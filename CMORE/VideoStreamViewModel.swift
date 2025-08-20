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
    
    /// The current image being displayed from the camera
    @Published var image: UIImage?
    
    /// Whether the camera is currently recording video
    @Published var isRecording = false
    
    /// Status message for recording operations
    @Published var recordingStatusMessage: String?
    
    /// Whether to show the save confirmation dialog
    @Published var showSaveConfirmation = false
    
    /// The URL of the current video being processed (temporary)
    private var currentVideoURL: URL?
    
    // MARK: - Private Properties
    
    /// The main camera capture session - manages camera input and output
    private var captureSession: AVCaptureSession?
    
    /// Handles video data output from the camera
    private var videoOutput: AVCaptureVideoDataOutput?
    
    /// Handles movie file output for recording
    private var movieOutput: AVCaptureMovieFileOutput?
    
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.recordingStatusMessage = nil
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Sets up the camera capture session
    /// Camera starts automatically, no separate streaming control needed
    private func setupCamera() {
        // Get the default wide-angle camera (back camera)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get camera device")
            return
        }
        
        do {
            // Create and configure the capture session
            captureSession = AVCaptureSession()
            captureSession?.sessionPreset = .medium // Medium quality for better performance
            
            // Create input from the camera
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            
            // Add camera input to the session
            if captureSession?.canAddInput(cameraInput) == true {
                captureSession?.addInput(cameraInput)
            }
            
            // Set up video output to receive frames
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.setSampleBufferDelegate(self, queue: videoOutputQueue)
            
            // Add video output to the session
            if captureSession?.canAddOutput(videoOutput!) == true {
                captureSession?.addOutput(videoOutput!)
            }
            
            // Set up movie file output for recording
            movieOutput = AVCaptureMovieFileOutput()
            
            // Add movie output to the session
            if captureSession?.canAddOutput(movieOutput!) == true {
                captureSession?.addOutput(movieOutput!)
            }
            
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    /// Starts the camera feed (called automatically)
    private func startCamera() {
        guard let captureSession = captureSession else { return }
        
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
        guard let movieOutput = movieOutput else {
            print("Movie output not available")
            return
        }
        
        // Don't start recording if already recording
        guard !movieOutput.isRecording else { return }
        
        // Create a unique filename for the recorded video
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videoFileName = "CMORE_Recording_\(Date().timeIntervalSince1970).mov"
        let outputURL = documentsPath.appendingPathComponent(videoFileName)
        
        // Remove any existing file at this location
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        // Start recording to the file
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        
        // Update UI
        Task { @MainActor in
            self.isRecording = true
            self.recordingStatusMessage = "Recording started..."
        }
    }
    
    /// Stops video recording
    private func stopRecording() {
        guard let movieOutput = movieOutput else { return }
        
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        
        // Update UI
        Task { @MainActor in
            self.isRecording = false
            self.recordingStatusMessage = "Recording stopped"
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
/// This extension handles camera frame data for live preview display
extension VideoStreamViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called for each new camera frame - displays live preview
    /// - Parameters:
    ///   - output: The capture output that produced the frame
    ///   - sampleBuffer: The frame data
    ///   - connection: The connection information
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Extract the pixel buffer from the sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Convert to CIImage for processing
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Process the frame for face detection (runs on background thread)
        frameProcessor.processFrame(ciImage)

        // Convert to UIImage for display
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        
        // Update UI on main thread
        Task { @MainActor in
            self.image = uiImage
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
/// This extension handles video recording events (start, finish, errors)
extension VideoStreamViewModel: AVCaptureFileOutputRecordingDelegate {
    /// Called when recording starts successfully
    /// - Parameters:
    ///   - output: The file output that started recording
    ///   - fileURL: The URL where the video is being saved
    ///   - connections: The connections involved in recording
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Task { @MainActor in
            self.recordingStatusMessage = "Recording to: \(fileURL.lastPathComponent)"
        }
    }
    
    /// Called when recording finishes (successfully or with error)
    /// - Parameters:
    ///   - output: The file output that finished recording
    ///   - outputFileURL: The URL where the video was saved
    ///   - connections: The connections involved in recording
    ///   - error: Any error that occurred during recording
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.recordingStatusMessage = "Recording failed: \(error.localizedDescription)"
                print("Recording error: \(error)")
            } else {
                // Successfully recorded - ask user to save or discard (one-time choice)
                self.currentVideoURL = outputFileURL
                self.recordingStatusMessage = "Recording completed! Save or discard?"
                self.showSaveConfirmation = true
            }
        }
    }
    
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.recordingStatusMessage = nil
                }
            }
        }
    }
}

