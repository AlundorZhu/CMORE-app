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
    
    // MARK: - Private Properties
    
    private let facesRequest = DetectFaceRectanglesRequest()
    
    private let boxRequest: CoreMLRequest
    
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
        
        async let faces = try? facesRequest.perform(on: ciImage)
        async let box = try? boxRequest.perform(on: ciImage)
        
        var boxDetected: BoxDetection? = nil
        
        if let boxRequestResult = await box as? [CoreMLFeatureValueObservation],
            let outputArray = boxRequestResult.first?.featureValue.shapedArrayValue(of: Float.self) {
                boxDetected = BoxDetector.processKeypointOutput(outputArray)
            }
    
        
        return visualize(boxes: await faces, keypoints: boxDetected?.keypoints, on: ciImage)
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
        
        for keypoint in keypoints {
            // Each keypoint has format [x, y, confidence]
            guard keypoint.count >= 3 else { continue }
            
            let x = CGFloat(keypoint[0])
            let y = CGFloat(keypoint[1])
            let confidence = keypoint[2]
            
            // Only draw confident keypoints
            if confidence > 0.5 {
                // Convert normalized coordinates to pixel coordinates if needed
                // Assuming keypoints are already in pixel coordinates based on the model output
                let pixelX = x
                let pixelY = y
                
                // Draw keypoint as a filled circle with white border
                let keypointRect = CGRect(
                    x: pixelX - keypointRadius,
                    y: pixelY - keypointRadius,
                    width: keypointRadius * 2,
                    height: keypointRadius * 2
                )
                
                context.fillEllipse(in: keypointRect)
                context.strokeEllipse(in: keypointRect)
            }
        }
    }
    
}
