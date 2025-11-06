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
class CMOREViewModel: ObservableObject {
    // MARK: - Published Properties
    // @Published automatically notifies the UI when these values change
    
    /// Whether the camera is currently recording video
    @Published var isRecording = false
    
    /// Whether to show the save confirmation dialog
    @Published var showSaveConfirmation = false
    
    /// Show the visualization overlay in real-time
    @Published var overlay: FrameResult?
    
    public let camera: Camera
    
    /// The URL of the current video being processed (temporary)
    private var currentVideoURL: URL?
    
    /// Background queue for processing video frames (keeps UI responsive)
    private let videoOutputQueue: DispatchQueue
    
    /// Processes each frame through it
    private let frameProcessor: FrameProcessor
    
    private lazy var captureOutputDelegate: CaptureOutputDelegate = {
        return CaptureOutputDelegate(frameProcessor: self.frameProcessor, forFrameResult: { [weak self] (result: FrameResult) in
            Task { @MainActor in
                self?.overlay = result
            }
        })
    }()
    
    
    // MARK: - Initialization
    
    init() {
        self.videoOutputQueue = DispatchQueue(label: "videoOutputQueue", qos: .userInitiated)
        
        self.camera = Camera()
        
        self.frameProcessor = FrameProcessor(onCross: {
            AudioServicesPlaySystemSound(1054)
        })
        
        self.camera.setupCamera(outputFrameTo: self.captureOutputDelegate, on: self.videoOutputQueue)
        
        Task {
            await self.camera.startCamera()
        }
    }
    
    /// Clean up when the ViewModel is destroyed
    deinit {
        camera.stopCamera()
    }
    
    /// Toggles video recording on/off (main functionality)
    func toggleRecording() {
        if camera.isRecording {
            isRecording = false
            Task { await frameProcessor.stopCountingBlocks() }
            camera.stopRecording()
        } else {
            // Create a unique filename for the recorded video
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let videoFileName = "CMORE_Recording_\(Date().timeIntervalSince1970).mov"
            let outputURL = documentsPath.appendingPathComponent(videoFileName)
            
            currentVideoURL = outputURL
            
            camera.startRecording(to: outputURL, whenFinishRecording: { error in
                if let error {
                    print("Recording error: \(error.localizedDescription)")
                    // Clean up on error
                    self.currentVideoURL = nil
                } else {
                    // Successfully recorded - ask user to save or discard
                    print("Recording completed! Save or discard?")
                    self.showSaveConfirmation = true
                }
            })
            
            Task { await frameProcessor.startCountingBlocks() }
            
            isRecording = true
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
}

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

