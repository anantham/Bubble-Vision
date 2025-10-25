//
//  ARCoordinator.swift
//  Bubble Vision
//
//  Core AR session management, tracking gating, and persistence
//

import Foundation
import ARKit
import RealityKit
import Combine
import Metal

final class ARCoordinator: NSObject, ObservableObject {
    // MARK: - Published State

    /// True when tracking is normal AND world is mapped/extending
    @Published var isReady = false

    /// User-facing status message
    @Published var statusMessage = "Initializing AR..."

    /// Number of bubbles currently placed
    @Published var bubbleCount = 0

    // MARK: - Internal State

    weak var arView: ARView?
    private var sessionState = SessionState()
    private var bubbleEntities: [UUID: AnchorEntity] = [:]

    private let maxBubbles = 100

    // Add after existing properties
    private let motionCoupler = MotionCoupler()

    // MARK: - File URLs

    private var worldMapURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("worldMap.ardata")
    }

    private var sessionURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("session.json")
    }

    // MARK: - Session Lifecycle

    /// Start a fresh AR session (no world map)
    func run(in arView: ARView) {
        self.arView = arView

        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic

        // Enable scene reconstruction on LiDAR devices
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        // Enable plane detection as fallback for placement
        config.planeDetection = [.horizontal, .vertical]

        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        motionCoupler.start()

        statusMessage = "Scanning environment..."
    }

    /// Load persisted ARWorldMap and bubbles, then run session
    func loadStateAndRun(in arView: ARView) {
        self.arView = arView

        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        config.planeDetection = [.horizontal, .vertical]

        // Attempt to load world map
        if let data = try? Data(contentsOf: worldMapURL),
           let map = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) {
            config.initialWorldMap = map
            statusMessage = "Relocalizing to saved map..."
        } else {
            statusMessage = "No saved map found. Scanning..."
        }

        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        motionCoupler.start()

        // Load saved bubbles
        if let bubblesData = try? Data(contentsOf: sessionURL),
           let state = try? JSONDecoder().decode(SessionState.self, from: bubblesData) {
            sessionState = state

            // Reconstructing bubbles after relocalization succeeds happens in the session delegate
        }
    }

    /// Save current ARWorldMap and bubble anchors to disk
    func saveState() {
        guard let arView = arView else { return }

        arView.session.getCurrentWorldMap { [weak self] map, error in
            guard let self = self, let map = map else {
                print("Failed to get world map: \(String(describing: error))")
                return
            }

            // Save world map
            if let mapData = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true) {
                try? mapData.write(to: self.worldMapURL)
                print("✅ Saved world map")
            }

            // Save bubbles
            if let sessionData = try? JSONEncoder().encode(self.sessionState) {
                try? sessionData.write(to: self.sessionURL)
                print("✅ Saved \(self.sessionState.bubbles.count) bubbles")
            }
        }
    }

    /// Pause the session (e.g., app backgrounded)
    func pause() {
        arView?.session.pause()
    }

    // MARK: - Bubble Placement

    /// Place a new bubble pane at the camera's position, offset forward
    func placeBubble() {
        guard let arView = arView,
              let frame = arView.session.currentFrame,
              isReady else { return }

        // Check bubble cap
        if sessionState.bubbles.count >= maxBubbles {
            // Remove oldest
            if let oldest = sessionState.bubbles.min(by: { $0.createdAt < $1.createdAt }) {
                removeBubble(id: oldest.id)
            }
        }

        // Compute placement transform
        var cameraTransform = frame.camera.transform
        let forward = normalize(simd_float3(-cameraTransform.columns.2.x,
                                             -cameraTransform.columns.2.y,
                                             -cameraTransform.columns.2.z))
        let position = simd_make_float3(cameraTransform.columns.3) + forward * 0.8
        cameraTransform.columns.3 = simd_float4(position, 1)

        // Create bubble model
        let bubbleData = BubbleAnchor(transform: cameraTransform)
        sessionState.bubbles.append(bubbleData)

        // Create entity
        createBubbleEntity(from: bubbleData)

        bubbleCount = sessionState.bubbles.count
    }

    /// Remove a bubble by ID
    private func removeBubble(id: UUID) {
        sessionState.bubbles.removeAll { $0.id == id }

        if let entity = bubbleEntities[id] {
            arView?.scene.removeAnchor(entity)
            bubbleEntities.removeValue(forKey: id)
        }

        bubbleCount = sessionState.bubbles.count
    }

    // MARK: - Entity Creation

    /// Create and add a bubble entity to the scene
    private func createBubbleEntity(from bubble: BubbleAnchor) {
        guard let arView = arView else { return }

        let anchor = AnchorEntity(world: bubble.transform.matrix)

        // Generate plane mesh with rounded corners
        let mesh = MeshResource.generatePlane(width: bubble.size.x,
                                               height: bubble.size.y,
                                               cornerRadius: 0.02)

        // Create iridescent material
        var material: Material
        do {
            // Get the default Metal library (contains our shader)
            guard let device = MTLCreateSystemDefaultDevice(),
                  let library = device.makeDefaultLibrary() else {
                throw NSError(domain: "CustomMaterial", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load Metal library"])
            }

            let surfaceShader = CustomMaterial.SurfaceShader(named: "IridescentSurface", in: library)
            var customMat = try CustomMaterial(surfaceShader: surfaceShader, lightingModel: .lit)

            // Pass custom parameters (hueSeed in x, reserve y/z/w for future use)
            customMat.custom.value = SIMD4<Float>(bubble.hueSeed, 0, 0, 0)
            material = customMat
        } catch {
            // Fallback to simple transparent material
            print("⚠️ CustomMaterial failed, using fallback: \(error)")
            var simpleMat = SimpleMaterial()
            simpleMat.color = .init(tint: .white.withAlphaComponent(0.3))
            simpleMat.roughness = .init(floatLiteral: 0.1)
            simpleMat.metallic = .init(floatLiteral: 0.0)
            material = simpleMat
        }

        let paneEntity = ModelEntity(mesh: mesh, materials: [material])
        anchor.addChild(paneEntity)

        arView.scene.addAnchor(anchor)
        bubbleEntities[bubble.id] = anchor

        print("🫧 Placed bubble \(bubble.id)")
    }

    /// Reconstruct all saved bubbles (called after relocalization)
    private func reconstructAllBubbles() {
        guard let arView = arView else { return }

        // Clear existing entities
        bubbleEntities.values.forEach { arView.scene.removeAnchor($0) }
        bubbleEntities.removeAll()

        // Recreate from session state
        sessionState.bubbles.forEach(createBubbleEntity(from:))

        bubbleCount = sessionState.bubbles.count
        print("♻️ Reconstructed \(bubbleCount) bubbles")
    }
}

// MARK: - ARSessionDelegate

extension ARCoordinator: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update motion coupling
        motionCoupler.update(from: frame)

        // Determine tracking state
        let trackingOK: Bool = {
            if case .normal = frame.camera.trackingState {
                return true
            } else {
                return false
            }
        }()

        // Determine mapping state
        let mappedOK = (frame.worldMappingStatus == .mapped ||
                        frame.worldMappingStatus == .extending)

        let newIsReady = trackingOK && mappedOK

        // Update status message
        var newMessage = statusMessage
        if !trackingOK {
            switch frame.camera.trackingState {
            case .limited(let reason):
                switch reason {
                case .excessiveMotion:
                    newMessage = "Move slower"
                case .insufficientFeatures:
                    newMessage = "Find a textured area"
                case .initializing:
                    newMessage = "Initializing tracking..."
                case .relocalizing:
                    newMessage = "Relocalizing..."
                @unknown default:
                    newMessage = "Tracking limited"
                }
            case .notAvailable:
                newMessage = "Tracking unavailable"
            default:
                break
            }
        } else if !mappedOK {
            switch frame.worldMappingStatus {
            case .notAvailable:
                newMessage = "Mapping not available"
            case .limited:
                newMessage = "Keep scanning environment..."
            default:
                break
            }
        } else {
            newMessage = "Ready to blow bubbles!"
        }

        // Publish on main thread
        DispatchQueue.main.async { [weak self] in
            self?.isReady = newIsReady
            self?.statusMessage = newMessage
        }

        // If we just became ready and have saved bubbles but no entities, reconstruct
        if newIsReady,
           !sessionState.bubbles.isEmpty,
           bubbleEntities.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.reconstructAllBubbles()
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "Session failed: \(error.localizedDescription)"
            self?.isReady = false
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "Session interrupted"
            self?.isReady = false
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "Resuming session..."
        }
    }
}
