//
//  Camera.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 11/5/25.
//

import AVFoundation

class Camera: NSObject, AVCaptureFileOutputRecordingDelegate {
    
    var isRecording: Bool {
        if let movieOutput {
            return movieOutput.isRecording
        }
        return false
    }
    
    /// The main camera capture session - manages camera input and output
    public private(set) var captureSession: AVCaptureSession?
    
    /// Handles video data output from the camera
    private var videoOutput: AVCaptureVideoDataOutput?
    
    /// Handles movie file output for recording
    private var movieOutput: AVCaptureMovieFileOutput?
    
    /// Called when recording finishes
    private var finishHandle: ((_ error: Error?) -> Void)?
    
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
    public func setupCamera(outputFrameTo frameReceiver: AVCaptureVideoDataOutputSampleBufferDelegate, on videoOutputQueue: DispatchQueue) {
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
            videoOutput?.setSampleBufferDelegate(frameReceiver, queue: videoOutputQueue)
            
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
        
    /// Stops the camera feed (called when app is destroyed)
    public func stopCamera() {
        // Use Task for async operation
        Task {
            captureSession?.stopRunning()
        }
    }
    
    /// Starts video recording to a file
    public func startRecording(to outputURL: URL, whenFinishRecording finishHandle: @escaping (_ error: Error?) -> Void) {
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
        
        
        // Start recording with the movie output
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        print("Recording started")
        
        // Set up handler when Recording finishes
        self.finishHandle = finishHandle
    }
    
    /// Stops video recording
    public func stopRecording() {
        guard let movieOutput = movieOutput else { return }
        
        // Check if actually recording
        guard movieOutput.isRecording else { return }
        
        // Stop recording - delegate methods will be called when finished
        movieOutput.stopRecording()
    }
    
    /// Called when recording starts successfully
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("Started recording to: \(fileURL)")
    }
    
    /// Called when recording finishes
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let finishHandle {
            finishHandle(error)
        }
    }
}
