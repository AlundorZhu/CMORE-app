//
//  ContentView.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/19/25.
//
import SwiftUI
import AVFoundation

// MARK: - Video Stream Interface
/// A full-screen camera experience similar to the default Camera app.
/// - Shows a 16:9 live preview that expands to the largest size that fits the screen
///   without cropping (letterboxes on the short dimension).
/// - Overlays recording controls and status on top of the preview.
/// - Keeps face bounding boxes aligned with the preview area.
struct CMOREView: View {
    enum Mode {
        case camera
        case video
    }
    
    // View model driving camera and recording state
    @ObservedObject var viewModel: CMOREViewModel
    @State private var mode: Mode? = nil
    
    
    // The target stream aspect ratio (e.g., 1920x1080 = 16:9)
    private var streamAspect: CGFloat {
        CameraSettings.resolution.width / CameraSettings.resolution.height
    }

    var body: some View {
        ZStack {
            // Background to match system camera letterboxing
            Color.gray
            
            if mode == nil {
                VStack(spacing: 20) {
                    Button("Start Camera") {
                        mode = .camera
                        Task {
                            await viewModel.startCamera() }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Button("Process Video") {
                        mode = .video
                        Task {
                            if let url = Bundle.main.url(forResource: "longer_bb_test", withExtension: "mov") {
                                try? await viewModel.processVideo(url: url)
                            }
                        }
                    }
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else if mode == .video {
                if let frame = viewModel.currentFrame {
                    ZStack {
                        Image(uiImage: frame)
                            .resizable()
                            .scaledToFit()
                        GeometryReader { localGeo in
                            if let overlay = viewModel.overlay {
                                OverlayView(overlay, localGeo, viewModel.handedness)
                            }
                        }
                    }
                }
            } else if mode == .camera {
                if let session = viewModel.captureSession {
                    ZStack {
                        CameraPreviewView(session: session)
                        GeometryReader { localGeo in
                            if let overlay = viewModel.overlay {
                                OverlayView(overlay, localGeo, viewModel.handedness)
                            }
                        }
                    }
                    .aspectRatio(streamAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                CmoreUI(viewModel)
            }
            
            // MARK: - Live Preview (fits into available space; no cropping)
            /*Group {
                if let frame = viewModel.currentFrame {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFit()
                } else if let session = viewModel.captureSession {
                    ZStack {
                        CameraPreviewView(session: session)
                        GeometryReader { localGeo in
                            if let overlay = viewModel.overlay {
                                OverlayView(overlay, localGeo, viewModel.handedness)
                            }
                        }
                    }
                    .aspectRatio(streamAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.black
                        .aspectRatio(streamAspect, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(
                            Text("Camera will appear here")
                                .foregroundColor(.white)
                                .font(.title2)
                        )
                }
            }*/

            /*Group {
                if let session = viewModel.captureSession {
                    // Live camera preview with overlay in a ZStack
                    ZStack {
                        CameraPreviewView(session: session)
                        
                        // Face bounding boxes overlay, constrained to the same space as camera preview
                        GeometryReader { localGeo in
                            if let overlay = viewModel.overlay {
                                OverlayView(overlay, localGeo, viewModel.handedness)
                            }
                        }
                    }
                    .aspectRatio(streamAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Placeholder when camera is not available yet, maintaining 16:9 fit.
                    Color.black
                        .aspectRatio(streamAspect, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(
                            Text("Camera will appear here")
                                .foregroundColor(.white)
                                .font(.title2)
                        )
                }
            }
            
            CmoreUI(viewModel)*/
        }
        .ignoresSafeArea()
    }
}

// MARK: - Preview
#Preview {
    CMOREView(viewModel: CMOREViewModel())
}

