//
//  KeypointsView.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 10/8/25.
//
import SwiftUI
import Vision

struct KeypointsView: View {
    let geo: GeometryProxy
    let normalizedKeypoints: [NormalizedPoint]
    
    var body: some View {
        ForEach(normalizedKeypoints.indices, id: \.self) { index in
            let pos = normalizedKeypoints[index].toImageCoordinates(geo.size, origin: .upperLeft)
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .position(x: pos.x, y: pos.y)
        }
    }
    
    init(_ geo: GeometryProxy, _ normalizedKeypoints: [NormalizedPoint]) {
        self.geo = geo
        self.normalizedKeypoints = normalizedKeypoints
    }
}

