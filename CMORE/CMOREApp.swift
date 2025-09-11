//
//  CMOREApp.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/19/25.
//

import SwiftUI

// MARK: - Main App Entry Point
// The @main attribute tells Swift this is where the app starts
@main
struct CMOREApp: App {
    
    /// @StateObject make it persist through "the App" here
    @StateObject var realTimeStream = VideoStreamViewModel()
    
    // The body property defines what appears when the app launches
    var body: some Scene {
        // WindowGroup creates the main window for our app
        // ContentView() is the first screen users will see
        WindowGroup {
            VideoStreamView(viewModel: realTimeStream)
        }
    }
}
