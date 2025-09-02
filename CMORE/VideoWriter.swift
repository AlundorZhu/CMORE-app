//
//  VideoWriter.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/20/25.
//

import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import UIKit

// MARK: - Video Writer
/// Custom video writer that can record processed frames with face detection bounding boxes
class VideoWriter {
    
    // MARK: - Properties
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let frameProcessor = FrameProcessor()
    private var isRecording = false
    private var frameCount = 0
    
    
    // MARK: - Public Methods
    
    /// Starts recording to the specified URL
    /// - Parameter outputURL: The URL where the video should be saved
    /// - Returns: True if recording started successfully, false otherwise
    func startRecording(to outputURL: URL) -> Bool {
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        do {
            // Create asset writer
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            
            // Configure video input
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: CameraSettings.videoCodec,
                AVVideoWidthKey: CameraSettings.resolution.width,
                AVVideoHeightKey: CameraSettings.resolution.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: CameraSettings.averageBitRate,
                    AVVideoProfileLevelKey: CameraSettings.profileLevel
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            // Create pixel buffer adaptor
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: CameraSettings.resolution.width,
                kCVPixelBufferHeightKey as String: CameraSettings.resolution.height
            ]
            
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput!,
                sourcePixelBufferAttributes: pixelBufferAttributes
            )
            
            // Add input to asset writer
            if assetWriter!.canAdd(videoInput!) {
                assetWriter!.add(videoInput!)
            } else {
                print("Cannot add video input to asset writer")
                return false
            }
            
            // Start writing
            guard assetWriter!.startWriting() else {
                print("Failed to start writing: \(assetWriter?.error?.localizedDescription ?? "Unknown error")")
                return false
            }
            
            assetWriter!.startSession(atSourceTime: .zero)
            isRecording = true
            frameCount = 0
            
            return true
            
        } catch {
            print("Error setting up video writer: \(error)")
            return false
        }
    }
    
    /// Adds a frame to the video
    /// - Parameter frame: The processed frame as a UIImage
    /// - Parameter presentationTime: The presentation time for the frame
    func appendFrame(_ frame: UIImage) {
        guard isRecording,
              let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData,
              let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool,
              let cgImage = frame.cgImage else {
            return
        }

        // Create a pixel buffer from the pool
        guard let pixelBuffer = pixelBufferPool.createPixelBuffer() else {
            print("Failed to create pixel buffer")
            return
        }

        // Convert UIImage to CIImage and render into the pixel buffer
        let ciImage = CIImage(cgImage: cgImage)
        let ciContext = CIContext()
        ciContext.render(ciImage, to: pixelBuffer)

        // Create a presentation time for the frame
        let presentationTime = CMTime(value: CMTimeValue(frameCount), timescale: CameraSettings.frameRate.timescale)

        // Append the pixel buffer to the video
        pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
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

        // Ensure cleanup
        defer {
            assetWriter = nil
            videoInput = nil
            pixelBufferAdaptor = nil
        }
        
        await assetWriter?.finishWriting()
        let success = assetWriter?.status == .completed
        let error = assetWriter?.error

        return (success: success, error: error)
    }
}

// MARK: - CVPixelBufferPool Extension
private extension CVPixelBufferPool {
    func createPixelBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, self, &pixelBuffer)
        
        if status == kCVReturnSuccess {
            return pixelBuffer
        } else {
            print("Failed to create pixel buffer: \(status)")
            return nil
        }
    }
}
