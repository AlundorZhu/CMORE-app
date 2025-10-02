//
//  CmoreUI.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 10/2/25.
//

import SwiftUI

struct CmoreUI: View {
    
    init(_ viewModel: VideoStreamViewModel) {
        self.viewModel = viewModel
    }
    
    @ObservedObject var viewModel: VideoStreamViewModel
    
    var body: some View {
        HStack{
            Spacer()
            MovieCaptureButton(isRecording: $viewModel.isRecording, action: { _ in
                viewModel.toggleRecording()
            })
            .aspectRatio(1.0, contentMode: .fit)
            .frame(width: 68)
            .padding(.trailing, 5)
            
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
                    isRecording.toggle()
                }
                action(isRecording)
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

#Preview("UI"){
    CmoreUI(VideoStreamViewModel())
}

