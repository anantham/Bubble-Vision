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

    // Load persisted state on launch
    @State private var loadPersisted = true

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

                    Text("Bubbles: \(coordinator.bubbleCount)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                }
                .padding()

                Spacer()

                // Bottom controls
                VStack(spacing: 16) {
                    // Blow Button
                    Button(action: {
                        coordinator.placeBubble()
                        generateHaptic()
                    }) {
                        Image(systemName: "wind")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(
                                Circle()
                                    .fill(coordinator.isReady ?
                                          Color.blue.opacity(0.8) :
                                          Color.gray.opacity(0.4))
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                    }
                    .disabled(!coordinator.isReady)
                    .scaleEffect(coordinator.isReady ? 1.0 : 0.9)
                    .animation(.easeInOut(duration: 0.2), value: coordinator.isReady)

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
    }

    private func generateHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

#Preview {
    ContentView()
}
