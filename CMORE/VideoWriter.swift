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
actor VideoWriter {
    
    // MARK: - Properties
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var isRecording = false
    private var frameCount: Int64 = 0
    private var startTime: CMTime?
    private var ciContext: CIContext?
    
    // MARK: - Public Methods
    func startRecording(to outputURL: URL) -> Bool {
        try? FileManager.default.removeItem(at: outputURL)
        
        do {
            // Create writer
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            
            // Use high-level preset for video settings
            let videoSettings = AVOutputSettingsAssistant(preset: .preset1920x1080)?
                .videoSettings ?? [
                    AVVideoCodecKey: CameraSettings.videoCodec,
                    AVVideoWidthKey: CameraSettings.resolution.width,
                    AVVideoHeightKey: CameraSettings.resolution.height
                ]
            
            // Create video input
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            // Configure pixel buffer attributes for better compatibility
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(CameraSettings.resolution.width),
                kCVPixelBufferHeightKey as String: Int(CameraSettings.resolution.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            
            // Simple pixel buffer adaptor with explicit attributes
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput!,
                sourcePixelBufferAttributes: pixelBufferAttributes
            )
            
            // Create reusable CIContext for better performance
            ciContext = CIContext(options: [.useSoftwareRenderer: false])
            
            // Add to writer
            assetWriter!.add(videoInput!)
            
            // Start
            assetWriter!.startWriting()
            
            isRecording = true
            
            return true
            
        } catch {
            print("Failed to start recording: \(error)")
            return false
        }
    }
    
    func append(_ pixelBuffer: CVPixelBuffer, overlay: FrameResult, at time: CMTime) {
        guard isRecording,
              let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              let ciContext = ciContext,
              videoInput.isReadyForMoreMediaData else {
            print("Skipping frame - not ready for more data")
            return
        }
        
        if startTime == nil {
            startTime = time
            assetWriter?.startSession(atSourceTime: startTime!)
        }
        
        // Create overlay and combine with frame
        let frame = CIImage(cvPixelBuffer: pixelBuffer)
        let overlayImage = createOverlayFrame(for: frame.extent, overlay)
        let combined = overlayImage.composited(over: frame)
        
        // Create a NEW pixel buffer for the combined image
        guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool,
              let newPixelBuffer = createPixelBuffer(from: pixelBufferPool) else {
            print("Failed to create new pixel buffer")
            return
        }
        
        // Render combined image to the NEW pixel buffer
        ciContext.render(combined, to: newPixelBuffer)
        
        // Append the new pixel buffer with error handling
        let success = pixelBufferAdaptor.append(newPixelBuffer, withPresentationTime: time)
        if !success {
            if let error = assetWriter?.error {
                print("Failed to append pixel buffer: \(error)")
            } else {
                print("Failed to append pixel buffer: Unknown error")
            }
        }
    }
    
    /// Helper method to create a pixel buffer from the pool
    private func createPixelBuffer(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess else {
            print("Error creating pixel buffer from pool: \(status)")
            return nil
        }
        return pixelBuffer
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
        
        // Clean up resources
        ciContext = nil
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        startTime = nil
        frameCount = 0
        
        return (success: success, error: error)
    }
    
    func createOverlayFrame(for size: CGRect, _ overlay: FrameResult) -> CIImage {
        /// create a transparent image
        let transparentColor = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        var result = CIImage(color: transparentColor).cropped(to: size)
        
        /// box color
        let boxColor = CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.7)
        
        if let faces = overlay.faces {
            faces.forEach({ face in
                let faceBox: CGRect = face.boundingBox.toImageCoordinates(CGSize(width: size.width, height: size.height))
                let colorBox: CIImage = CIImage(color: boxColor).cropped(to: faceBox)
                result = colorBox.composited(over: result)
            })
        }
        
        return result
    }
}
