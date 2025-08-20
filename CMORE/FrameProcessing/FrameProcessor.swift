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
class FrameProcessor {
    
    // MARK: - Private Properties
    private let faceDetector = FaceDetector()
    
    // MARK: - Public Methods
    func processFrame(_ ciImage: CIImage) {
        // No need for extra queue - already on background thread
        let preparedImage = prepareFrame(ciImage)
        faceDetector.detectFaces(in: preparedImage)
    }
    
    // MARK: - Private Methods
    private func prepareFrame(_ ciImage: CIImage) -> CIImage {
        // Add any frame preparation here if needed
        return ciImage
    }
}