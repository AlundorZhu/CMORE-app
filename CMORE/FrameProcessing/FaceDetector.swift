//
//  FaceDetector.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/20/25.
//

import Foundation
import Vision
import CoreImage
import CoreGraphics
import UIKit

// MARK: - Face Detector
/// Uses Apple's Vision framework to detect faces in images/video frames
/// Now provides detection results for drawing bounding boxes on recorded videos
class FaceDetector {
    
    // MARK: - Private Properties
    
    /// Current face detection results
    private var currentFaceObservations: [VNFaceObservation] = []
    
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
    
    /// Gets the current face detection results
    /// - Returns: Array of face observations from the most recent detection
    func getCurrentFaceObservations() -> [VNFaceObservation] {
        return currentFaceObservations
    }
    
    /// Draws face detection bounding boxes on an image
    /// - Parameters:
    ///   - image: The image to draw on
    ///   - imageSize: The size of the image in pixels
    /// - Returns: The image with bounding boxes drawn
    func drawFaceBoundingBoxes(on image: CIImage, imageSize: CGSize) -> CIImage {
        // Create a graphics context to draw on
        UIGraphicsBeginImageContext(imageSize)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        
        // Convert CIImage to CGImage for drawing
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return image }
        
        // Draw the original image
        context.draw(cgImage, in: CGRect(origin: .zero, size: imageSize))
        
        // Draw bounding boxes for each detected face
        context.setStrokeColor(UIColor.red.cgColor)
        context.setLineWidth(3.0)
        
        for face in currentFaceObservations {
            // Convert normalized coordinates to pixel coordinates
            // Vision uses normalized coordinates (0.0 to 1.0) with origin at bottom-left
            let boundingBox = face.boundingBox
            let x = boundingBox.origin.x * imageSize.width
            let y = boundingBox.origin.y * imageSize.height
            let width = boundingBox.width * imageSize.width
            let height = boundingBox.height * imageSize.height
            
            let rect = CGRect(x: x, y: y, width: width, height: height)
            context.stroke(rect)
        }
        
        // Get the final image with bounding boxes
        guard let finalImage = UIGraphicsGetImageFromCurrentImageContext(),
              let finalCGImage = finalImage.cgImage else { return image }
        
        return CIImage(cgImage: finalCGImage)
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
            currentFaceObservations = []
            return
        }
        
        // Store the current face observations
        currentFaceObservations = faceObservations
        
        // Optional: Print detection info for debugging
        if !faceObservations.isEmpty {
            print("Found \(faceObservations.count) face(s)")
            for face in faceObservations {
                print("Face confidence: \(face.confidence), Bounding box: \(face.boundingBox)")
            }
        }
    }
}