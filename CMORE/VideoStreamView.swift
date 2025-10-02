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
struct VideoStreamView: View {
    // View model driving camera and recording state
    @ObservedObject var viewModel: VideoStreamViewModel

    // The target stream aspect ratio (e.g., 1920x1080 = 16:9)
    private var streamAspect: CGFloat {
        CGFloat(CameraSettings.resolution.width) / CGFloat(CameraSettings.resolution.height)
    }

    var body: some View {
        ZStack {
            // Background to match system camera letterboxing
            Color.gray

            // MARK: - Live Preview (fits into available space; no cropping)
            Group {
                if let session = viewModel.captureSession {
                    // Live camera preview sized by aspect ratio and allowed to take
                    // as much space as possible inside the screen.
                    CameraPreviewView(session: session)
                        .aspectRatio(streamAspect, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Face bounding boxes overlay, sized to the preview area only.
                        // Keep this local GeometryReader so boxes align with the preview's
                        // actual drawing rect. This doesn't control layout; it only reads size.
                        .overlay(
                            GeometryReader { localGeo in
                                if let overlay = viewModel.overlay {
                                    OverlayView(overlay, localGeo)
                                }
                            }
                        )
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
            
            CmoreUI(viewModel)
        }
        .ignoresSafeArea()
        // Save/discard confirmation after recording ends
        .alert("Save Video?", isPresented: $viewModel.showSaveConfirmation) {
            Button("Save to Photos") {
                viewModel.saveVideoToPhotos()
            }
            Button("Discard", role: .destructive) {
                viewModel.discardVideo()
            }
        } message: {
            Text("Would you like to save this recorded video to your Photos library or discard it?")
        }
    }
}

// MARK: - Preview
#Preview {
    VideoStreamView(viewModel: VideoStreamViewModel())
}
