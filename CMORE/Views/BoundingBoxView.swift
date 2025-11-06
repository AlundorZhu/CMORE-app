//
//  BoundingBoxView.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 9/30/25.
//

import SwiftUI
import Vision

struct BoundingBoxView: View {
    let geo: GeometryProxy
    let normalizedBox: NormalizedRect
    let roi: NormalizedRect?
    
    init(_ geo: GeometryProxy, _ bbox: BoundingBoxProviding, from roi: NormalizedRect? = nil) {
        self.geo = geo
        self.normalizedBox = bbox.boundingBox
        self.roi = roi
    }

    var body: some View {
        let rect: CGRect = {
            if let roi = roi {
                return normalizedBox.toImageCoordinates(from: roi, imageSize: geo.size, origin: .upperLeft)
            } else {
                return normalizedBox.toImageCoordinates(geo.size, origin: .upperLeft)
            }
        }()
        
        return Rectangle()
            .stroke(Color.red, lineWidth: 2)
            .frame(
                width: rect.width,
                height: rect.height
            )
            .position(
                x: rect.midX,
                y: rect.midY
            )
    }
}

extension NormalizedRect: @retroactive BoundingBoxProviding {
    public var boundingBox: NormalizedRect { self }
}
