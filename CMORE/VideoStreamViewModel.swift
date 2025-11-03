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
class VideoStreamViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    // @Published automatically notifies the UI when these values change
    
    /// Whether the camera is currently recording video
    @Published var isRecording = false
    
    /// Status message for recording operations
//    @Published var recordingStatusMessage: String?
    
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
    
    private var processingTasks: [UInt: Task<Void,Never>] = [:]
    
    /// For recording
    private var packetBuffer: Heap<FramePacket> = []
    
    private struct FramePacket: Comparable {
        let time: CMTime
        let pixelBuffer: CVImageBuffer
        let overlay: FrameResult
        
        static func < (lhs: FramePacket, rhs: FramePacket) -> Bool {
            return lhs.time < rhs.time
        }
        
        static func == (lhs: FramePacket, rhs: FramePacket) -> Bool {
            return lhs.time == rhs.time
        }
    }
    
    private var frameStream: AsyncStream<FramePacket>?
    private var frameContinuation: AsyncStream<FramePacket>.Continuation?
    private var writerTask: Task<Void, Never>?
    
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
    
    /// Starts the camera feed
    func startCamera() async {
        guard captureSession?.isRunning != true else { return }
        guard let captureSession = captureSession else {
            print("Capture session not available")
            return
        }
        captureSession.startRunning()
    }
    
    // MARK: - Private Methods
    
    // Calculate New ISO by a factor of change in shutter spee
    private func calculateISO(old shutterOld: CMTime, new shutterNew: CMTime, current ISO: Float) -> Float {
        let factor = shutterOld.seconds / shutterNew.seconds
        return ISO * Float(factor)
    }
    
    // Check supported format
    private func getFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format {
        
        let allFormats = device.formats
            
        // Break down the complex condition into separate predicates
        let hasCorrectResolution: (AVCaptureDevice.Format) -> Bool = { format in
            format.formatDescription.dimensions.width == 1920 &&
            format.formatDescription.dimensions.height == 1080
        }
        
//        let hasDepthDataSupport: (AVCaptureDevice.Format) -> Bool = { format in
//            !format.supportedDepthDataFormats.isEmpty
//        }
        
        let supportsFrameRate: (AVCaptureDevice.Format) -> Bool = { format in
            format.videoSupportedFrameRateRanges.contains { (range: AVFrameRateRange) in
                range.minFrameRate <= CameraSettings.frameRate && CameraSettings.frameRate <= range.maxFrameRate
            }
        }
        
        // Combine the conditions
        guard let targetFormat = (allFormats.first { format in
            hasCorrectResolution(format) &&
//            hasDepthDataSupport(format) &&
            supportsFrameRate(format)
        }) else {
            fatalError("No supported format")
        }
        
        return targetFormat
    }
    
    /// Sets up the camera capture session
    /// Camera starts automatically, no separate streaming control needed
    private func setupCamera() {
        // Get the default LiDAR depth camera (back camera)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get camera with LiDAR device")
            return
        }

        let format = getFormat(for: camera)
        
        do {
            // Configure camera settings before creating capture session
            try camera.lockForConfiguration()

            camera.activeFormat = format
            /// Set the max exposure duration to allow faster shutter speeds (not possible)
//            camera.activeFormat.maxExposureDuration = CameraSettings.maxExposureDuration
            /// Set the minimum frame duration to control frame rate
//            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(CameraSettings.frameRate))
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(CameraSettings.frameRate))
//            camera.setExposureModeCustom(duration: CameraSettings.maxExposureDuration, iso: AVCaptureDevice.currentISO)

            camera.unlockForConfiguration()
            
            print("Selected video format: \(camera.activeFormat)")
            
            print("Min frame duration: \(camera.activeVideoMinFrameDuration)")
            print("Max frame duration: \(camera.activeVideoMaxFrameDuration)")
            
            // print the actual shutter speed and frame rate
            let shutterSpeed = camera.exposureDuration.seconds
            print("Shutter Speed: 1/\(Int(1 / shutterSpeed)) seconds")
            
            // print the actual frame rate
            let actualFrameRate = 1.0 / camera.activeVideoMinFrameDuration.seconds
            print("Frame Rate: \(actualFrameRate) fps")
            
            
            // Create and configure the capture session
            captureSession = AVCaptureSession()
            captureSession?.sessionPreset = .inputPriority
            
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
        
        // Create a channel (AsyncStream) for frames
        frameStream = AsyncStream<FramePacket> { continuation in
            self.frameContinuation = continuation
        }
        
        // Start recording with the video writer
        Task{
            
            // ensure the recording started successfully.
            if await videoWriter.startRecording(to: outputURL) {
                
                // Start the block counting algorithm
                await frameProcessor.startCountingBlocks()
                
                // Launch the writer task that consumes the stream
                writerTask = Task.detached { [weak self] in
                    guard let self, let stream = self.frameStream else { return }
                    for await packet in stream {
                        await self.videoWriter?.append(packet.pixelBuffer, overlay: packet.overlay, at: packet.time)
                    }
                }
                
                // Update UI
                await MainActor.run {
                    print("Recording started")
                    self.currentVideoURL = outputURL
                }
            } else {
                await MainActor.run {
                    print("Failed to start recording")
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
            
            // Wait to finish all the processing tasks
            let tasks = processingTasks.values
            for task in tasks {
                await task.value
            }
            
            // Push the rest of packet to the stream
            while !packetBuffer.isEmpty {
                frameContinuation?.yield(packetBuffer.popMin()!)
            }
            
            // Finish the stream so the writer loop can exit
            frameContinuation?.finish()
            frameContinuation = nil

            // Wait for the writer to finish draining and exit
            await writerTask?.value
            writerTask = nil
            
            let result = await videoWriter.stopRecording()
            
            await MainActor.run {
                self.isRecording = false
                
                if let error = result.error {
                    print("Recording error: \(error)")
                } else if result.success {
                    // Successfully recorded - ask user to save or discard
                    print("Recording completed with face detection! Save or discard?")
                    self.showSaveConfirmation = true
                } else {
                    print("Recording failed: Unknown error")
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
        guard processingTasks.count < maxFrameBehind else {
            print("Current buffered number of frames: \(processingTasks.count)")
            print("Skipped! Frame: \(frameNum)")
            return
        }
        
        print("Processing Frame: \(frameNum)")
        
        // Extract the pixel buffer from the sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Process the frame - capture frameNum to avoid race condition
        let currentFrameNum = frameNum
        processingTasks[currentFrameNum] = Task {

            defer { processingTasks[currentFrameNum] = nil }
            let processedResult = await frameProcessor.processFrame(pixelBuffer)
            
            await MainActor.run {
                self.overlay = processedResult
            }
            
            // If recording, add this frame to the jobs dictionary
            if isRecording {
                let packet = FramePacket(time: currentTime, pixelBuffer: pixelBuffer, overlay: processedResult)
                packetBuffer.insert(packet)
                
                frameContinuation?.yield(packetBuffer.popMin()!)
            }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameNum += 1
        print("Avfundation Dropped frame: \(frameNum) automatically!")
    }
}

// MARK: - Video Saving Methods
extension VideoStreamViewModel {
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

