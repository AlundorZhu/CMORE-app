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
                    AVVideoCodecKey: AVVideoCodecType.hevc,
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
    
    func append(_ pixelBuffer: CVPixelBuffer, overlay: FrameResult, at time: CMTime) {
        guard isRecording,
              let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData else {
            return
        }
        
        let frame = CIImage(cvPixelBuffer: pixelBuffer)
        let overlay = createOverlayFrame(for: frame.extent, overlay)
        let combined = overlay.composited(over: frame)
        
        // Render combined image back into the same pixel buffer
        let ciContext = CIContext()
        ciContext.render(combined, to: pixelBuffer)
        
        pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: time)
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
