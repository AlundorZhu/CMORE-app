//
//  CmoreUI.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 10/2/25.
//

import SwiftUI
import Vision

struct StreamUI: View {
    
    init(_ viewModel: StreamViewModel) {
        self.viewModel = viewModel
    }
    
    @ObservedObject var viewModel: StreamViewModel
    
    var body: some View {
        ZStack {
            // Handedness indicator at the top
            VStack{
                HandednessIndicator(handedness: viewModel.handedness)
                    .padding(.top, 5)
                Spacer()
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
            
//            if let overlay: FrameResult = viewModel.overlay {
//                VStack{
//                    HStack {
//                        Text("\(overlay.blockTransfered ?? 0)")
//                            .font(.headline)
//                            .foregroundStyle(.white)
//                            .padding(8)
//                            .background(
//                                RoundedRectangle(cornerRadius: 8)
//                                    .fill(.black.opacity(0.5))
//                            )
//                            .padding(.top, 5)
//                            .padding(.leading, 50)
//                        Spacer()
//                    }
//                    Spacer()
//                }
//            }
        }
        .background(Color.clear)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { gesture in
                    
//                    print("I see you draged: \(gesture)")
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
                viewModel.saveSession()
            }
            Button("Discard", role: .destructive) {
                viewModel.discardSession()
            }
        } message: {
            Text("Save this recording to your library?")
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

#Preview("UI"){
    StreamUI(StreamViewModel())
}

