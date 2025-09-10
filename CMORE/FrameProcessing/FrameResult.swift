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
    var handPoses: [HumanHandPoseObservation]?
}
