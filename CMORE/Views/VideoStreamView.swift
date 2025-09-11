//
//  ContentView.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/19/25.
//
import SwiftUI
import AVFoundation

// MARK: - Video Stream Interface
/// This view handles camera recording functionality with a simple one-button interface
struct VideoStreamView: View {
    // @StateObject creates and manages the ViewModel for this view
    // It ensures the ViewModel persists for the lifetime of this view
    @ObservedObject var viewModel: VideoStreamViewModel
    
    var body: some View {
        // VStack arranges elements vertically (top to bottom)
        VStack {
            // MARK: - Video Display Area
            // ZStack layers elements on top of each other
            ZStack {
                // Show the live camera preview using preview layer
                if let session = viewModel.captureSession {
                    CameraPreviewView(session: session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Placeholder when camera is not available
                    Color.black
                        .overlay(
                            Text("Camera will appear here")
                                .foregroundColor(.white)
                                .font(.title2)
                        )
                }
                
                // Recording overlay when recording is active
                if viewModel.isRecording {
                    VStack {
                        HStack {
                            // Recording indicator (red dot + text)
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)
                                    .scaleEffect(viewModel.isRecording ? 1.0 : 0.8)
                                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: viewModel.isRecording)
                                
                                Text("REC")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(15)
                            
                            Spacer()
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                        
                        Spacer()
                    }
                }
            }
            // .frame(height: 400) // Fixed height for the video display area
            .aspectRatio(CameraSettings.resolution.height / CameraSettings.resolution.width, contentMode: .fit)
            .cornerRadius(12) // Rounded corners for the camera view
            
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
    VideoStreamView(viewModel: VideoStreamViewModel())
}
