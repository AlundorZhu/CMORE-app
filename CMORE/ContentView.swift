//
//  ContentView.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/19/25.
//
import SwiftUI

struct ContentView: View {
    var body: some View {
        VideoStreamView()
    }
}

#Preview {
    ContentView()
}

struct VideoStreamView: View {
    @StateObject private var viewModel = VideoStreamViewModel()
    @State private var isShowingVideoPicker = false
    
    var body: some View {
        VStack {
            ZStack {
                if let image = viewModel.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.black
                }
            }
            .frame(height: 400)
            
            HStack {
                Button {
                    viewModel.toggleStreaming()
                } label: {
                    Text(viewModel.isStreaming ? "Stop Streaming" : "Start Streaming")
                        .padding()
                        .background(viewModel.isStreaming ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                Button {
                    isShowingVideoPicker = true
                } label: {
                    Text("Select Video")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .sheet(isPresented: $isShowingVideoPicker) {
                    VideoPicker(completion: { url in
                        viewModel.loadVideo(from: url)
                    })
                }
    }
}



#Preview {
    ContentView()
}
