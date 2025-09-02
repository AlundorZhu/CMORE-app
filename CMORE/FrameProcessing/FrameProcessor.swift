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
    
    
    // MARK: - Public Methods
    
    /// Processes a single frame from the camera or video
    /// - Parameter ciImage: The frame to process as a Core Image
    /// Note: This method is called on a background thread, so it won't block the UI
    func processFrame(_ ciImage: CIImage) async -> UIImage?{
        
        async let faces = try? facesRequest.perform(on: ciImage)
        
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
        
        // Draw bounding boxes for each detected face
        context.setStrokeColor(UIColor.red.cgColor)
        context.setLineWidth(3.0)
        
        if let detectedFaces = await faces {
            for face in detectedFaces {
                // Convert normalized coordinates to pixel coordinates
                // Vision uses normalized coordinates (0.0 to 1.0)
                let boundingBox = face.boundingBox
                let x = boundingBox.origin.x * imageSize.width
                let y = boundingBox.origin.y * imageSize.height
                let width = boundingBox.width * imageSize.width
                let height = boundingBox.height * imageSize.height
                
                let rect = CGRect(x: x, y: y, width: width, height: height)
                context.stroke(rect)
            }
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
        
    }
    
    // MARK: - Private Methods
    

}
