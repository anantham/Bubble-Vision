//
//  ARViewContainer.swift
//  Bubble Vision
//
//  UIViewRepresentable wrapper for ARView with coaching overlay
//

import SwiftUI
import ARKit
import RealityKit

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var coordinator: ARCoordinator
    let loadPersisted: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Setup coaching overlay
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false

        arView.addSubview(coachingOverlay)
        NSLayoutConstraint.activate([
            coachingOverlay.topAnchor.constraint(equalTo: arView.topAnchor),
            coachingOverlay.bottomAnchor.constraint(equalTo: arView.bottomAnchor),
            coachingOverlay.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coachingOverlay.trailingAnchor.constraint(equalTo: arView.trailingAnchor)
        ])

        // Start session
        if loadPersisted {
            coordinator.loadStateAndRun(in: arView)
        } else {
            coordinator.run(in: arView)
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // No-op
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        // Placeholder for future interactions
    }
}
