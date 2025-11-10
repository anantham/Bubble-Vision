import Foundation
import RealityKit
import simd

/// Lightweight CPU topology cache for tracking adjacent-slice pairs and dirty seams.
/// Runs refinement passes at throttled intervals (e.g., 30 Hz) to update vertex alphas.
/// Reference: Phase 3 RealityKit-native seam band approach
final class SeamTopologyCache {

    // MARK: - Configuration

    /// Refinement update interval (seconds) - 30 Hz = ~33ms
    private let updateInterval: TimeInterval = 1.0 / 30.0

    /// Maximum number of dirty seams to process per update
    private let maxSeamsPerUpdate: Int = 32

    // MARK: - Data Structures

    struct AdjacentPair: Hashable {
        let sliceA: UUID
        let sliceB: UUID

        init(_ a: UUID, _ b: UUID) {
            // Normalize order for hashing
            if a.uuidString < b.uuidString {
                self.sliceA = a
                self.sliceB = b
            } else {
                self.sliceA = b
                self.sliceB = a
            }
        }
    }

    struct SeamInfo {
        var pair: AdjacentPair
        var distance: Float
        var isDirty: Bool
        var lastRefinedTime: TimeInterval
        var adjacencyThreshold: Float

        /// Compute overlap factor for seam blending (0 = no overlap, 1 = full overlap)
        var overlapFactor: Float {
            guard distance < adjacencyThreshold else { return 0 }
            return 1.0 - (distance / adjacencyThreshold)
        }
    }

    // MARK: - State

    private var adjacencyMap: [AdjacentPair: SeamInfo] = [:]
    private var dirtySeams: Set<AdjacentPair> = []
    private var lastUpdateTime: TimeInterval = 0
    private let adjacencyThreshold: Float

    // MARK: - Statistics

    private(set) var totalSeams: Int = 0
    private(set) var dirtySeamCount: Int = 0
    private(set) var lastRefinementDuration: TimeInterval = 0

    // MARK: - Init

    init(adjacencyThreshold: Float = 0.05) {
        self.adjacencyThreshold = adjacencyThreshold
    }

    // MARK: - Public Interface

    /// Update topology based on current slice ring state
    func updateTopology(slices: [SliceRing], currentTime: TimeInterval) {
        guard slices.count >= 2 else {
            adjacencyMap.removeAll()
            dirtySeams.removeAll()
            totalSeams = 0
            dirtySeamCount = 0
            return
        }

        var newAdjacencyMap: [AdjacentPair: SeamInfo] = [:]

        // Check all pairs of slices for adjacency
        for i in 0..<slices.count {
            for j in (i+1)..<slices.count {
                let sliceA = slices[i]
                let sliceB = slices[j]

                let dist = distance(sliceA.position, sliceB.position)

                // Only track if within threshold
                if dist < adjacencyThreshold {
                    let pair = AdjacentPair(sliceA.id, sliceB.id)

                    // Check if this is a new or changed adjacency
                    let isDirty: Bool
                    if let existing = adjacencyMap[pair] {
                        // Mark dirty if distance changed significantly
                        isDirty = abs(existing.distance - dist) > 0.005  // 5mm change threshold
                    } else {
                        // New adjacency, mark as dirty
                        isDirty = true
                    }

                    let seam = SeamInfo(
                        pair: pair,
                        distance: dist,
                        isDirty: isDirty,
                        lastRefinedTime: adjacencyMap[pair]?.lastRefinedTime ?? 0,
                        adjacencyThreshold: adjacencyThreshold
                    )

                    newAdjacencyMap[pair] = seam

                    if isDirty {
                        dirtySeams.insert(pair)
                    }
                }
            }
        }

        adjacencyMap = newAdjacencyMap
        totalSeams = adjacencyMap.count
        dirtySeamCount = dirtySeams.count
    }

    /// Process dirty seams and update vertex alphas (throttled to updateInterval)
    /// Returns true if refinement was performed
    @discardableResult
    func refineDirtySeams(currentTime: TimeInterval,
                          sliceMap: [UUID: SliceRing],
                          updateMesh: (UUID, [Float]) -> Void) -> Bool {
        guard currentTime - lastUpdateTime >= updateInterval else {
            return false
        }

        guard !dirtySeams.isEmpty else {
            return false
        }

        let startTime = CACurrentMediaTime()

        // Process limited number of dirty seams per update
        let seamsToProcess = Array(dirtySeams.prefix(maxSeamsPerUpdate))

        for pair in seamsToProcess {
            guard let seam = adjacencyMap[pair],
                  let sliceA = sliceMap[pair.sliceA],
                  let sliceB = sliceMap[pair.sliceB] else {
                continue
            }

            // Compute refined vertex alphas based on micro-SDF
            let alphasA = computeRefinedAlphas(for: sliceA, neighbor: sliceB, overlapFactor: seam.overlapFactor)
            let alphasB = computeRefinedAlphas(for: sliceB, neighbor: sliceA, overlapFactor: seam.overlapFactor)

            // Update meshes
            updateMesh(pair.sliceA, alphasA)
            updateMesh(pair.sliceB, alphasB)

            // Mark as refined
            adjacencyMap[pair]?.isDirty = false
            adjacencyMap[pair]?.lastRefinedTime = currentTime
            dirtySeams.remove(pair)
        }

        lastUpdateTime = currentTime
        lastRefinementDuration = CACurrentMediaTime() - startTime
        dirtySeamCount = dirtySeams.count

        return true
    }

    /// Get adjacency info for a specific slice
    func getAdjacentSeams(for sliceID: UUID) -> [SeamInfo] {
        return adjacencyMap.values.filter {
            $0.pair.sliceA == sliceID || $0.pair.sliceB == sliceID
        }
    }

    /// Clear all topology data
    func clear() {
        adjacencyMap.removeAll()
        dirtySeams.removeAll()
        totalSeams = 0
        dirtySeamCount = 0
    }

    // MARK: - Private Helpers

    /// Compute refined vertex alphas using micro-SDF approach
    private func computeRefinedAlphas(for slice: SliceRing,
                                      neighbor: SliceRing,
                                      overlapFactor: Float) -> [Float] {
        // Simple micro-SDF: reduce alpha near overlapping neighbor
        // This is a CPU-based refinement that tweaks the geometric seam band

        let segments = 32  // Match FilmPlaneBuilder segments
        let innerVertices = segments + 1
        let outerVertices = segments + 1
        let totalVertices = 1 + innerVertices + outerVertices  // center + inner + outer

        var alphas = [Float](repeating: 1.0, count: totalVertices)

        // Center vertex always full opacity
        alphas[0] = 1.0

        // Inner ring: slight reduction based on overlap
        for i in 1...innerVertices {
            let baseAlpha: Float = 1.0
            let reduction = overlapFactor * 0.3  // Max 30% reduction
            alphas[i] = max(0.0, baseAlpha - reduction)
        }

        // Outer ring: stronger quadratic falloff with overlap adjustment
        let outerStart = 1 + innerVertices
        for i in 0..<outerVertices {
            let t: Float = 1.0  // At edge
            var alpha = (1.0 - t) * (1.0 - t)  // Base quadratic falloff

            // Further reduce alpha near overlapping neighbor
            let overlapReduction = overlapFactor * 0.5
            alpha = max(0.0, alpha - overlapReduction)

            alphas[outerStart + i] = alpha
        }

        return alphas
    }
}

/// Extension to update mesh vertex alphas on ModelEntity
extension ModelEntity {

    /// Update vertex alphas for seam refinement
    /// Note: This requires mesh replacement due to RealityKit constraints
    func updateSeamAlphas(_ alphas: [Float], builder: FilmPlaneBuilder) {
        // RealityKit doesn't support direct vertex attribute updates
        // This is a placeholder for the mesh replacement flow
        // In practice, we'd need to regenerate the mesh with new alphas
        // and call MeshResource.replace(_:with:) which is throttled appropriately

        // TODO: Implement efficient mesh update strategy
        // Options:
        // 1. Batch updates and call MeshResource.replace() at 30 Hz
        // 2. Use instance rendering with per-instance opacity
        // 3. Pack alpha into texture and sample in shader
    }
}
