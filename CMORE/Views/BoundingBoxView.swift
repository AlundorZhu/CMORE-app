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
    let box: BoundingBoxProviding

    var body: some View {
        Rectangle()
            .stroke(Color.red, lineWidth: 2)
            .frame(
                width: box.boundingBox.width * geo.size.width,
                height: box.boundingBox.height * geo.size.height
            )
            .position(
                x: (box.boundingBox.origin.x + box.boundingBox.width / 2) * geo.size.width,
                y: (1 - (box.boundingBox.origin.y + box.boundingBox.height / 2)) * geo.size.height
            )
    }
}
