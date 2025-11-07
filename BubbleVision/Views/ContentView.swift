//
//  ContentView.swift
//  Bubble Vision
//
//  Main UI: AR passthrough + blow button + status
//

import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = ARCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settingsManager: SettingsManager

    // Load persisted state on launch
    @State private var loadPersisted = true
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            // AR View (full screen)
            ARViewContainer(coordinator: coordinator, loadPersisted: loadPersisted)
                .ignoresSafeArea()
                .onAppear {
                    loadPersisted = false // Only load once
                }

            // UI Overlay
            VStack {
                // Top status bar
                HStack {
                    Text(coordinator.statusMessage)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)

                    Spacer()

                    HStack(spacing: 8) {
                        Text("Bubbles: \(coordinator.bubbleCount)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)

                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .padding()

                Spacer()

                // Bottom controls
                VStack(spacing: 16) {
                    // Trail Mode Indicator
                    if coordinator.isTrailMode {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Trail Mode")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("• \(coordinator.sliceCount) slices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(16)
                    }

                    // Blow Button (Toggle)
                    Button(action: {
                        coordinator.toggleTrailMode()
                    }) {
                        Image(systemName: coordinator.isTrailMode ? "stop.circle.fill" : "wind")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                    }
                    .frame(width: 80, height: 80)
                    .background(
                        Circle()
                            .fill(coordinator.isTrailMode ? Color.red : Color.white.opacity(0.2))
                    )
                    .scaleEffect(coordinator.isTrailMode ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3), value: coordinator.isTrailMode)
                    .disabled(!coordinator.isReady)

                    // Action Buttons
                    HStack(spacing: 12) {
                        // Clear All Button
                        Button(action: {
                            coordinator.clearAllSlices()
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear All")
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.6))
                            .cornerRadius(20)
                        }
                        .disabled(coordinator.sliceCount == 0)

                        // Save Button
                        Button(action: {
                            coordinator.saveState()
                            generateHaptic()
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Save Session")
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                        }
                        .disabled(!coordinator.isReady)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                coordinator.saveState()
                coordinator.pause()
            case .active:
                // Session resumes automatically via ARView
                break
            default:
                break
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(settingsManager)
        }
    }

    private func generateHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

#Preview {
    ContentView()
}
