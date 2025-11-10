import Foundation
import Combine

/// User-tunable runtime settings for the Bubble Vision demo.
/// Settings are persisted via UserDefaults and broadcast through a shared manager.
struct AppSettings: Codable {
    enum QualityTier: String, Codable, CaseIterable, Identifiable {
        case auto
        case high
        case medium
        case low

        var id: String { rawValue }
    }

    var qualityTier: QualityTier = .auto
    var enableWobble: Bool = true
    var enableSeamSoftening: Bool = true
    var maxBubbles: Int = 100
    var visualFX: VisualFXSettings = .default

    static let `default` = AppSettings()
}

/// Centralised settings manager with debounced persistence.
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published private(set) var current: AppSettings

    private let saveQueue = DispatchQueue(label: "com.bubblevision.settings", qos: .utility)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let defaultsKey = "AppSettings.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? decoder.decode(AppSettings.self, from: data) {
            current = decoded
        } else {
            current = .default
        }
    }

    /// Mutate settings on the main queue and schedule a debounced persistence update.
    func update(_ block: (inout AppSettings) -> Void) {
        block(&current)
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let data = try self.encoder.encode(self.current)
                UserDefaults.standard.set(data, forKey: self.defaultsKey)
            } catch {
                print("⚠️ Failed to persist settings: \(error)")
            }
        }

        pendingSaveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + .milliseconds(250), execute: workItem)
    }
}
