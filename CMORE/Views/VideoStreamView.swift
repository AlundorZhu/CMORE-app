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
    
    /// Tell swiftUI to refresh whenever this changes
    @ObservedObject var viewModel: VideoStreamViewModel
    
    var body: some View {
        // HStack arranges elements horizontally for landscape orientation
        HStack(spacing: 20) {
            // MARK: - Video Display Area
            // ZStack layers elements on top of each other
            ZStack {
                Group {
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
                }.overlay(
                    GeometryReader { geo in
                        if let overlay = viewModel.overlay,
                           let faces = overlay.faces {
                            ForEach(faces.indices, id: \.self) { i in
                                BoundingBoxView(geo: geo, box: faces[i])
                            }
                        }
                    }
                )
                
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
            // Use proper aspect ratio for landscape camera view (1920x1080 = 16:9)
            .aspectRatio(CameraSettings.resolution.width / CameraSettings.resolution.height, contentMode: .fit)
            .cornerRadius(12) // Rounded corners for the camera view
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // MARK: - Control Panel (Right Side)
            // VStack for vertical arrangement of controls in the right panel
            VStack(spacing: 30) {
                Spacer()
                
                // MARK: - Single Recording Button
                // Simple one-button interface for recording
                Button {
                    viewModel.toggleRecording()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                        
                        Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    // Dynamic color: red when recording, green when stopped
                    .background(viewModel.isRecording ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(20)
                }
                
                // MARK: - Recording Status
                // Show recording status message when available
                if let statusMessage = viewModel.recordingStatusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
                
                Spacer()
            }
            .frame(width: 200) // Fixed width for control panel
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
