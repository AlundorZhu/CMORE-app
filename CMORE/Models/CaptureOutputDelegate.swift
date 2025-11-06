//
//  CaptureOutputDelegate.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 11/6/25.
//

import AVFoundation

class CaptureOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private var frameNum: UInt = 0
    
    private let maxFrameBehind = 12
    
    private var numFrameBehind = 0
    
    private var lastTimestamp: CMTime?
    
    private let frameProcessor: FrameProcessor
    
    private let frameResultHandler: (FrameResult) -> Void
    
    init(frameNum: UInt = 0, numFrameBehind: Int = 0, lastTimestamp: CMTime? = nil, frameProcessor: FrameProcessor, forFrameResult frameResultHandler: @escaping (FrameResult) -> Void) {
        self.frameNum = frameNum
        self.numFrameBehind = numFrameBehind
        self.lastTimestamp = lastTimestamp
        self.frameProcessor = frameProcessor
        self.frameResultHandler = frameResultHandler
    }
    
    
    /// Called for each new camera frame - processes for face detection and records if recording
    /// - Parameters:
    ///   - output: The capture output that produced the frame
    ///   - sampleBuffer: The frame data
    ///   - connection: The connection information
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        let currentTime = sampleBuffer.presentationTimeStamp
        frameNum += 1
        
        print(String(repeating: "-", count: 50))
        
        if let last = lastTimestamp {
            let delta = CMTimeGetSeconds(currentTime - last)
            let actualFPS = 1.0 / delta
            print("Actual FPS: \(actualFPS)")
        }
        
        lastTimestamp = currentTime
        
        // Avoid pile up on frames
        guard numFrameBehind < maxFrameBehind else {
            print("Current buffered number of frames: \(numFrameBehind)")
            print("Skipped! Frame: \(frameNum)")
            return
        }
        
        print("Processing Frame: \(frameNum)")
        
        // Extract the pixel buffer from the sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Process the frame
        Task {

            let processedResult = await frameProcessor.processFrame(pixelBuffer)
            
            frameResultHandler(processedResult)
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameNum += 1
        print("Avfundation Dropped frame: \(frameNum) automatically!")
    }
}
