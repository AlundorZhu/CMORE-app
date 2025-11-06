//
//  VideoStreamViewModel.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/19/25.
//

import UIKit
import SwiftUI
import Collections
import AVFoundation
import AudioToolbox
import UniformTypeIdentifiers

// MARK: - VideoStreamViewModel
/// This class manages camera recording functionality with a simplified interface
/// It uses the MVVM (Model-View-ViewModel) pattern to separate business logic from UI
/// SIMPLIFIED: Removed video file loading, automatic camera startup, single recording button
class CMOREViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    // @Published automatically notifies the UI when these values change
    
    /// Whether the camera is currently recording video
    @Published var isRecording = false
    
    /// Whether to show the save confirmation dialog
    @Published var showSaveConfirmation = false
    
    /// Show the visualization overlay in real-time
    @Published var overlay: FrameResult?
    
    private let camera = Camera()
    
    /// The URL of the current video being processed (temporary)
    private var currentVideoURL: URL?
    
    /// Number of frames currently waiting to get processed
    private var numFrameBehind: Int = 0
    
    /// Maximum of frames allowed to buffer before droping frames
    private let maxFrameBehind: Int = 12
    
    /// Tracks the current frame number
    private var frameNum: UInt = 0
    
    /// Background queue for processing video frames (keeps UI responsive)
    private let videoOutputQueue = DispatchQueue(label: "videoOutputQueue", qos: .userInitiated)
    
    /// Processes each frame through it
    private let frameProcessor = FrameProcessor(onCross: {
        AudioServicesPlaySystemSound(1054)
    })
    
    /// For fps calculation
    private var lastTimestamp: CMTime?
    
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        
        camera.setupCamera(outputFrameTo: <#T##any AVCaptureVideoDataOutputSampleBufferDelegate#>, on: <#T##DispatchQueue#>)
    }
    
    /// Clean up when the ViewModel is destroyed
    deinit {
        camera.stopCamera()
    }
    
    /// Toggles video recording on/off (main functionality)
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /// Saves the pending video to Photos library (called when user confirms)
    func saveVideoToPhotos() {
        guard let videoURL = currentVideoURL else { return }
        saveVideoToPhotosLibrary(videoURL)
        currentVideoURL = nil
        showSaveConfirmation = false
    }
    
    /// Discards the pending video (called when user declines)
    func discardVideo() {
        guard let videoURL = currentVideoURL else { return }
        
        // Delete the temporary file
        try? FileManager.default.removeItem(at: videoURL)
        
        // Update UI
        Task { @MainActor in
            print("Video discarded")
            self.currentVideoURL = nil
            self.showSaveConfirmation = false
        }
    }
    
    /// Starts video recording to a file
    private func startRecording() {
        guard let movieOutput = movieOutput else {
            print("Movie output not available")
            return
        }

        // Don't start recording if already recording
        guard !isRecording else { return }
        
        isRecording = true
            
        // Create a unique filename for the recorded video
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videoFileName = "CMORE_Recording_\(Date().timeIntervalSince1970).mov"
        let outputURL = documentsPath.appendingPathComponent(videoFileName)
        
        // Store the URL for later use
        currentVideoURL = outputURL
        
        // Start recording with the movie output
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        print("Recording started")
        
        // Start the block counting algorithm
        Task {
            await frameProcessor.startCountingBlocks()
        }
    }
    
    /// Stops video recording
    private func stopRecording() {
        guard let movieOutput = movieOutput else { return }
        
        /// Recording has to be started
        guard isRecording else { return }
        
        // Check if actually recording
        guard movieOutput.isRecording else { return }
        
        isRecording = false
        
        // Stop the block counting algorithm
        Task {
            await frameProcessor.stopCountingBlocks()
        }
        
        // Stop recording - delegate methods will be called when finished
        movieOutput.stopRecording()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
/// This extension handles camera frame data for face detection processing and video recording
extension CMOREViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
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
            
            await MainActor.run {
                self.overlay = processedResult
            }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameNum += 1
        print("Avfundation Dropped frame: \(frameNum) automatically!")
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
///// This extension handles movie file recording callbacks
//extension VideoStreamViewModel {
//    /// Called when recording starts successfully
//    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
//        print("Started recording to: \(fileURL)")
//    }
//    
//    /// Called when recording finishes
//    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
//        Task { @MainActor in
//            if let error = error {
//                print("Recording error: \(error.localizedDescription)")
//                // Clean up on error
//                self.currentVideoURL = nil
//            } else {
//                // Successfully recorded - ask user to save or discard
//                print("Recording completed! Save or discard?")
//                self.showSaveConfirmation = true
//            }
//        }
//    }
//}

// MARK: - Video Saving Methods
extension CMOREViewModel {
    /// Saves the recorded video to the Photos library
    /// - Parameter videoURL: The URL of the recorded video file
    private func saveVideoToPhotosLibrary(_ videoURL: URL) {
        // Check if the file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("Error: Video file not found")
            return
        }
        
        // Save to Photos library
        UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, self, #selector(video(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    /// Callback for Photos library save operation
    /// - Parameters:
    ///   - videoPath: Path to the video file
    ///   - error: Any error that occurred during saving
    ///   - contextInfo: Additional context (unused)
    @objc private func video(_ videoPath: String, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        Task { @MainActor in
            if let error = error {
                print("Error: Failed to save video: \(error.localizedDescription)")
            } else {
                print("Video saved to Photos!")
                
                // Clean up the temporary file after successful save
                let url = URL(fileURLWithPath: videoPath)
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

