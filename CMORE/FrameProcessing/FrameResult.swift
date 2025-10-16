//
//  FrameResult.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 9/9/25.
//

import Foundation
import Vision
import CoreImage

struct FrameResult {
    /// The state at which processing the this frame
    let processingState: FrameProcessor.State
    var faces: [BoundingBoxProviding]?
    var boxDetection: BoxDetection?
    var hands: [HumanHandPoseObservation]?
}

extension HumanHandPoseObservation : @retroactive BoundingBoxProviding {
    public var boundingBox: NormalizedRect {
        let Xs = allJoints().values.map({ $0.location.x })
        let Ys = allJoints().values.map({ $0.location.y })
        
        let maxX = Xs.max()!
        let minX = Xs.min()!
        
        return NormalizedRect(
            x: CGFloat(minX),
            y: CGFloat(minX),
            width: CGFloat(maxX - minX),
            height: CGFloat(maxX - minX)
        )
    }
}
