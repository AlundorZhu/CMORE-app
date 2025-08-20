//
//  FaceDetector.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/20/25.
//

import Foundation
import Vision
import CoreImage

// MARK: - Face Detector
/// Uses Apple's Vision framework to detect faces in images/video frames
/// SIMPLIFICATION SUGGESTIONS:
/// 1. Could add delegate pattern to communicate results back to UI
/// 2. Could add configuration options for detection accuracy vs. performance
/// 3. Results are currently only printed - could be used to draw overlays on video
class FaceDetector {
    
    // MARK: - Private Properties
    
    /// The Vision request for face detection
    /// Created lazily (only when first needed) for better performance
    private lazy var faceDetectionRequest: VNDetectFaceRectanglesRequest = {
        // Create the request with a completion handler
        let request = VNDetectFaceRectanglesRequest { request, error in
            // Process the detection results when they're available
            self.handleDetectionResults(request.results, error: error)
        }
        return request
    }()
    
    // MARK: - Public Methods
    
    /// Detects faces in the provided image
    /// - Parameter image: The image to analyze for faces
    func detectFaces(in image: CIImage) {
        // Create a Vision request handler with the image
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        
        do {
            // Perform the face detection request
            try handler.perform([faceDetectionRequest])
        } catch {
            print("Face detection error: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    /// Handles the results from face detection
    /// - Parameters:
    ///   - results: Array of detection results (could be faces or nil)
    ///   - error: Any error that occurred during detection
    private func handleDetectionResults(_ results: [Any]?, error: Error?) {
        // Make sure we have valid face detection results
        guard let faceObservations = results as? [VNFaceObservation] else {
            if let error = error {
                print("Face detection failed: \(error)")
            }
            return
        }
        
        // Process each detected face
        // SIMPLIFICATION SUGGESTION: This could be made more useful by:
        // 1. Drawing bounding boxes on the video
        // 2. Counting faces and showing in UI
        // 3. Triggering actions when faces are detected
        for face in faceObservations {
            print("Found face with confidence: \(face.confidence)")
            print("Bounding box: \(face.boundingBox)")
            // Note: Bounding box coordinates are normalized (0.0 to 1.0)
            // You'd need to convert these to actual pixel coordinates for drawing
        }
    }
}