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
/// Handles processing of individual video frames from the camera or video files
/// Processes frames for face detection and can return frames with bounding boxes drawn
class FrameProcessor {
    
    enum State {
        case free
        case detecting
    }
    
    // MARK: - Public Properties
    
    public var countingBlocks = false
    
    // MARK: - Private ML Requests
    
    private let facesRequest = DetectFaceRectanglesRequest()
    
    private let handsRequest = DetectHumanHandPoseRequest()
    
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
    }
    
    /// Processes a single frame from the camera or video
    /// - Parameter ciImage: The frame to process as a Core Image
    func processFrame(_ ciImage: CIImage) async -> UIImage?{
        
        if !countingBlocks {
            async let faces = try? facesRequest.perform(on: ciImage)
            async let box = try? boxRequest.perform(on: ciImage)
            
            var boxDetected: BoxDetection? = nil
            
            if let boxRequestResult = await box as? [CoreMLFeatureValueObservation],
                let outputArray = boxRequestResult.first?.featureValue.shapedArrayValue(of: Float.self) {
                    boxDetected = BoxDetector.processKeypointOutput(outputArray)
                    currentBox = boxDetected
                }
        
            
            return visualize(boxes: await faces, keypoints: boxDetected?.keypoints, on: ciImage)
        }
        
        async let hands = try? handsRequest.perform(on: ciImage)
        guard let hands = await hands,
              hands.count > 0 else {
            return nil
        }
        
        guard let currentBox = currentBox else {
            return nil
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
        return nil
    }
    
    func visualize(boxes: [BoundingBoxProviding]?, keypoints: [[Float]]?, on ciImage: CIImage) -> UIImage? {
        let imageSize = ciImage.extent.size
        
        // Create a graphics context to draw on
        UIGraphicsBeginImageContext(imageSize)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            fatalError("Could not get graphics context")
        }
        
        // Convert CIImage to CGImage for drawing
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            fatalError("Could not create CGImage")
        }
        
        // Draw the original image
        context.draw(cgImage, in: CGRect(origin: .zero, size: imageSize))
        
        if let boxes = boxes {
            drawBoxes(context, boxes, imageSize)
        }
        
        if let keypoints = keypoints {
            drawKeypoints(context, keypoints, imageSize)
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
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
    
    private func drawBoxes(_ context: CGContext, _ boxes: [BoundingBoxProviding], _ imageSize: CGSize) {
        // Draw bounding boxes for each detected face
        context.setStrokeColor(UIColor.red.cgColor)
        context.setLineWidth(3.0)
        
        for box in boxes {
            // Convert normalized coordinates to pixel coordinates
            // Vision uses normalized coordinates (0.0 to 1.0)
            let boundingBox = box.boundingBox
            let x = boundingBox.origin.x * imageSize.width
            let y = boundingBox.origin.y * imageSize.height
            let width = boundingBox.width * imageSize.width
            let height = boundingBox.height * imageSize.height
            
            let rect = CGRect(x: x, y: y, width: width, height: height)
            context.stroke(rect)
        }
    }
    
    private func drawKeypoints(_ context: CGContext, _ keypoints: [[Float]], _ imageSize: CGSize) {
        // Set keypoint drawing properties
        context.setFillColor(UIColor.blue.cgColor)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2.0)
        
        let keypointRadius: CGFloat = 4.0
        
        for (idx, keypoint) in keypoints.enumerated() {
            // Each keypoint has format [x, y, confidence]
            let x = CGFloat(keypoint[0])
            let y = CGFloat(keypoint[1])
            
            // Draw keypoint as a filled circle with white border
            let keypointRect = CGRect(
                x: x - keypointRadius,
                y: y - keypointRadius,
                width: keypointRadius * 2,
                height: keypointRadius * 2
            )
            
            context.fillEllipse(in: keypointRect)
            context.strokeEllipse(in: keypointRect)
            
            // Draw the index of the keypoint with better visibility
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16), // Larger, bold font
                .foregroundColor: UIColor.yellow // More visible color
            ]
            
            let indexString = "\(idx)"
            let textSize = indexString.size(withAttributes: attributes)
            
            // Position text slightly above the keypoint for better visibility
            let textPoint = CGPoint(
                x: x - textSize.width / 2,
                y: y - textSize.height - keypointRadius - 2 // Position above the circle
            )
            
            // Draw a small background rectangle for better text visibility
            let backgroundRect = CGRect(
                x: textPoint.x - 2,
                y: textPoint.y - 2,
                width: textSize.width + 4,
                height: textSize.height + 4
            )
            
            context.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)
            context.fill(backgroundRect)
            
            // Draw the text
            indexString.draw(at: textPoint, withAttributes: attributes)
        }
    }
    
}
