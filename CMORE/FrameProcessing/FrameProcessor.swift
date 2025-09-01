//
//  FrameProcessor.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/20/25.
//

import Foundation
import CoreImage
import AVFoundation

// MARK: - Frame Processor
/// Handles processing of individual video frames from the camera or video files
/// Processes frames for face detection and can return frames with bounding boxes drawn
class FrameProcessor {
    
    // MARK: - Private Properties
    
    /// The face detector that analyzes frames for faces
    private let faceDetector = FaceDetector()
    
    /// The keypoint detector for box
    private let boxDetector = BoxDetector()
    
    // MARK: - Public Methods
    
    /// Processes a single frame from the camera or video
    /// - Parameter ciImage: The frame to process as a Core Image
    /// Note: This method is called on a background thread, so it won't block the UI
    func processFrame(_ ciImage: CIImage) {
        
        // Detect faces in the frame
        faceDetector.detectFaces(in: ciImage)
        
        // Detect box keypoints in the frame
        boxDetector.detect(on: ciImage)
    }
    
    /// Processes a frame and returns it with face detection bounding boxes drawn
    /// - Parameters:
    ///   - ciImage: The frame to process
    ///   - imageSize: The size of the image in pixels
    /// - Returns: The frame with bounding boxes drawn on detected faces
    func processFrameWithBoundingBoxes(_ ciImage: CIImage, imageSize: CGSize) -> CIImage {
        // First detect faces
        faceDetector.detectFaces(in: ciImage)
        
        // Detect box keypoints in the frame
        boxDetector.detect(on: ciImage)
        
        // Then draw bounding boxes on the frame
        return faceDetector.drawFaceBoundingBoxes(on: ciImage, imageSize: imageSize)
    }
    
    // MARK: - Private Methods
    

}
