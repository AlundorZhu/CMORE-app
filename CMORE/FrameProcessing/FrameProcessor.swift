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
/// Currently focuses on face detection but could be extended for other analysis
/// SIMPLIFICATION SUGGESTIONS:
/// 1. This class could be made optional if face detection isn't always needed
/// 2. Could add configuration options for different types of processing
/// 3. The prepareFrame method is currently empty and could be removed
class FrameProcessor {
    
    // MARK: - Private Properties
    
    /// The face detector that analyzes frames for faces
    private let faceDetector = FaceDetector()
    
    // MARK: - Public Methods
    
    /// Processes a single frame from the camera or video
    /// - Parameter ciImage: The frame to process as a Core Image
    /// Note: This method is called on a background thread, so it won't block the UI
    func processFrame(_ ciImage: CIImage) {
        // Prepare the frame (currently just passes through, but could do preprocessing)
        let preparedImage = prepareFrame(ciImage)
        
        // Detect faces in the frame
        faceDetector.detectFaces(in: preparedImage)
    }
    
    // MARK: - Private Methods
    
    /// Prepares a frame for processing (placeholder for future enhancements)
    /// - Parameter ciImage: The original frame
    /// - Returns: The prepared frame (currently unchanged)
    /// SIMPLIFICATION SUGGESTION: This method could be removed since it doesn't do anything
    private func prepareFrame(_ ciImage: CIImage) -> CIImage {
        // Add any frame preparation here if needed (e.g., resizing, filtering, etc.)
        return ciImage
    }
}