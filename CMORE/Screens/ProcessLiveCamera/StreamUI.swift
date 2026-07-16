//
//  CmoreUI.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 10/2/25.
//

import SwiftUI
import Vision

private enum NamingStage {
    case idle
    case choosing
    case customEntry
}

struct StreamUI: View {
    @Environment(\.dismiss) private var dismiss
    
    init(_ viewModel: StreamViewModel) {
        self.viewModel = viewModel
    }
    
    @ObservedObject var viewModel: StreamViewModel
    @State private var namingStage: NamingStage = .idle
    
    var body: some View {
        ZStack {
            // Handedness indicator at the top
            VStack{
                HandednessIndicator(handedness: viewModel.handedness)
                    .padding(.top, 5)
                Spacer()
            }

            // Recording time remaining (bottom-left while recording)
            if viewModel.isRecording {
                VStack {
                    Spacer()
                    HStack {
                        RecordingTimerView(seconds: viewModel.recordingTimeRemaining)
                            .padding(.leading, 12)
                            .padding(.bottom, 20)
                        Spacer()
                    }
                }
            }

            HStack{
                Spacer()
                MovieCaptureButton(isRecording: $viewModel.isRecording, action: { _ in
                    viewModel.toggleRecording()
                })
                .aspectRatio(1.0, contentMode: .fit)
                .frame(width: 68)
                .padding(.trailing, 5)
            }

            // Countdown overlay
            if let count = viewModel.countdown {
                CountdownOverlayView(count: count)	
            }

            if namingStage == .customEntry {
                FileNamingPopup(
                    onGoBack: {
                        namingStage = .choosing
                    },
                    onSave: { name in
                        namingStage = .idle
                        viewModel.saveSession(nameRequest: name)
                    }
                )
            }
        }
        .background(Color.clear)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { gesture in
                    
                    let horizontalMovement = gesture.translation.width
                    let verticalMovement = gesture.translation.height
                    
                    // Check if it's more horizontal than vertical (true swipe)
                    if abs(horizontalMovement) > abs(verticalMovement) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.toggleHandedness()
                        }
                    }
                }
        )
        .alert("Save session?", isPresented: $viewModel.showSaveConfirmation) {
            Button("Save") {
                namingStage = .idle
                viewModel.saveSession()
            }
            Button("Save As") {
                namingStage = .customEntry
            }
            Button("Discard", role: .destructive) {
                viewModel.discardSession()
            }
        } message: {
            Text("Save this recording to your library?")
        }
        .alert("Camera need to see the box before starting counting blocks.", isPresented: $viewModel.askForBox) {
            Button("Resume") {
                viewModel.askForBox = false
            }
            Button("Exit", role: .close) {
                dismiss()
            }
        }
    }
}

struct MovieCaptureButton: View {
    
    private let action: (Bool) -> Void
    private let lineWidth = CGFloat(4.0)
    
    @Binding private var isRecording: Bool
    
    init(isRecording: Binding<Bool>, action: @escaping (Bool) -> Void) {
        _isRecording = isRecording
        self.action = action
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: lineWidth)
                .foregroundColor(Color.white)
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    action(isRecording)
                }
            } label: {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: geometry.size.width / (isRecording ? 4.0 : 2.0))
                        .inset(by: lineWidth * 1.2)
                        .fill(.red)
                        .scaleEffect(isRecording ? 0.6 : 1.0)
                }
            }
            .buttonStyle(NoFadeButtonStyle())
        }
    }
    
    struct NoFadeButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
        }
    }
}

struct HandednessIndicator: View {
    let handedness: HumanHandPoseObservation.Chirality
    
    var body: some View {
        HStack(spacing: 0) {
            // Left hand indicator
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 16))
                Text("LEFT")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(handedness == .left ? .white : .gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(handedness == .left ? Color.black.opacity(0.8) : Color.clear)
            )
            
            // Right hand indicator
            HStack(spacing: 8) {
                Text("RIGHT")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 16))
                    .scaleEffect(x: -1, y: 1) // Mirror the hand icon for right hand
            }
            .foregroundColor(handedness == .right ? .white : .gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(handedness == .right ? Color.black.opacity(0.8) : Color.clear)
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.3))
                .blur(radius: 1)
        )
    }
}

struct CountdownOverlayView: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 120, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
            .transition(.scale.combined(with: .opacity))
            .id(count)
    }
}

struct RecordingTimerView: View {
    let seconds: Int

    private var formatted: String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text(formatted)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule())
    }
}

struct FileNamingPopup: View {
    let onGoBack: () -> Void
    let onSave: (String) -> Void

    @State private var customName: String = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Enter a custom file name")
                    .font(.headline)

                TextField("File name", text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 4)

                HStack(spacing: 12) {
                    Button("Go Back") {
                        onGoBack()
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20)
            .padding(32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeInOut(duration: 0.2), value: customName.isEmpty)
    }
}

#Preview("UI"){
    StreamUI(StreamViewModel())
}

