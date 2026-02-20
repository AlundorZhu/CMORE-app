//
//  VideoProcessingView.swift
//  CMORE
//

import SwiftUI
import Vision

struct VideoProcessingView: View {
    @StateObject private var viewModel = VideoProcessingViewModel()
    @Environment(\.dismiss) private var dismiss

    let videoURL: URL
    let handedness: HumanHandPoseObservation.Chirality

    private var streamAspect: CGFloat {
        CameraSettings.resolution.width / CameraSettings.resolution.height
    }

    var body: some View {
        ZStack {
            Color.black

            // Video frame + overlay
            ZStack {
                if let frame = viewModel.currentFrame {
                    Image(uiImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.black
                }

                GeometryReader { geo in
                    if let overlay = viewModel.overlay {
                        OverlayView(overlay, geo, viewModel.handedness)
                    }
                }
            }
            .aspectRatio(streamAspect, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // UI overlay
            VStack {
                HandednessIndicator(handedness: viewModel.handedness)
                    .padding(.top, 5)
                // Block count
                if let overlay = viewModel.overlay {
                    Text("Blocks: \(overlay.blockDetections.count)")
                        .font(.headline)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.black.opacity(0.6))
                        )
                        .foregroundColor(.white)
                }
                Spacer()

                if viewModel.isProcessing {
                    ProgressView("Processing...")
                        .tint(.white)
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.black.opacity(0.6))
                        )
                        .padding(.bottom, 20)
                }
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .onAppear {
            Task { @MainActor in
                OrientationManager.shared.setOrientation(.landscapeRight)
            }
            viewModel.handedness = handedness
            viewModel.loadVideo(url: videoURL)
        }
        .onDisappear {
            Task { @MainActor in
                OrientationManager.shared.setOrientation(.all)
            }
        }
        .task {
            await viewModel.startProcessing()
        }
        .onChange(of: viewModel.isDone) { _, isDone in
            if isDone {
                dismiss()
            }
        }
    }
}

