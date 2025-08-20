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
/// This view handles camera recording functionality with a simple one-button interface
struct VideoStreamView: View {
    // @StateObject creates and manages the ViewModel for this view
    // It ensures the ViewModel persists for the lifetime of this view
    @StateObject private var viewModel = VideoStreamViewModel()
    
    var body: some View {
        // VStack arranges elements vertically (top to bottom)
        VStack {
            // MARK: - Video Display Area
            // ZStack layers elements on top of each other
            ZStack {
                // Show the current camera frame if available, otherwise show black background
                if let image = viewModel.image {
                    Image(uiImage: image)
                        .resizable() // Allows the image to be resized
                        .aspectRatio(contentMode: .fit) // Maintains aspect ratio while fitting
                } else {
                    // Placeholder when no camera feed is available
                    Color.black
                        .overlay(
                            Text("Camera will appear here")
                                .foregroundColor(.white)
                                .font(.title2)
                        )
                }
            }
            .frame(height: 400) // Fixed height for the video display area
            
            // MARK: - Single Recording Button
            // Simple one-button interface for recording
            Button {
                viewModel.toggleRecording()
            } label: {
                Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 15)
                    // Dynamic color: red when recording, green when stopped
                    .background(viewModel.isRecording ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(25)
            }
            .padding(.top, 20)
            
            // MARK: - Recording Status
            // Show recording status message when available
            if let statusMessage = viewModel.recordingStatusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 10)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        // Start camera automatically when view appears
        .onAppear {
            viewModel.startCameraAutomatically()
        }
        // Alert modifier shows the save confirmation dialog
        .alert("Save Video?", isPresented: $viewModel.showSaveConfirmation) {
            // Save button - saves the video to Photos library
            Button("Save to Photos") {
                viewModel.saveVideoToPhotos()
            }
            
            // Discard button - deletes the video file
            Button("Discard", role: .destructive) {
                viewModel.discardVideo()
            }
        } message: {
            Text("Would you like to save this recorded video to your Photos library or discard it?")
        }
    }
}

// MARK: - Preview
/// SwiftUI preview for development - allows seeing the UI in Xcode's canvas
#Preview {
    ContentView()
}
