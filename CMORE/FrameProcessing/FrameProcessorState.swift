//
//  FrameProcessorState.swift
//  CMORE
//

import Foundation
import Vision
import simd

/// The hand-crossing state machine for block counting.
///
/// State flow:
///   free -> detecting -> crossed -> crossedBack?-> released -> free
enum BlockCountingState: String, Codable {
    case free
    case detecting
    case crossed
    case crossedBack
    case released

    /// Compute the next state given the current hand observations, box geometry,
    /// and recent block detections.
    func transition(by hands: [HumanHandPoseObservation], _ box: BoxDetection, _ blockDetections: [BlockDetection]) -> BlockCountingState {
        guard let hand = hands.first else {
            return self
        }

        let divider = (
            box["Front divider top"],
            box["Front top middle"],
            box["Back divider top"]
        )
        let backHorizon = max(
            box["Back top left"].position.y,
            box["Back top right"].position.y
        )
        let chirality = hand.chirality!
        let tips = hand.fingerTips

        /// Block centers in frame coordinates (lazily computed).
        var blockCenters: [SIMD2<Double>] {
            var result: [SIMD2<Double>] = []
            for detection in blockDetections {
                let roi = detection.ROI
                guard let blocks = detection.objects else { continue }
                for block in blocks {
                    result.append(SIMD2<Double>(
                        x: block.boundingBox.toImageCoordinates(from: roi, imageSize: CameraSettings.resolution).midX,
                        y: block.boundingBox.toImageCoordinates(from: roi, imageSize: CameraSettings.resolution).midY
                    ))
                }
            }
            return result
        }

        switch self {
        case .free:
            if isAbove(of: box["Front divider top"].position.y, tips) &&
                !isCrossed(divider: divider, tips, handedness: chirality) {
                return .detecting
            }

        case .released:
            if !isAbove(of: backHorizon, tips) &&
                !isCrossed(divider: divider, tips, handedness: chirality) {
                return .free
            }

        case .crossedBack:
            if isBlockApart(from: hand, distanceThreshold: FrameProcessingThresholds.releasedDistanceMultiplier * blockLengthInPixels(scale: box.cmPerPixel), blockCenters) {
                return .released
            }
            if !isAbove(of: backHorizon, tips) {
                return .free
            }
            if isCrossed(divider: divider, tips, handedness: chirality) {
                return .crossed
            }

        case .detecting:
            if !isAbove(of: backHorizon, tips) &&
                !isCrossed(divider: divider, tips, handedness: chirality) {
                return .free
            }
            if isCrossed(divider: divider, tips, handedness: chirality) {
                return .crossed
            }

        case .crossed:
            if isBlockApart(from: hand, distanceThreshold: FrameProcessingThresholds.releasedDistanceMultiplier * blockLengthInPixels(scale: box.cmPerPixel), blockCenters) {
                return .released
            }
            if !isCrossed(divider: divider, tips, handedness: chirality) {
                return .crossedBack
            }
        }
        return self
    }
}
