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
    // View model driving camera and recording state
    @ObservedObject var viewModel: CMOREViewModel

    // The target stream aspect ratio (e.g., 1920x1080 = 16:9)
    private var streamAspect: CGFloat {
        CameraSettings.resolution.width / CameraSettings.resolution.height
    }

    var body: some View {
        ZStack {
            // Background to match system camera letterboxing
            Color.gray

            // MARK: - Live Preview (fits into available space; no cropping)
            Group {
                if let session = viewModel.captureSession {
                    // Live camera preview with overlay in a ZStack
                    ZStack {
                        CameraPreviewView(session: session)
                        
                        // Face bounding boxes overlay, constrained to the same space as camera preview
                        GeometryReader { localGeo in
                            if let overlay = viewModel.overlay {
                                OverlayView(overlay, localGeo)
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
            
            CmoreUI(viewModel)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Preview
#Preview {
    CMOREView(viewModel: CMOREViewModel())
}
