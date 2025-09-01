//
//  BoxDetector.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 9/1/25.
//
import CoreML
import Vision
import CoreImage
import UIKit

// MARK: - BoxDetector Class

class BoxDetector {
    private let detector = try? KeypointDetector()
    private let context = CIContext()
    
    // MARK: - Detection Method
    
    func detect(on image: CIImage) {
        guard let detector = detector else {
            print("BoxDetector: Model not loaded")
            return
        }
        
        // Preprocess the image
        guard let preprocessedImage = preprocessImage(image) else {
            print("BoxDetector: Image preprocessing failed")
            return
        }
        
        // Do the actual detection
        performDetection(with: preprocessedImage, using: detector)
    }
    
    // MARK: - Private Methods
    
    /// Preprocesses the CIImage to the required format (512x512)
    private func preprocessImage(_ ciImage: CIImage) -> CVPixelBuffer? {
        // Resize to 512x512 while maintaining aspect ratio
        let targetSize = CGSize(width: 512, height: 512)
        let scaleTransform = CGAffineTransform(scaleX: targetSize.width / ciImage.extent.width,
                                              y: targetSize.height / ciImage.extent.height)
        let scaledImage = ciImage.transformed(by: scaleTransform)
        
        // Create pixel buffer attributes
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
        ]
        
        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32ARGB,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            print("BoxDetector: Failed to create pixel buffer")
            return nil
        }
        
        // Render CIImage to pixel buffer
        context.render(scaledImage, to: buffer)
        return buffer
    }
    
    /// Performs the actual keypoint detection
    private func performDetection(with pixelBuffer: CVPixelBuffer, using detector: KeypointDetector) {
        do {
            // Create input for the model
            let input = KeypointDetectorInput(image: pixelBuffer)
            
            // Run prediction
            let output = try detector.prediction(input: input)
            
            // Process the results
            if let keypointData = output.featureValue(for: "var_2340")?.multiArrayValue {
                let keypoints = processKeypointOutput(keypointData)
                
                // Handle the detected keypoints
                handleDetectedKeypoints(keypoints)
            } else {
                print("BoxDetector: Failed to extract keypoint data from model output")
            }
            
        } catch {
            print("BoxDetector: Detection failed with error: \(error)")
        }
    }
    
    /// Processes the raw model output to extract keypoints
    private func processKeypointOutput(_ multiArray: MLMultiArray) -> [[Float]] {
        // Following YOLO pose format:
        // Output shape: (1 × 35 × 5376) -> transpose to (1 × 5376 × 35)
        // Format: [x_center, y_center, width, height, class_conf, kpt1_x, kpt1_y, kpt1_conf, ...]
        
        let numAnchors = 5376
        let numKeypoints = 10
        let objectConfThreshold: Float = 0.25
        
        var allDetections: [BoxDetection] = []
        
        // Process each anchor
        for anchorIdx in 0..<numAnchors {
            var detection = BoxDetection()
            
            // Extract bounding box info (first 5 channels)
            detection.centerX = Float(truncating: multiArray[0 * numAnchors + anchorIdx])
            detection.centerY = Float(truncating: multiArray[1 * numAnchors + anchorIdx])
            detection.width = Float(truncating: multiArray[2 * numAnchors + anchorIdx])
            detection.height = Float(truncating: multiArray[3 * numAnchors + anchorIdx])
            detection.objectConf = Float(truncating: multiArray[4 * numAnchors + anchorIdx])
            
            // Skip low confidence detections
            if detection.objectConf < objectConfThreshold {
                continue
            }
            
            // Extract keypoints (channels 5-34)
            var keypoints: [[Float]] = []
            for kptIdx in 0..<numKeypoints {
                let baseChannelIdx = 5 + kptIdx * 3
                let x = Float(truncating: multiArray[baseChannelIdx * numAnchors + anchorIdx])
                let y = Float(truncating: multiArray[(baseChannelIdx + 1) * numAnchors + anchorIdx])
                let conf = Float(truncating: multiArray[(baseChannelIdx + 2) * numAnchors + anchorIdx])
                keypoints.append([x, y, conf])
            }
            detection.keypoints = keypoints
            allDetections.append(detection)
        }
        
        // Apply Non-Maximum Suppression
        let filteredDetections = applyNMS(detections: allDetections, iouThreshold: 0.5)
        
        // Return keypoints from the best detection
        if let bestDetection = filteredDetections.first {
            return bestDetection.keypoints
        }
        
        print("No box detected!")
        return []
    }
    
    /// Applies Non-Maximum Suppression to filter overlapping detections
    private func applyNMS(detections: [BoxDetection], iouThreshold: Float) -> [BoxDetection] {
        let sortedDetections = detections.sorted { $0.objectConf > $1.objectConf }
        var filtered: [BoxDetection] = []
        
        for detection in sortedDetections {
            var shouldKeep = true
            
            for existingDetection in filtered {
                if calculateIoU(detection1: detection, detection2: existingDetection) > iouThreshold {
                    shouldKeep = false
                    break
                }
            }
            
            if shouldKeep {
                filtered.append(detection)
            }
        }
        
        return filtered
    }
    
    /// Calculates Intersection over Union (IoU) between two detections
    private func calculateIoU(detection1: BoxDetection, detection2: BoxDetection) -> Float {
        // Convert center coordinates to corner coordinates
        let x1_min = detection1.centerX - detection1.width / 2
        let y1_min = detection1.centerY - detection1.height / 2
        let x1_max = detection1.centerX + detection1.width / 2
        let y1_max = detection1.centerY + detection1.height / 2
        
        let x2_min = detection2.centerX - detection2.width / 2
        let y2_min = detection2.centerY - detection2.height / 2
        let x2_max = detection2.centerX + detection2.width / 2
        let y2_max = detection2.centerY + detection2.height / 2
        
        // Calculate intersection
        let intersectionXMin = max(x1_min, x2_min)
        let intersectionYMin = max(y1_min, y2_min)
        let intersectionXMax = min(x1_max, x2_max)
        let intersectionYMax = min(y1_max, y2_max)
        
        let intersectionArea = max(0, intersectionXMax - intersectionXMin) * max(0, intersectionYMax - intersectionYMin)
        
        // Calculate union
        let area1 = detection1.width * detection1.height
        let area2 = detection2.width * detection2.height
        let unionArea = area1 + area2 - intersectionArea
        
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
    
    /// Handles the final detected keypoints
    private func handleDetectedKeypoints(_ keypoints: [[Float]]) {
        // Process the detected keypoints
        print("BoxDetector: Detected \(keypoints.count) keypoints")
        
        for (index, keypoint) in keypoints.enumerated() {
            if keypoint.count >= 3 {
                let x = keypoint[0]
                let y = keypoint[1]
                let confidence = keypoint[2]
                
                // Only process confident keypoints
                if confidence > 0.5 {
                    print("Keypoint \(index): x=\(x), y=\(y), confidence=\(confidence)")
                    
                    // TODO: Add your specific box keypoint processing logic here
                    // For example:
                    // - Update UI with keypoint positions
                    // - Analyze box structure/orientation
                    // - Track box movement
                    // - etc.
                }
            }
        }
    }
}

// MARK: - Supporting Structures

struct BoxDetection {
    var centerX: Float = 0
    var centerY: Float = 0
    var width: Float = 0
    var height: Float = 0
    var objectConf: Float = 0
    var keypoints: [[Float]] = []
}
