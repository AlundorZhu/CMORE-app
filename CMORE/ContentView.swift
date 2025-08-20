//
//  ContentView.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/19/25.
//
import SwiftUI

// MARK: - Main Content View
/// This is the root view of our app - it simply displays the VideoStreamView
/// SIMPLIFICATION SUGGESTION: This could be removed entirely and VideoStreamView
/// could be used directly in CMOREApp.swift to reduce unnecessary nesting
struct ContentView: View {
    var body: some View {
        VideoStreamView()
    }
}

// MARK: - Video Stream Interface
/// This view handles the main camera/video functionality and user interface
struct VideoStreamView: View {
    // @StateObject creates and manages the ViewModel for this view
    // It ensures the ViewModel persists for the lifetime of this view
    @StateObject private var viewModel = VideoStreamViewModel()
    
    // @State tracks whether the video picker sheet is currently shown
    @State private var isShowingVideoPicker = false
    
    var body: some View {
        // VStack arranges elements vertically (top to bottom)
        VStack {
            // MARK: - Video Display Area
            // ZStack layers elements on top of each other
            ZStack {
                // Show the current frame if available, otherwise show black background
                if let image = viewModel.image {
                    Image(uiImage: image)
                        .resizable() // Allows the image to be resized
                        .aspectRatio(contentMode: .fit) // Maintains aspect ratio while fitting
                } else {
                    // Placeholder when no image is available
                    Color.black
                }
            }
            .frame(height: 400) // Fixed height for the video display area
            
            // MARK: - Control Buttons
            // HStack arranges elements horizontally (left to right)
            HStack {
                // Stream toggle button - starts/stops camera streaming
                Button {
                    viewModel.toggleStreaming()
                } label: {
                    Text(viewModel.isStreaming ? "Stop Streaming" : "Start Streaming")
                        .padding()
                        // Dynamic color: red when streaming, green when stopped
                        .background(viewModel.isStreaming ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                // Video selection button - opens file picker
                Button {
                    isShowingVideoPicker = true
                } label: {
                    Text("Select Video")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        // Sheet modifier shows the video picker as a modal overlay
        .sheet(isPresented: $isShowingVideoPicker) {
            VideoPicker(completion: { url in
                // When user selects a video, load it into the view model
                viewModel.loadVideo(from: url)
            })
        }
    }
}

// MARK: - Preview
/// SwiftUI preview for development - allows seeing the UI in Xcode's canvas
#Preview {
    ContentView()
}
