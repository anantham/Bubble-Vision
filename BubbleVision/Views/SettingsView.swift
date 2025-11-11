import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        NavigationStack {
            Form {
                qualitySection
                wobbleSection
                visualFXSection
                limitsSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var qualitySection: some View {
        Section("Quality") {
            Picker("Quality Tier", selection: Binding(
                get: { settingsManager.current.qualityTier },
                set: { tier in
                    settingsManager.update { $0.qualityTier = tier }
                }
            )) {
                ForEach(AppSettings.QualityTier.allCases) { tier in
                    Text(tier.rawValue.capitalized).tag(tier)
                }
            }
        }
    }

    private var wobbleSection: some View {
        Section("Physics") {
            Toggle("Enable Wobble", isOn: Binding(
                get: { settingsManager.current.enableWobble },
                set: { newValue in
                    settingsManager.update { $0.enableWobble = newValue }
                }
            ))

            Toggle("Seam Softening", isOn: Binding(
                get: { settingsManager.current.enableSeamSoftening },
                set: { newValue in
                    settingsManager.update { $0.enableSeamSoftening = newValue }
                }
            ))
        }
    }

    private var visualFXSection: some View {
        Section("Visual Effects") {
            Toggle("Enable Effects", isOn: Binding(
                get: { settingsManager.current.visualFX.enabled },
                set: { newValue in
                    settingsManager.update { $0.visualFX.enabled = newValue }
                }
            ))

            if settingsManager.current.visualFX.enabled {
                // Phase 4: Updated FX toggles
                effectToggle("✨ Sparkles", flag: VisualFXSettings.sparkles)
                effectToggle("🌈 Chromatic Aberration", flag: VisualFXSettings.chromatic)
                effectToggle("🔭 Camera Refraction", flag: VisualFXSettings.refraction)
                effectToggle("💫 Rim Glow", flag: VisualFXSettings.rimGlow)
                effectToggle("☁️ Dust Motes", flag: VisualFXSettings.dustMotes)
                effectToggle("✨ Halo Bloom", flag: VisualFXSettings.haloBloom)
                effectToggle("〰️ Micro Ripples", flag: VisualFXSettings.microRipples)

                Text("FX modulated by wobble intensity and gravity")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func effectToggle(_ label: String, flag: UInt8) -> some View {
        Toggle(label, isOn: Binding(
            get: { (settingsManager.current.visualFX.effectsMask & flag) != 0 },
            set: { _ in
                settingsManager.update { $0.visualFX.toggleEffect(flag) }
            }
        ))
    }

    private var limitsSection: some View {
        Section("Limits") {
            Stepper(
                value: Binding(
                    get: { settingsManager.current.maxBubbles },
                    set: { value in
                        settingsManager.update { $0.maxBubbles = value }
                    }
                ),
                in: 10...200,
                step: 10
            ) {
                Text("Max Bubbles: \(settingsManager.current.maxBubbles)")
            }
        }
    }
}

