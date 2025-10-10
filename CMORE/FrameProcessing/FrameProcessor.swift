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
    
    enum State {
        case free
        case detecting
    }
    
    // MARK: - Public Properties
    
    public private(set) var countingBlocks = false
    
    // MARK: - Private ML Requests
    
    private let facesRequest = DetectFaceRectanglesRequest()
    
    private let handsRequest = DetectHumanHandPoseRequest()
    
    private let blocksRequest: CoreMLRequest
    
    private let boxRequest: CoreMLRequest
    
    // MARK: - Private Properties
    private var currentBox: BoxDetection?
    
    private var currentState:State = .free
    
    // MARK: - Public Methods
    
    init() {
        
        /// Craft the boxDetection request
        let keypointModelContainer = BoxDetector.createBoxDetector()
        var request = CoreMLRequest(model: keypointModelContainer)
        request.cropAndScaleAction = .scaleToFit
        self.boxRequest = request
        
        /// Craft the blockDetection request
        let blockModelContainer = BlockDetector.createBlockDetector()
        /// Default resize action is scaleToFill
        self.blocksRequest = CoreMLRequest(model: blockModelContainer)
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
        
        /// Before the algorithm starts, locate the box
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
        
        /// The block counting algorithm
        result.boxDetection = currentBox // for overlay
        
        async let hands = try? handsRequest.perform(on: ciImage)
        guard let hands = await hands,
              hands.count > 0 else {
            return result
        }
        result.hands = hands
        
        /// simulate the load by running the block detector after hand is avaliable
//        let blocks = try? await blocksRequest.perform(on: ciImage)
//        if let blocks = blocks {
//            print(blocks)
//        }
        
        guard let currentBox = currentBox else {
            fatalError("Bad Box!")
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
        
        // TODO remove it
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
}

