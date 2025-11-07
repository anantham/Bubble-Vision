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
import UIKit

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

    private let settingsManager = SettingsManager.shared
    private var cancellables: Set<AnyCancellable> = []
    private let joltFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    private var maxBubbles: Int {
        settingsManager.current.maxBubbles
    }
    private var wobbleGrid: WobbleGrid?
    private var wobbleTexture: TextureResource?
    private var metalDevice: MTLDevice?

    private let motionCoupler = MotionCoupler()
    private var filmPlaneBuilder: FilmPlaneBuilder?
    private var tileManager: TileManager?
    private let pathTracker = PathTracker()
    private let sliceRingBuffer = SliceRingBuffer()
    private var trailSliceEntities: [UUID: ModelEntity] = [:]  // entity lookup by slice ID
    private var lastPaintPosition: SIMD3<Float>?
    private var cacheMeshEntities: [(anchor: AnchorEntity, tileId: Int, epoch: UInt32)] = []
    private var framesSinceExtraction: Int = 0
    private let extractionCadence: Int = 10
    private var trailSliceBaselineCount: Int = 0

    // Trail mode state
    @Published public var isTrailMode: Bool = false
    public var sliceCount: Int { sessionState.trailSlices.count }

    override init() {
        super.init()
        settingsManager.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.applySettings(settings)
            }
            .store(in: &cancellables)
    }

    // MARK: - File URLs

    private var worldMapURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("worldMap.ardata")
    }

    private var sessionURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("session.json")
    }

    // MARK: - Private Helpers

    /// Setup film plane builder with Metal device
    private func setupFilmPlaneBuilder() {
        if let device = MTLCreateSystemDefaultDevice() {
            do {
                metalDevice = device
                filmPlaneBuilder = try FilmPlaneBuilder(device: device, apertureShape: .circle(radius: 0.15))
                if tileManager == nil {
                    tileManager = TileManager(device: device)
                    print("✓ TileManager initialized (\(tileManager?.tileCount ?? 0) tiles × 64³ voxels)")
                }
                createWobbleGridIfNeeded()
                applySettings(settingsManager.current)
            } catch {
                print("⚠️ Failed to create FilmPlaneBuilder: \(error)")
            }
        } else {
            print("⚠️ Failed to create Metal device - film plane features disabled")
        }
    }

    private func applySettings(_ settings: AppSettings) {
        if settings.enableWobble {
            createWobbleGridIfNeeded()
        } else {
            wobbleGrid = nil
            wobbleTexture = nil
        }
        updateSceneMaterials()
    }

    private func createWobbleGridIfNeeded() {
        guard wobbleGrid == nil,
              let device = metalDevice,
              settingsManager.current.enableWobble else { return }

        wobbleGrid = WobbleGrid(device: device)
        refreshWobbleTextureResource()
    }

    private func refreshWobbleTextureResource() {
        guard let texture = wobbleGrid?.displacementTexture else {
            wobbleTexture = nil
            return
        }

        do {
            wobbleTexture = try TextureResource(from: texture)
        } catch {
            wobbleTexture = nil
            print("⚠️ Failed to create wobble texture resource: \(error)")
        }
    }

    private func updateSceneMaterials() {
        let apply: (ModelEntity) -> Void = { [weak self] entity in
            guard let self,
                  var material = entity.model?.materials.first as? CustomMaterial else { return }
            self.configureMaterial(&material)
            entity.model?.materials[0] = material
        }

        trailSliceEntities.values.forEach(apply)
        cacheMeshEntities.forEach { tuple in
            tuple.anchor.children.compactMap { $0 as? ModelEntity }.forEach(apply)
        }
    }

    private func configureMaterial(_ material: inout CustomMaterial) {
        if settingsManager.current.enableWobble, let wobbleTexture {
            material.custom.texture = CustomMaterial.Texture(wobbleTexture)
        } else {
            material.custom.texture = nil
        }

        material.custom.value = makeCustomValueVector()
    }

    private func makeCustomValueVector() -> SIMD4<Float> {
        let fx = settingsManager.current.visualFX
        var packedMask: UInt32 = settingsManager.current.enableSeamSoftening ? (1 << 7) : 0

        if fx.enabled {
            packedMask |= UInt32(fx.effectsMask)
        }

        let intensity = fx.enabled ? fx.intensity : 0.0
        let param2 = fx.enabled ? fx.param2 : 0.0
        let param3 = fx.enabled ? fx.param3 : 0.0

        return SIMD4<Float>(Float(packedMask), intensity, param2, param3)
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
        setupFilmPlaneBuilder()
        joltFeedbackGenerator.prepare()

        DispatchQueue.main.async {
            self.statusMessage = "Scanning environment..."
        }
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
            DispatchQueue.main.async {
                self.statusMessage = "Relocalizing to saved map..."
            }
        } else {
            DispatchQueue.main.async {
                self.statusMessage = "No saved map found. Scanning..."
            }
        }

        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        motionCoupler.start()
        setupFilmPlaneBuilder()
        joltFeedbackGenerator.prepare()

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

            // Save session (bubbles + trail slices)
            if let sessionData = try? JSONEncoder().encode(self.sessionState) {
                try? sessionData.write(to: self.sessionURL)
                print("✅ Saved session (\(self.sessionState.bubbles.count) bubbles + \(self.sessionState.trailSlices.count) slices)")
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

        // Test: Create film plane
        if let builder = filmPlaneBuilder {
            do {
                let filmEntity = try builder.createFilmPlane(cameraTransform: frame.camera.transform)
                if var material = filmEntity.model?.materials.first as? CustomMaterial {
                    configureMaterial(&material)
                    filmEntity.model?.materials[0] = material
                }

                // Add to scene
                let anchor = AnchorEntity(world: frame.camera.transform)
                anchor.addChild(filmEntity)
                arView.scene.addAnchor(anchor)

                print("✓ Film plane created")
            } catch {
                print("⚠️ Failed to create film plane: \(error)")
            }
        }

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

    /// Reconstruct all saved bubbles and trail slices (called after relocalization)
    private func reconstructAllBubbles() {
        guard let arView = arView else { return }

        // Clear existing entities
        bubbleEntities.values.forEach { arView.scene.removeAnchor($0) }
        bubbleEntities.removeAll()
        trailSliceEntities.values.forEach { $0.parent?.removeFromParent() }
        trailSliceEntities.removeAll()

        sliceRingBuffer.clear()

        // Recreate MVP bubbles from session state
        sessionState.bubbles.forEach(createBubbleEntity(from:))
        bubbleCount = sessionState.bubbles.count

        // Recreate trail slices from session state
        sessionState.trailSlices.forEach(createTrailSliceEntity(from:))

        print("♻️ Reconstructed \(bubbleCount) bubbles + \(sessionState.trailSlices.count) slices")
    }

    /// Create and add a trail slice entity to the scene
    private func createTrailSliceEntity(from slice: TrailSlice) {
        guard let arView = arView, let builder = filmPlaneBuilder else { return }

        do {
            let filmEntity = try builder.createFilmPlane(cameraTransform: slice.transform.matrix)
            if var material = filmEntity.model?.materials.first as? CustomMaterial {
                configureMaterial(&material)
                filmEntity.model?.materials[0] = material
            }
            let anchor = AnchorEntity(world: slice.transform.matrix)
            anchor.addChild(filmEntity)
            arView.scene.addAnchor(anchor)
            trailSliceEntities[slice.id] = filmEntity

            let matrix = slice.transform.matrix
            let position = SIMD3<Float>(matrix.columns.3.x,
                                        matrix.columns.3.y,
                                        matrix.columns.3.z)
            sliceRingBuffer.addSlice(position: position, timestamp: slice.createdAt.timeIntervalSince1970)
        } catch {
            print("⚠️ Failed to reconstruct trail slice: \(error)")
        }
    }

    // MARK: - Trail Tracking

    func toggleTrailMode() {
        isTrailMode.toggle()

        if isTrailMode {
            // Entering trail mode
            trailSliceBaselineCount = sessionState.trailSlices.count
            guard let frame = arView?.session.currentFrame else { return }
            pathTracker.startTracking(
                initialTransform: frame.camera.transform,
                timestamp: frame.timestamp
            )

            lastPaintPosition = SIMD3<Float>(
                frame.camera.transform.columns.3.x,
                frame.camera.transform.columns.3.y,
                frame.camera.transform.columns.3.z
            )
            if let startPosition = lastPaintPosition {
                sliceRingBuffer.addSlice(position: startPosition, timestamp: frame.timestamp)
            }
            framesSinceExtraction = 0

            // Spawn initial slice immediately (so user sees something)
            spawnSlice(at: frame.camera.transform)

            // Haptic feedback for mode toggle
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            print("▶ Trail mode ACTIVATED (slice spawned at current position)")
        } else {
            // Exiting trail mode
            endTrail()

            // Haptic feedback for mode toggle
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        }
    }

    private func spawnSlice(at transform: simd_float4x4) {
        guard let builder = filmPlaneBuilder else { return }

        do {
            // Create slice data model
            let adjustedTransform = smoothedSliceTransform(from: transform)
            let sliceData = TrailSlice(transform: adjustedTransform)
            sessionState.trailSlices.append(sliceData)

            // Create entity
            let filmEntity = try builder.createFilmPlane(cameraTransform: adjustedTransform)
            if var material = filmEntity.model?.materials.first as? CustomMaterial {
                configureMaterial(&material)
                filmEntity.model?.materials[0] = material
            }
            let anchor = AnchorEntity(world: adjustedTransform)
            anchor.addChild(filmEntity)
            arView?.scene.addAnchor(anchor)
            trailSliceEntities[sliceData.id] = filmEntity

            // Subtle haptic on slice spawn
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()

            print("• Slice spawned (\(sessionState.trailSlices.count) total)")
        } catch {
            print("⚠️ Failed to create film plane slice: \(error)")
        }
    }

    func updateTrail() {
        guard let frame = arView?.session.currentFrame else { return }

        let cameraPos = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )

        if lastPaintPosition == nil {
            lastPaintPosition = cameraPos
        }

        if pathTracker.update(transform: frame.camera.transform, timestamp: frame.timestamp) {
            if let previous = lastPaintPosition {
                tileManager?.paintSegment(
                    from: previous,
                    to: cameraPos,
                    aperture: .circle(radius: 0.15),
                    cameraTransform: frame.camera.transform
                )
            }

            sliceRingBuffer.addSlice(position: cameraPos, timestamp: frame.timestamp)
            spawnSlice(at: frame.camera.transform)
            lastPaintPosition = cameraPos
        }
    }

    func endTrail() {
        let path = pathTracker.stopTracking()
        print("■ Trail mode DEACTIVATED (\(path.count) samples, \(sessionState.trailSlices.count) slices)")
        trailSliceBaselineCount = sessionState.trailSlices.count
        lastPaintPosition = nil
        extractCacheMeshes(force: true)
    }

    // MARK: - Volume Cache Rendering

    private func extractCacheMeshes(force: Bool = false) {
        guard let tileManager = tileManager else { return }

        if force {
            framesSinceExtraction = 0
        }

        var results: [(vertices: [TileManager.Vertex], indices: [UInt32], frame: TileFrame, tileIndex: Int)] = []
        var emptyTiles: [Int] = []

        for index in 0..<tileManager.tileCount {
            if let mesh = tileManager.extractMesh(from: index) {
                results.append((mesh.vertices, mesh.indices, mesh.frame, index))
            } else {
                emptyTiles.append(index)
            }
        }

        guard !results.isEmpty || !emptyTiles.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            self?.removeCacheMeshes(for: emptyTiles)
            self?.installCacheMeshes(results)
        }
    }

    private func installCacheMeshes(_ meshes: [(vertices: [TileManager.Vertex], indices: [UInt32], frame: TileFrame, tileIndex: Int)]) {
        guard let arView = arView else { return }
        guard let tileManager = tileManager else { return }

        for mesh in meshes {
            guard let currentFrame = tileManager.getTileFrame(at: mesh.tileIndex) else {
                #if DEBUG
                print("⏭️ Skipped installing cache mesh for tile \(mesh.tileIndex) because frame is unavailable")
                #endif
                continue
            }

            guard currentFrame.epoch == mesh.frame.epoch else {
                #if DEBUG
                print("⏭️ Skipped installing cache mesh for tile \(mesh.tileIndex) due to epoch mismatch (\(mesh.frame.epoch) -> \(currentFrame.epoch))")
                #endif
                continue
            }

            let existing = cacheMeshEntities.filter { $0.tileId == mesh.tileIndex }
            existing.forEach { arView.scene.removeAnchor($0.anchor) }
            cacheMeshEntities.removeAll { $0.tileId == mesh.tileIndex }

            var descriptor = MeshDescriptor()
            descriptor.positions = MeshBuffer(mesh.vertices.map { $0.position })
            descriptor.normals = MeshBuffer(mesh.vertices.map { $0.normal })
            descriptor.textureCoordinates = MeshBuffer(mesh.vertices.map { $0.uv })
            descriptor.primitives = .triangles(mesh.indices)

            guard let meshResource = try? MeshResource.generate(from: [descriptor]) else {
                continue
            }

            let entity = ModelEntity(mesh: meshResource)
            if var material = filmPlaneBuilder?.sharedMaterial {
                configureMaterial(&material)
                entity.model?.materials = [material]
            } else {
                let fallback = SimpleMaterial(color: .white, roughness: 0.2, isMetallic: false)
                entity.model?.materials = [fallback]
            }

            let anchor = AnchorEntity(world: matrix_identity_float4x4)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)

            cacheMeshEntities.append((anchor: anchor, tileId: mesh.tileIndex, epoch: mesh.frame.epoch))
        }
    }

    private func removeCacheMeshes(for tileIndices: [Int]) {
        guard let arView = arView, !tileIndices.isEmpty else { return }

        for tileIndex in tileIndices {
            let matches = cacheMeshEntities.filter { $0.tileId == tileIndex }
            matches.forEach { arView.scene.removeAnchor($0.anchor) }
            cacheMeshEntities.removeAll { $0.tileId == tileIndex }
        }
    }

    func clearAllSlices() {
        let sliceCount = sessionState.trailSlices.count
        let bubbleCount = sessionState.bubbles.count
        let totalCount = sliceCount + bubbleCount
        guard totalCount > 0 else { return }

        // Remove all trail slices from scene
        trailSliceEntities.values.forEach { entity in
            entity.parent?.removeFromParent()
        }
        trailSliceEntities.removeAll()
        sessionState.trailSlices.removeAll()
        sliceRingBuffer.clear()
        trailSliceBaselineCount = 0

        cacheMeshEntities.forEach { anchor in
            arView?.scene.removeAnchor(anchor.anchor)
        }
        cacheMeshEntities.removeAll()

        // Remove all MVP bubbles from scene
        bubbleEntities.values.forEach { entity in
            arView?.scene.removeAnchor(entity)
        }
        bubbleEntities.removeAll()
        sessionState.bubbles.removeAll()
        self.bubbleCount = 0

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        print("🗑️ Cleared everything (\(sliceCount) slices + \(bubbleCount) MVP bubbles)")
    }
}

// MARK: - Seam Softening Helpers

private extension ARCoordinator {
    func smoothedSliceTransform(from transform: simd_float4x4) -> simd_float4x4 {
        guard settingsManager.current.enableSeamSoftening else { return transform }
        let existingSliceCount = sessionState.trailSlices.count
        guard existingSliceCount > trailSliceBaselineCount,
              let lastMatrix = sessionState.trailSlices.last?.transform.matrix else {
            return transform
        }

        let previousRotation = simd_quatf(lastMatrix)
        let currentRotation = simd_quatf(transform)
        let blendedRotation = simd_slerp(previousRotation, currentRotation, 0.35)

        var result = simd_float4x4(blendedRotation)
        result.columns.3 = transform.columns.3
        return result
    }
}

// MARK: - ARSessionDelegate

extension ARCoordinator: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update motion coupling
        motionCoupler.update(from: frame)
        if motionCoupler.detectJolt() {
            DispatchQueue.main.async {
                self.joltFeedbackGenerator.impactOccurred()
            }
        }

        if settingsManager.current.enableWobble,
           let grid = wobbleGrid {
            grid.update(dt: 1.0 / 60.0, externalAcceleration: motionCoupler.accelSmoothed2D)
        }

        let cameraTransform = frame.camera.transform
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        if let movedTiles = tileManager?.updateTilePositions(cameraPosition: cameraPosition),
           !movedTiles.isEmpty {
            removeCacheMeshes(for: movedTiles)
        }

        // Update trail if tracking
        if pathTracker.tracking {
            updateTrail()

            framesSinceExtraction += 1
            if framesSinceExtraction >= extractionCadence {
                extractCacheMeshes()
                framesSinceExtraction = 0
            }
        } else if framesSinceExtraction != 0 {
            framesSinceExtraction = 0
        }

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
