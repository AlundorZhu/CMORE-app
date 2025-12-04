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
    
    nonisolated let onCrossed: (() -> Void) // For sound playing
    
    enum State {
        case free
        case detecting
        case crossed
    }
    
    public private(set) var countingBlocks = false
    
    private lazy var handedness: HumanHandPoseObservation.Chirality = .right
    
    private let facesRequest = DetectFaceRectanglesRequest()
    
    private let handsRequest = DetectHumanHandPoseRequest()
    
    private var blocksRequest: CoreMLRequest /// var because the region of interest changes
    
    private lazy var blocksRequestDuplicate: CoreMLRequest = self.blocksRequest /// one ROI follows the hand, another follows the block projectory
    
    private let boxRequest: CoreMLRequest
    
    private var currentBox: BoxDetection?
    
    private var currentState: State = .free
    
    private var cmPerPixel: Float?
    
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
    
    func startCountingBlocks(for handedness: HumanHandPoseObservation.Chirality, box: BoxDetection) {
        self.handedness = handedness
        self.countingBlocks = true
        self.currentBox = box
    }
    
    func stopCountingBlocks() {
        self.countingBlocks = false
    }
    
    /// Processes a single frame from the camera or video
    /// - Parameter ciImage: The frame to process as a Core Image
    func processFrame(_ pixelBuffer: CVImageBuffer) async -> FrameResult {
        
        var result = FrameResult(processingState: currentState)
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        async let faces = try? facesRequest.perform(on: ciImage)
        
        // MARK: - Before the algorithm starts, locate the box
        if !countingBlocks {
            async let box = try? boxRequest.perform(on: ciImage)
            
            var boxDetected: BoxDetection? = nil
            
            if let boxRequestResult = await box as? [CoreMLFeatureValueObservation],
                let outputArray = boxRequestResult.first?.featureValue.shapedArrayValue(of: Float.self) {
                    boxDetected = BoxDetector.processKeypointOutput(outputArray)
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
        guard var hands = await hands,
              hands.count > 0 else {
            
            result.faces = await faces
            return result
        }
        result.hands = hands
        
        // MARK: - Filter out the wrong hand
        hands.removeAll { hand in
            return hand.chirality != nil && hand.chirality != handedness
        }
        
        guard !hands.isEmpty else {
            result.faces = await faces
            return result
        }
        
        // MARK: - detect the block
        if cmPerPixel == nil {
            cmPerPixel = calculateScaleToCM(currentBox)
        }
        
        let blockROI = defineBlockROI(hand: hands.first!, cmPerPixel: cmPerPixel!)
        result.blockROI = blockROI
        
        blocksRequest.regionOfInterest = blockROI
        
        let blocks = try? await blocksRequest.perform(on: ciImage)
        if let blocks = blocks as? [RecognizedObjectObservation], !blocks.isEmpty {
            result.blocks = blocks
        }
        
        currentState = transition(from: currentState, hand: hands.first!, box: currentBox)
        
        print("\(currentState)")
        
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
    
    /// Calculate the cm/px ratio
    private func calculateScaleToCM(_ box: BoxDetection) -> Float {
        let dividerHeight: Float = 10.0 // cm
        let keypointHeight = Float(box["Front divider top"][1] - box["Front top middle"][1]) // px
        
        return dividerHeight / keypointHeight
    }
    
    func defineBlockROI(hand: HumanHandPoseObservation, cmPerPixel: Float) -> NormalizedRect {
        let handBox = hand.boundingBox // normalized rect
        let blockSize = CGFloat(2.5 / cmPerPixel)
        
        var roi = CGRect()
        
        roi.origin.y = handBox.origin.y * CameraSettings.resolution.height - 2 * blockSize
        roi.size.width = handBox.width * CameraSettings.resolution.width + blockSize * 2
        roi.size.height = handBox.height * CameraSettings.resolution.height + blockSize * 2
        
        if hand.chirality == .left {
            roi.origin.x = handBox.origin.x * CameraSettings.resolution.width - 2 * blockSize
        }
        
        // right hand don't move the origin.x but extend the width
        
        return NormalizedRect(imageRect: roi, in: CameraSettings.resolution)
    }
}


