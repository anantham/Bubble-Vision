import Foundation
import SwiftUI
import Combine

/// Instrumentation and debug metrics for seam softening validation
/// Provides EMA-smoothed metrics and debug visualization controls
final class SeamInstrumentation: ObservableObject {

    // MARK: - Debug Controls

    @Published var debugMode: DebugMode = .off
    @Published var showMetricsHUD: Bool = false

    enum DebugMode {
        case off                  // Normal rendering
        case seamOnly             // Show only seam bands (highlight alpha falloff)
        case topologyOverlay      // Overlay adjacency graph
        case dirtySeamsOnly       // Show only dirty seams
        case vertexAlphaHeatmap   // Color-code vertex alphas
    }

    // MARK: - Metrics (EMA Smoothed)

    @Published private(set) var fps: Double = 60.0
    @Published private(set) var meshUpdateDuration: Double = 0.0  // milliseconds
    @Published private(set) var totalSeams: Int = 0
    @Published private(set) var dirtySeams: Int = 0
    @Published private(set) var refinementRate: Double = 0.0  // Hz

    // MARK: - EMA State

    private let emaAlpha: Double = 0.1  // 10% weight to new samples
    private var fpsEMA: Double = 60.0
    private var meshUpdateEMA: Double = 0.0
    private var refinementRateEMA: Double = 0.0

    // Frame timing
    private var lastFrameTime: TimeInterval = 0
    private var lastRefinementTime: TimeInterval = 0

    // MARK: - Safety Net Thresholds

    private let maxMeshUpdateDuration: Double = 1.5  // milliseconds
    private let minFPS: Double = 55.0

    struct SafetyNetStatus {
        var meshUpdateExceeded: Bool = false
        var fpsDropped: Bool = false
        var message: String = ""

        var isHealthy: Bool {
            !meshUpdateExceeded && !fpsDropped
        }
    }

    @Published private(set) var safetyStatus = SafetyNetStatus()

    // MARK: - Update Methods

    /// Update FPS metric with EMA smoothing
    func updateFPS(currentTime: TimeInterval) {
        guard lastFrameTime > 0 else {
            lastFrameTime = currentTime
            return
        }

        let deltaTime = currentTime - lastFrameTime
        guard deltaTime > 0 else { return }

        let instantFPS = 1.0 / deltaTime
        fpsEMA = emaAlpha * instantFPS + (1.0 - emaAlpha) * fpsEMA
        fps = fpsEMA

        // Check safety threshold
        safetyStatus.fpsDropped = fpsEMA < minFPS
        lastFrameTime = currentTime
    }

    /// Update mesh update duration (call after MeshResource.replace)
    func recordMeshUpdate(duration: TimeInterval) {
        let durationMS = duration * 1000.0  // Convert to milliseconds
        meshUpdateEMA = emaAlpha * durationMS + (1.0 - emaAlpha) * meshUpdateEMA
        meshUpdateDuration = meshUpdateEMA

        // Check safety threshold
        safetyStatus.meshUpdateExceeded = meshUpdateEMA > maxMeshUpdateDuration
    }

    /// Update seam statistics from topology cache
    func updateSeamStats(total: Int, dirty: Int, currentTime: TimeInterval) {
        totalSeams = total
        dirtySeams = dirty

        // Calculate refinement rate
        if lastRefinementTime > 0 {
            let deltaTime = currentTime - lastRefinementTime
            if deltaTime > 0 {
                let instantRate = 1.0 / deltaTime
                refinementRateEMA = emaAlpha * instantRate + (1.0 - emaAlpha) * refinementRateEMA
                refinementRate = refinementRateEMA
            }
        }
        lastRefinementTime = currentTime
    }

    /// Update safety status message
    func updateSafetyMessage() {
        var messages: [String] = []

        if safetyStatus.fpsDropped {
            messages.append("⚠️ FPS below \(minFPS)")
        }

        if safetyStatus.meshUpdateExceeded {
            messages.append("⚠️ Mesh update > \(maxMeshUpdateDuration)ms")
        }

        safetyStatus.message = messages.isEmpty ? "✓ Healthy" : messages.joined(separator: ", ")
    }

    /// Reset all metrics
    func reset() {
        fpsEMA = 60.0
        meshUpdateEMA = 0.0
        refinementRateEMA = 0.0
        fps = 60.0
        meshUpdateDuration = 0.0
        totalSeams = 0
        dirtySeams = 0
        refinementRate = 0.0
        safetyStatus = SafetyNetStatus()
    }
}

// MARK: - HUD View

/// Debug HUD for displaying seam instrumentation metrics
struct SeamInstrumentationHUD: View {
    @ObservedObject var instrumentation: SeamInstrumentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Seam Instrumentation")
                .font(.headline)
                .foregroundColor(.white)

            Divider().background(Color.white)

            // Performance Metrics
            Group {
                metricRow("FPS", String(format: "%.1f", instrumentation.fps),
                         warning: instrumentation.safetyStatus.fpsDropped)
                metricRow("Mesh Update", String(format: "%.2f ms", instrumentation.meshUpdateDuration),
                         warning: instrumentation.safetyStatus.meshUpdateExceeded)
            }

            Divider().background(Color.white.opacity(0.5))

            // Seam Metrics
            Group {
                metricRow("Total Seams", "\(instrumentation.totalSeams)", warning: false)
                metricRow("Dirty Seams", "\(instrumentation.dirtySeams)", warning: false)
                metricRow("Refinement Rate", String(format: "%.1f Hz", instrumentation.refinementRate), warning: false)
            }

            Divider().background(Color.white.opacity(0.5))

            // Safety Status
            HStack {
                Text("Status:")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text(instrumentation.safetyStatus.message)
                    .font(.caption.bold())
                    .foregroundColor(instrumentation.safetyStatus.isHealthy ? .green : .orange)
            }

            // Debug Mode Selector
            Divider().background(Color.white.opacity(0.5))

            Picker("Debug Mode", selection: $instrumentation.debugMode) {
                Text("Off").tag(SeamInstrumentation.DebugMode.off)
                Text("Seam Only").tag(SeamInstrumentation.DebugMode.seamOnly)
                Text("Topology").tag(SeamInstrumentation.DebugMode.topologyOverlay)
                Text("Dirty").tag(SeamInstrumentation.DebugMode.dirtySeamsOnly)
                Text("Alpha Heat").tag(SeamInstrumentation.DebugMode.vertexAlphaHeatmap)
            }
            .pickerStyle(MenuPickerStyle())
            .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
        .shadow(radius: 5)
    }

    private func metricRow(_ label: String, _ value: String, warning: Bool) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundColor(warning ? .orange : .white)
        }
    }
}

// MARK: - Debug Shader Support

extension SeamInstrumentation {

    /// Get debug visualization flags for shader
    func debugFlags() -> UInt32 {
        switch debugMode {
        case .off:
            return 0
        case .seamOnly:
            return 1 << 0
        case .topologyOverlay:
            return 1 << 1
        case .dirtySeamsOnly:
            return 1 << 2
        case .vertexAlphaHeatmap:
            return 1 << 3
        }
    }
}

// MARK: - Failure Cookbook Entry

extension SeamInstrumentation {

    /// Known failure modes and remediation
    struct FailureCookbook {
        static let entries: [(symptom: String, cause: String, fix: String)] = [
            ("Visible halo around seam edges",
             "Vertex alpha falloff too steep",
             "Increase seam band width from 2cm to 3cm"),

            ("Flicker during camera movement",
             "Mesh updates not throttled properly",
             "Ensure refinement capped at 30 Hz"),

            ("Cracks appear at sharp angles",
             "Edge rim pass not covering gap",
             "Increase rim width or depth bias"),

            ("Seams darken over time",
             "Dirty seam counter growing unbounded",
             "Implement LRU eviction in topology cache"),

            ("FPS drops below 55",
             "Too many seams being refined per frame",
             "Reduce maxSeamsPerUpdate from 32 to 16"),

            ("Mesh updates > 1.5ms",
             "MeshResource.replace() called too frequently",
             "Batch updates and increase throttle interval")
        ]
    }

    /// Get relevant failure cookbook entry based on current metrics
    func suggestFix() -> String? {
        if safetyStatus.fpsDropped {
            return FailureCookbook.entries.first { $0.symptom.contains("FPS") }?.fix
        }

        if safetyStatus.meshUpdateExceeded {
            return FailureCookbook.entries.first { $0.symptom.contains("Mesh") }?.fix
        }

        return nil
    }
}
