//
//  VideoStreamViewModel.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/19/25.
//
import SwiftUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers

// MARK: - VideoStreamViewModel
/// This class manages camera recording functionality with a simplified interface
/// It uses the MVVM (Model-View-ViewModel) pattern to separate business logic from UI
/// SIMPLIFIED: Removed video file loading, automatic camera startup, single recording button
class VideoStreamViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    // @Published automatically notifies the UI when these values change
    
    /// Whether the camera is currently recording video
    @Published var isRecording = false
    
    /// Status message for recording operations
    @Published var recordingStatusMessage: String?
    
    /// Whether to show the save confirmation dialog
    @Published var showSaveConfirmation = false
    
    /// Show the visualization overlay in real-time
    @Published var overlay: FrameResult?
    
    /// The main camera capture session - manages camera input and output
    public private(set) var captureSession: AVCaptureSession?
    
    /// The URL of the current video being processed (temporary)
    private var currentVideoURL: URL?
    
    /// Handles video data output from the camera
    private var videoOutput: AVCaptureVideoDataOutput?
    
    /// Custom video writer for recording processed frames with face detection
    private var videoWriter: VideoWriter?
    
    /// Number of frames currently waiting to get processed
    private var numFrameBehind: Int = 0
    
    /// Maximum of frames allowed to buffer before droping frames
    private let maxFrameBehind: Int = 3
    
    /// Background queue for processing video frames (keeps UI responsive)
    private let videoOutputQueue = DispatchQueue(label: "videoOutputQueue", qos: .userInitiated)
    
    /// Processes each frame for face detection
    private let frameProcessor = FrameProcessor()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupCamera() // Initialize camera when ViewModel is created
    }
    
    /// Clean up when the ViewModel is destroyed
    deinit {
        stopCamera()
    }
    
    // MARK: - Public Methods
    
    /// Starts the camera automatically when the app launches
    func startCameraAutomatically() {
        guard captureSession?.isRunning != true else { return }
        startCamera()
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
            self.recordingStatusMessage = "Video discarded"
            self.currentVideoURL = nil
            self.showSaveConfirmation = false
            
            // Clear message after a delay
            try? await Task.sleep(for: .seconds(2))
            self.recordingStatusMessage = nil
        }
    }
    
    // MARK: - Private Methods
    
    // Calculate New ISO by a factor of change in shutter spee
    private func calculateISO(old shutterOld: CMTime, new shutterNew: CMTime, current ISO: Float) -> Float {
        let factor = shutterOld.seconds / shutterNew.seconds
        return ISO * Float(factor)
    }
    
    /// Sets up the camera capture session
    /// Camera starts automatically, no separate streaming control needed
    private func setupCamera() {
        // Get the default wide-angle camera (back camera)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get camera device")
            return
        }
        
        do {
            // Configure camera settings before creating capture session
            try camera.lockForConfiguration()
            
            // Set frame rate
            camera.activeVideoMinFrameDuration = CameraSettings.frameRate
            camera.activeVideoMaxFrameDuration = CameraSettings.frameRate

            let newISO = calculateISO(
                old: camera.exposureDuration,
                new: CameraSettings.ShutterSpeed,
                current: camera.iso
            )

            print("Current ISO: \(camera.iso)")
            print("Target ISO: \(newISO)")

            print("Current Shutter Speed: \(camera.exposureDuration)")

            let clampedISO = min(max(newISO, camera.activeFormat.minISO), camera.activeFormat.maxISO)
            print("Clamped ISO: \(clampedISO)")


            // Set shutter speed
            camera.setExposureModeCustom(
                duration: CameraSettings.ShutterSpeed,
                iso: clampedISO,
                completionHandler: { (timestamp) in
                    // This runs after the camera has actually applied the new settings
                    print("Shutter Speed (after): \(camera.exposureDuration)")
                    print("ISO (after): \(camera.iso)")
                }
            )

            camera.unlockForConfiguration()
            
            // Create and configure the capture session
            captureSession = AVCaptureSession()
            
            // Create input from the camera
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            
            // Add camera input to the session
            if captureSession?.canAddInput(cameraInput) == true {
                captureSession?.addInput(cameraInput)
            }
            
            // Set up video output to receive frames
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.alwaysDiscardsLateVideoFrames = true
            videoOutput?.setSampleBufferDelegate(self, queue: videoOutputQueue)
            
            // Add video output to the session
            if captureSession?.canAddOutput(videoOutput!) == true {
                captureSession?.addOutput(videoOutput!)
            }
            
            // Initialize video writer with camera settings
            videoWriter = VideoWriter()
            
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    /// Starts the camera feed (called automatically)
    private func startCamera() {
        
        guard let captureSession = captureSession else {
            print("Capture session not available")
            return
        }
        // Use Task for async operation to avoid blocking the UI
        Task {
            captureSession.startRunning()
        }
    }
    
    /// Stops the camera feed (called when app is destroyed)
    private func stopCamera() {
        // Use Task for async operation
        Task {
            captureSession?.stopRunning()
        }
    }
    
    /// Starts video recording to a file
    private func startRecording() {
        guard let videoWriter = videoWriter else {
            print("Video writer not available")
            return
        }

        // Don't start recording if already recording
        guard !isRecording else { return }
        
        isRecording = true
            
        // Create a unique filename for the recorded video
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videoFileName = "CMORE_Recording_\(Date().timeIntervalSince1970).mov"
        let outputURL = documentsPath.appendingPathComponent(videoFileName)
        
        // Start recording with the video writer
        Task{
            if await videoWriter.startRecording(to: outputURL) {
                
                // Start the block counting algorithm
                await frameProcessor.startCountingBlocks()
                
                // Update UI
                await MainActor.run {
                    self.recordingStatusMessage = "Recording started with face detection..."
                    self.currentVideoURL = outputURL
                }
            } else {
                await MainActor.run {
                    self.recordingStatusMessage = "Failed to start recording"
                }
            }
        }
    }
    
    /// Stops video recording
    private func stopRecording() {
        guard let videoWriter = videoWriter else { return }
        
        /// Recording has to be started
        guard isRecording else { return }
        isRecording = false
        
        // Stop recording with async/await
        Task {
            
            await frameProcessor.stopCountingBlocks()
            
            let result = await videoWriter.stopRecording()
            
            await MainActor.run {
                self.isRecording = false
                
                if let error = result.error {
                    self.recordingStatusMessage = "Recording failed: \(error.localizedDescription)"
                    print("Recording error: \(error)")
                } else if result.success {
                    // Successfully recorded - ask user to save or discard
                    self.recordingStatusMessage = "Recording completed with face detection! Save or discard?"
                    self.showSaveConfirmation = true
                } else {
                    self.recordingStatusMessage = "Recording failed: Unknown error"
                }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
/// This extension handles camera frame data for face detection processing and video recording
extension VideoStreamViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called for each new camera frame - processes for face detection and records if recording
    /// - Parameters:
    ///   - output: The capture output that produced the frame
    ///   - sampleBuffer: The frame data
    ///   - connection: The connection information
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Avoid pile up on frames
        guard numFrameBehind < maxFrameBehind else {
            print("Frame skipped!")
            return
        }
        
        numFrameBehind += 1
        
        // Extract the pixel buffer from the sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Convert to CIImage for processing
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Process the frame for face detection (runs on background thread)
        Task {
            let processedResult = await frameProcessor.processFrame(ciImage)
            
            await MainActor.run {
                self.overlay = processedResult
            }
            
            numFrameBehind -= 1
            
            
            // If recording, add this frame to the video writer
//            if isRecording,
//               let videoWriter = videoWriter {
//                videoWriter.appendFrame(processedFrame)
//            }
        }
    }
}

// MARK: - Video Saving Methods
extension VideoStreamViewModel {
    /// Saves the recorded video to the Photos library
    /// - Parameter videoURL: The URL of the recorded video file
    private func saveVideoToPhotosLibrary(_ videoURL: URL) {
        // Check if the file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            recordingStatusMessage = "Error: Video file not found"
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
                self.recordingStatusMessage = "Failed to save video: \(error.localizedDescription)"
            } else {
                self.recordingStatusMessage = "Video saved to Photos!"
                
                // Clean up the temporary file after successful save
                let url = URL(fileURLWithPath: videoPath)
                try? FileManager.default.removeItem(at: url)
                
                // Clear message after a delay
                try? await Task.sleep(for: .seconds(2))
                self.recordingStatusMessage = nil
            }
        }
    }
}



