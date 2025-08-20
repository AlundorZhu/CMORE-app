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
/// This class manages camera streaming and video processing logic
/// It uses the MVVM (Model-View-ViewModel) pattern to separate business logic from UI
/// SIMPLIFICATION SUGGESTIONS:
/// 1. Consider splitting this into separate classes for camera and video file handling
/// 2. Error handling could be more robust with proper user feedback
/// 3. The frame processing could be made optional to reduce complexity
class VideoStreamViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    // @Published automatically notifies the UI when these values change
    
    /// The current image being displayed (from camera or video file)
    @Published var image: UIImage?
    
    /// Whether the camera is currently streaming
    @Published var isStreaming = false
    
    // MARK: - Private Properties
    
    /// The main camera capture session - manages camera input and output
    private var captureSession: AVCaptureSession?
    
    /// Handles video data output from the camera
    private var videoOutput: AVCaptureVideoDataOutput?
    
    /// Preview layer for camera (currently unused but available for future use)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
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
        stopStreaming()
    }
    
    // MARK: - Public Methods
    
    /// Toggles camera streaming on/off
    func toggleStreaming() {
        if isStreaming {
            stopStreaming()
        } else {
            startStreaming()
        }
    }
    
    /// Loads a video file and displays its first frame
    /// - Parameter url: The URL of the video file to load
    func loadVideo(from url: URL) {
        // Stop current streaming if active to avoid conflicts
        if isStreaming {
            stopStreaming()
        }
        
        // Load and display the first frame from the video
        loadVideoFrame(from: url)
    }
    
    // MARK: - Private Methods
    
    /// Sets up the camera capture session
    /// SIMPLIFICATION SUGGESTION: Add better error handling and user feedback
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
            
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    /// Starts the camera streaming
    private func startStreaming() {
        guard let captureSession = captureSession else { return }
        
        // Use Task for async operation to avoid blocking the UI
        Task {
            captureSession.startRunning()
            // Update UI on main thread
            await MainActor.run {
                self.isStreaming = true
            }
        }
    }
    
    /// Stops the camera streaming
    private func stopStreaming() {
        // Use Task for async operation
        Task {
            captureSession?.stopRunning()
            // Update UI on main thread
            await MainActor.run {
                self.isStreaming = false
            }
        }
    }
    
    /// Loads and displays the first frame from a video file
    /// - Parameter url: The URL of the video file
    /// SIMPLIFICATION SUGGESTION: Could add progress indicator for long videos
    private func loadVideoFrame(from url: URL) {
        Task {
            // Create an asset from the video file
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            
            // Ensure the image orientation matches the video
            imageGenerator.appliesPreferredTrackTransform = true
            
            // Get the frame at time 0 (first frame)
            let time = CMTime(seconds: 0, preferredTimescale: 1)
            
            do {
                // Generate the image from the video
                let cgImage = try await imageGenerator.image(at: time).image
                let uiImage = UIImage(cgImage: cgImage)
                
                // Update UI on main thread
                await MainActor.run {
                    self.image = uiImage
                }
            } catch {
                print("Error loading video frame: \(error)")
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
/// This extension handles camera frame data as it comes in
/// SIMPLIFICATION SUGGESTION: This could be simplified by making frame processing optional
extension VideoStreamViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called for each new camera frame
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

