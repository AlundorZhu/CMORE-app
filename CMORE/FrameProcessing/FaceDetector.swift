//
//  FaceDetector.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/20/25.
//

import Foundation
import Vision
import CoreImage

class FaceDetector {
    
    private lazy var faceDetectionRequest: VNDetectFaceRectanglesRequest = {
        let request = VNDetectFaceRectanglesRequest { request, error in
            self.handleDetectionResults(request.results, error: error)
        }
        return request
    }()
    
    func detectFaces(in image: CIImage) {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        
        do {
            try handler.perform([faceDetectionRequest])
        } catch {
            print("Face detection error: \(error)")
        }
    }
    
    private func handleDetectionResults(_ results: [Any]?, error: Error?) {
        guard let faceObservations = results as? [VNFaceObservation] else {
            if let error = error {
                print("Face detection failed: \(error)")
            }
            return
        }
        
        // Process face detection results
        for face in faceObservations {
            print("Found face with confidence: \(face.confidence)")
            print("Bounding box: \(face.boundingBox)")
        }
    }
}