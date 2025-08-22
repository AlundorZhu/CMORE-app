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
    
    // Video settings
    private let videoSize: CGSize
    private let fps: Int32 = 30
    
    // MARK: - Initialization
    
    init(videoSize: CGSize = CGSize(width: 1280, height: 720)) {
        self.videoSize = videoSize
    }
    
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
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoSize.width,
                AVVideoHeightKey: videoSize.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2000000, // 2 Mbps
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            // Create pixel buffer adaptor
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: videoSize.width,
                kCVPixelBufferHeightKey as String: videoSize.height
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
    
    /// Adds a processed frame with bounding boxes to the video
    /// - Parameter sampleBuffer: The camera frame sample buffer
    func addFrame(from sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData else {
            return
        }
        
        // Get pixel buffer from sample buffer
        guard let inputPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Convert to CIImage for processing
        let ciImage = CIImage(cvPixelBuffer: inputPixelBuffer)
        
        // Process frame with face detection bounding boxes
        let processedImage = frameProcessor.processFrameWithBoundingBoxes(ciImage, imageSize: videoSize)
        
        // Create output pixel buffer
        guard let outputPixelBuffer = pixelBufferAdaptor.pixelBufferPool?.createPixelBuffer() else {
            return
        }
        
        // Render processed image to pixel buffer
        let ciContext = CIContext()
        ciContext.render(processedImage, to: outputPixelBuffer)
        
        // Calculate presentation time
        let presentationTime = CMTime(value: CMTimeValue(frameCount), timescale: fps)
        
        // Add frame to video
        pixelBufferAdaptor.append(outputPixelBuffer, withPresentationTime: presentationTime)
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
