//
//  FlowMateApp.swift
//  FlowMate
//
//  Created by Adam on 19/11/2025.
//

import SwiftUI

@main
struct FlowMateApp: App {
    @StateObject private var tracker = ActivityTracker()

    init() {
        #if os(macOS)
        AccessibilityPermission.ensure()
        NotificationManager.shared.requestAuthorization()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
        }
    }
}
