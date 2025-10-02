//
//  CameraPreviewView.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/20/25.
//

import SwiftUI
import AVFoundation

/// A SwiftUI view that displays a live camera preview using AVCaptureVideoPreviewLayer.
/// The app is locked to landscapeRight, and orientation is configured at the session level.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        view.applyLandscapeRightOrientation()
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Do nothing
    }
}

/// UIView whose backing layer is an AVCaptureVideoPreviewLayer.
/// Using the layer directly avoids sublayer management and explicit layout.
final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    /// Applies a fixed landscapeRight orientation to the preview layer's connection.
    func applyLandscapeRightOrientation() {
        guard let connection = previewLayer.connection else { return }
        if connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
    }
}
