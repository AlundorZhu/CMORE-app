//
//  FrameProcessor.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/20/25.
//

import Foundation
import CoreImage
import Vision
import AVFoundation
import UIKit

// MARK: - Frame Processor
/// Making it an actor so only one frame get processed at a time
/// Handles processing of individual video frames from the camera or video files
/// Processes frames for face detection and can return frames with bounding boxes drawn
actor FrameProcessor {
    
    nonisolated let onCrossed: (() -> Void)
    
    enum State {
        case free
        case detecting
        case crossed
    }
    
    // MARK: - Public Properties
    
    public private(set) var countingBlocks = false
    
    // MARK: - Private ML Requests
    
    private let facesRequest = DetectFaceRectanglesRequest()
    
    private let handsRequest = DetectHumanHandPoseRequest()
    
    private var blocksRequest: CoreMLRequest /// var because the region of interest changes
    
    private let boxRequest: CoreMLRequest
    
    // MARK: - Private Properties
    private var currentBox: BoxDetection?
    
    private var currentState: State = .free
    
    private var normalizedScalePerCM: Float?
    
    // MARK: - Public Methods
    
    init(onCross: @escaping () -> Void) {
        
        /// Craft the boxDetection request
        let keypointModelContainer = BoxDetector.createBoxDetector()
        var request = CoreMLRequest(model: keypointModelContainer)
        request.cropAndScaleAction = .scaleToFit
        self.boxRequest = request
        
        /// Craft the blockDetection request
        let blockModelContainer = BlockDetector.createBlockDetector()
        /// Default resize action is scaleToFill
        self.blocksRequest = CoreMLRequest(model: blockModelContainer)
        
        /// When crossing the bivider
        self.onCrossed = onCross
    }
    
    func startCountingBlocks() {
        self.countingBlocks = true
    }
    
    func stopCountingBlocks() {
        self.countingBlocks = false
    }
    
    /// Processes a single frame from the camera or video
    /// - Parameter ciImage: The frame to process as a Core Image
    func processFrame(_ ciImage: CIImage) async -> FrameResult {
        
        var result = FrameResult(processingState: currentState)
        async let faces = try? facesRequest.perform(on: ciImage)
        
        // MARK: - Before the algorithm starts, locate the box
        if !countingBlocks {
            async let box = try? boxRequest.perform(on: ciImage)
            
            var boxDetected: BoxDetection? = nil
            
            if let boxRequestResult = await box as? [CoreMLFeatureValueObservation],
                let outputArray = boxRequestResult.first?.featureValue.shapedArrayValue(of: Float.self) {
                    boxDetected = BoxDetector.processKeypointOutput(outputArray)
                    /// Assume the box doesn't move for the rest of the time
                    currentBox = boxDetected
                    result.boxDetection = boxDetected
                }
        
            result.faces = await faces
            return result
        }
        
        // MARK: - The block counting algorithm
        guard let currentBox = currentBox else {
            fatalError("Bad Box!")
        }
        result.boxDetection = currentBox
        
        async let hands = try? handsRequest.perform(on: ciImage)
        guard let hands = await hands,
              hands.count > 0 else {
            
            result.faces = await faces
            return result
        }
        result.hands = hands
        
        
        if normalizedScalePerCM == nil {
            normalizedScalePerCM = calculateScaleToCM(currentBox)
        }
        
        let blockROI = defineBlockROI(hand: hands.first!, cmPerScale: normalizedScalePerCM!)
        result.blockROI = blockROI
        
        blocksRequest.regionOfInterest = blockROI
        
        let blocks = try? await blocksRequest.perform(on: ciImage)
        if let blocks = blocks as? [RecognizedObjectObservation], !blocks.isEmpty {
            result.blocks = blocks
        }
        
        currentState = transition(from: currentState, hand: hands.first!, box: currentBox)
        
//        print("\(currentState)")
        
//        switch currentState {
//        case .free:
//            guard let hands = await hands,
//                  hands.count > 0 else {
//                return nil
//            }
//            
//            guard let currentBox = currentBox else {
//                return nil
//            }
//            
//            currentState = transition(from: currentState, hand: hands.first!, box: currentBox)
//            
//            print("\(currentState)")
//            
//        case .detecting:
//            guard let hands = await hands,
//                  hands.count > 0 else {
//                return nil
//            }
//            
//            guard let currentBox = currentBox else {
//                return nil
//            }
//            
//            currentState = transition(from: currentState, hand: hands.first!, box: currentBox)
//            
//            print("\(currentState)")
//        }
        
        result.faces = await faces
        return result
    }
    
    
    // MARK: - Private Methods
    
    private func transition(from oldState: State, hand: HumanHandPoseObservation, box: BoxDetection) -> State {
        let allJoints = hand.allJoints()
        let jointNames: [HumanHandPoseObservation.JointName] = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
        var fingerTips: [Joint] = []
        
        for jointName in jointNames {
            
            /// was going to just use the fingerTips if the joint(for:) func isn't broken
            if let joint = allJoints[jointName] {
                fingerTips.append(joint)
            }
        }
        
        if oldState == .free && isAbove(of: box["Front divider top"][1], fingerTips) {
            return .detecting
        } else if oldState == .detecting && !isAbove(of: max(box["Back top left"][1], box["Back top right"][1]), fingerTips) {
            return .free
        } else if oldState == .detecting && crossed(divider:(box["Front divider top"], box["Front top middle"], box["Back divider top"]), fingerTips, handedness: hand.chirality!) {
            // play a sound
            Task { @MainActor in
                self.onCrossed()
            }
            return .crossed
        } else if oldState == .crossed && !crossed(divider:(box["Front divider top"], box["Front top middle"], box["Back divider top"]), fingerTips, handedness: hand.chirality!) && !isAbove(of: max(box["Back top left"][1], box["Back top right"][1]), fingerTips) {
            return .free
        } else {
            return oldState
        }
    }
    
    private func isAbove(of horizon: Float, _ keypoints: [Joint]) -> Bool {
        for joint in keypoints {
            if Float(joint.location.y * CameraSettings.resolution.height) > horizon {
                return true
            }
        }
        return false
    }
    
    /// Returns true if any fingertip crosses the divider polyline.
    /// - Parameters:
    ///   - divider: Tuple of three points (front/top, front/middle, back/top) as [x, y] in image space.
    ///   - keypoints: Hand joints to test.
    private func crossed(divider: ([Float], [Float], [Float]), _ keypoints: [Joint], handedness: HumanHandPoseObservation.Chirality) -> Bool {
        let (frontTop, frontMiddle, backTop) = divider

        // Compute the divider's x-position for a given y by clamping to the end points
        // and linearly interpolating between them.
        func dividerX(at y: Float) -> Float {
            if y <= frontTop[1] { return frontTop[0] }
            if y >= backTop[1] { return backTop[0] }
            let dx = backTop[0] - frontTop[0]
            let dy = backTop[1] - frontTop[1]
            // Avoid division by zero if points are vertically aligned.
            guard dx > .leastNormalMagnitude else { return frontTop[0] }
            let m = dy / dx
            let c = frontTop[1] - m * frontTop[0]
            return (y - c) / m
        }

        return keypoints.contains { joint in
            let x = Float(joint.location.x * CameraSettings.resolution.width)
            let y = Float(joint.location.y * CameraSettings.resolution.height)
            switch handedness {
                case .left:
                    return x < dividerX(at: y)
                case .right:
                    return x > dividerX(at: y)
                @unknown default:
                    fatalError("Unknown handedness")
            }
        }
    }
    
    private func calculateScaleToCM(_ box: BoxDetection) -> Float {
        let dividerHeight: Float = 10.0
        let keypointHeight = Float(box.normalizedKeypoint(for: "Front divider top").y - box.normalizedKeypoint(for: "Front top middle").y)
        
        return dividerHeight / keypointHeight
    }
    
    func defineBlockROI(hand: HumanHandPoseObservation, cmPerScale: Float) -> NormalizedRect {
        let handBox = hand.boundingBox
        let blockSize = CGFloat(2.5 / cmPerScale)
        
        if hand.chirality == .left {
            return NormalizedRect(
                x: handBox.origin.x - 2 * blockSize,
                y: handBox.origin.y - 2 * blockSize,
                width: handBox.width + blockSize * 2,
                height: handBox.height + blockSize * 2
            )
        } else if hand.chirality == .right {
            return NormalizedRect(
                x: handBox.origin.x,
                y: handBox.origin.y - 2 * blockSize,
                width: handBox.width + blockSize * 2,
                height: handBox.height + blockSize * 2
            )
        } else {
            fatalError("Something went wrong with calculating blockROI")
        }
    }
}


