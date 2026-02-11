//
//  FrameResult.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 9/9/25.
//

import Foundation
import Vision

struct FrameResult: Codable, Comparable {
    @SecondsCoded var presentationTime: CMTime
    
    /// The state after the processing
    var state: FrameProcessor.State
    var blockTransfered: Int?
    var faces: [FaceObservation]?
    var boxDetection: BoxDetection?
    var hands: [HumanHandPoseObservation]?
    var blockDetections: [BlockDetection] = []
    
    static func < (lhs: FrameResult, rhs: FrameResult) -> Bool {
        lhs.presentationTime < rhs.presentationTime
    }
    
    static func == (lhs: FrameResult, rhs: FrameResult) -> Bool {
        lhs.presentationTime == rhs.presentationTime
    }
}

extension HumanHandPoseObservation : @retroactive BoundingBoxProviding {
    public var boundingBox: NormalizedRect {
        let Xs = allJoints().values.map({ $0.location.x })
        let Ys = allJoints().values.map({ $0.location.y })
        
        let maxX = Xs.max()!
        let minX = Xs.min()!
        let maxY = Ys.max()!
        let minY = Ys.min()!
        
        return NormalizedRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX),
            height: CGFloat(maxY - minY)
        )
    }
}

struct BlockDetection: Codable {
    let ROI: NormalizedRect
    var objects: [RecognizedObjectObservation]?
}

@propertyWrapper
struct SecondsCoded: Codable {
    var wrappedValue: CMTime

    init(wrappedValue: CMTime) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let seconds = try decoder.singleValueContainer().decode(Double.self)
        // Reconstruct CMTime. You might want to adjust the timescale (600 is common for video)
        self.wrappedValue = CMTime(seconds: seconds, preferredTimescale: 600)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Here we output just the seconds!
        try container.encode(wrappedValue.seconds)
    }
}
