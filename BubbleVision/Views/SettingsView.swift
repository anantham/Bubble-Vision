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
                effectToggle("Color Shift", flag: VisualFXSettings.colorShift)
                effectToggle("Vignette", flag: VisualFXSettings.vignette)
                effectToggle("Chromatic Aberration", flag: VisualFXSettings.chromaticAberration)
                effectToggle("Scanlines", flag: VisualFXSettings.scanlines)
                effectToggle("Glitch", flag: VisualFXSettings.glitch)
                effectToggle("Edge Glow", flag: VisualFXSettings.edgeGlow)
                effectToggle("Noise", flag: VisualFXSettings.noise)

                Slider(
                    value: Binding(
                        get: { settingsManager.current.visualFX.intensity },
                        set: { value in
                            settingsManager.update { $0.visualFX.intensity = value }
                        }
                    ),
                    in: 0...1
                ) {
                    Text("Intensity")
                }
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

