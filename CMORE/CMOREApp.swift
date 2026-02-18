//
//  CMOREApp.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/19/25.
//

import SwiftUI
import UIKit

// MARK: - Orientation Control

/// Controls which orientations are allowed at any given time.
/// Set to landscape-only when entering the camera view, reset when leaving.
class OrientationManager {
    static let shared = OrientationManager()
    var lockToLandscape = false
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if OrientationManager.shared.lockToLandscape {
            return .landscapeRight
        }
        return .all
    }
}

// MARK: - Main App Entry Point
@main
struct CMOREApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
    }
}
