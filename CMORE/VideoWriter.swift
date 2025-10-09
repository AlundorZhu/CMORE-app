//
//  VideoWriter.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/20/25.
//

import Foundation
import AVFoundation
import Vision
import UIKit

// MARK: - Simple Video Writer
/// Dead simple video writer - just feed it UIImages
actor VideoWriter {
    
    // MARK: - Properties
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var isRecording = false
    private var frameCount: Int64 = 0
    
    // MARK: - Public Methods
    
    /// Start recording - simple setup
    func startRecording(to outputURL: URL) -> Bool {
        // Clean slate
        try? FileManager.default.removeItem(at: outputURL)
        
        do {
            // Create writer
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            
            // Use high-level preset for video settings
            let videoSettings = AVOutputSettingsAssistant(preset: .preset1920x1080)?
                .videoSettings ?? [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: CameraSettings.resolution.width,
                    AVVideoHeightKey: CameraSettings.resolution.height
                ]
            
            // Create video input
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = false
            
            // Simple pixel buffer adaptor - let system handle optimization
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput!,
                sourcePixelBufferAttributes: nil
            )
            
            // Add to writer
            assetWriter!.add(videoInput!)
            
            // Start
            assetWriter!.startWriting()
            assetWriter!.startSession(atSourceTime: .zero)
            
            isRecording = true
            frameCount = 0
            
            return true
            
        } catch {
            print("Failed to start recording: \(error)")
            return false
        }
    }
    
    /// Add a frame - as simple as it gets
    func appendFrame(_ image: UIImage) {
        guard isRecording,
              let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData else {
            return
        }
        
        // Convert UIImage to pixel buffer (the only complex part we can't avoid)
        guard let pixelBuffer = image.toPixelBuffer() else {
            print("Failed to convert image to pixel buffer")
            return
        }
        
        // Calculate time for this frame
        let frameTime = CMTime(value: frameCount, timescale: CameraSettings.minFrameDuration.timescale)
        
        // Append it
        pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: frameTime)
        frameCount += 1
    }
    
    /// Stops recording and finalizes the video file
    /// - Returns: A tuple containing success status and any error that occurred
    func stopRecording() async -> (success: Bool, error: Error?) {
        guard isRecording else {
            return (false, nil)
        }
        
        isRecording = false
        videoInput?.markAsFinished()
        
        await assetWriter?.finishWriting()
        
        let success = assetWriter?.status == .completed
        let error = assetWriter?.error

        return (success: success, error: error)
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
    
    // MARK: - Public Methods
    
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
        }
    }
}

// MARK: - UIImage Extension
extension UIImage {
    /// Convert UIImage to CVPixelBuffer - simplified version
    func toPixelBuffer() -> CVPixelBuffer? {
        guard let cgImage = self.cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Create pixel buffer with minimal configuration
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        // Draw image into pixel buffer
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }
        
        // Flip coordinate system for video
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
}
