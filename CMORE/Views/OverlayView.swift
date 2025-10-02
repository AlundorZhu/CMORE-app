//
//  OverlayView.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 10/2/25.
//
import SwiftUI
import Vision

struct OverlayView: View {
    
    let geometry: GeometryProxy
    let overlay: FrameResult
    
    init(_ overlay: FrameResult, _ geometry: GeometryProxy){
        self.geometry = geometry
        self.overlay = overlay
    }
    
    var body: some View {
        if let faces = overlay.faces {
            ForEach(faces.indices, id: \.self) { i in
                BoundingBoxView(geometry, faces[i])
            }
        }
        
        if let boxDetection = overlay.boxDetection {
            BoxView(geometry, boxDetection)
        }
    }
}

struct BoxView: View {
    let geo: GeometryProxy
    let box: BoxDetection
    
    let normalizedKeypoints: [NormalizedPoint]
    
    init(_ geo: GeometryProxy, _ box: BoxDetection) {
        self.geo = geo
        self.box = box
        
        var normalizedPoints = [NormalizedPoint]()
        for keypoint in box.keypoints {
            let normalizedPoint = NormalizedPoint(
                imagePoint: CGPoint(x: CGFloat(keypoint[0]), y: CGFloat(keypoint[1])),
                in: CameraSettings.resolution
            )
            normalizedPoints.append(normalizedPoint)
        }
        self.normalizedKeypoints = normalizedPoints
    }
    
    var body: some View {
        ForEach(normalizedKeypoints.indices, id: \.self) { index in
            let pos = normalizedKeypoints[index].toImageCoordinates(geo.size, origin: .upperLeft)
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .position(x: pos.x, y: pos.y)
        }
    }
}
