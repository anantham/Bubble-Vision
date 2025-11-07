//
//  BubbleVisionApp.swift
//  Bubble Vision
//
//  Main app entry point
//

import SwiftUI

@main
struct BubbleVisionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
                .environmentObject(SettingsManager.shared)
        }
    }
}
