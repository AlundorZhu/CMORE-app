//
//  CameraManager.swift
//  CMORE
//
//  Manages all AVFoundation camera concerns: session setup, device configuration,
//  recording, delegate callbacks, and video saving to Photos.
//

import UIKit
import AVFoundation

class CameraManager: NSObject, AVCaptureFileOutputRecordingDelegate {
    // MARK: - Public Properties

    /// The camera capture session, exposed for use by CameraPreviewView
    private(set) var captureSession: AVCaptureSession?

    /// Whether the movie output is currently recording
    var isRecording: Bool { movieOutput?.isRecording ?? false }

    // MARK: - Callbacks

    /// Called on the videoOutputQueue when a new frame arrives
    var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?

    /// Called on the videoOutputQueue when AVFoundation drops a frame
    var onFrameDropped: ((CMTime) -> Void)?

    /// Called (on main) when movie file recording finishes
    var onRecordingFinished: ((URL, Error?) -> Void)?

    /// Called (on main) after a Photos-library save attempt completes
    var onVideoSavedToPhotos: ((Error?) -> Void)?

    // MARK: - Private Properties

    private var videoOutput: AVCaptureVideoDataOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private let videoOutputQueue = DispatchQueue(label: "videoOutputQueue", qos: .userInitiated)

    // MARK: - Setup

    func setup() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get camera with LiDAR device")
            return
        }

        let format = getFormat(for: camera)

        do {
            try camera.lockForConfiguration()

            camera.activeFormat = format
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(CameraSettings.frameRate))

            camera.unlockForConfiguration()

            print("Selected video format: \(camera.activeFormat)")
            print("Min frame duration: \(camera.activeVideoMinFrameDuration)")
            print("Max frame duration: \(camera.activeVideoMaxFrameDuration)")

            let shutterSpeed = camera.exposureDuration.seconds
            print("Shutter Speed: 1/\(Int(1 / shutterSpeed)) seconds")

            let actualFrameRate = 1.0 / camera.activeVideoMinFrameDuration.seconds
            print("Frame Rate: \(actualFrameRate) fps")

            captureSession = AVCaptureSession()
            captureSession?.sessionPreset = .inputPriority

            let cameraInput = try AVCaptureDeviceInput(device: camera)

            if captureSession?.canAddInput(cameraInput) == true {
                captureSession?.addInput(cameraInput)
            }

            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.alwaysDiscardsLateVideoFrames = true
            videoOutput?.setSampleBufferDelegate(self, queue: videoOutputQueue)

            if captureSession?.canAddOutput(videoOutput!) == true {
                captureSession?.addOutput(videoOutput!)
            }

            movieOutput = AVCaptureMovieFileOutput()

            if captureSession?.canAddOutput(movieOutput!) == true {
                captureSession?.addOutput(movieOutput!)
            }

        } catch {
            print("Error setting up camera: \(error)")
        }
    }

    func start() async {
        guard captureSession?.isRunning != true else { return }
        guard let captureSession = captureSession else {
            print("Capture session not available")
            return
        }
        captureSession.startRunning()
    }

    func stop() {
        Task {
            captureSession?.stopRunning()
        }
    }

    // MARK: - Recording

    func startRecording(to url: URL) {
        guard let movieOutput = movieOutput else {
            print("Movie output not available")
            return
        }

        if let connection = movieOutput.connection(with: .video) {
            connection.videoRotationAngle = 0.0
        }

        movieOutput.startRecording(to: url, recordingDelegate: self)
        print("Recording started")
    }

    func stopRecording() {
        guard let movieOutput = movieOutput, movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    // MARK: - Video Saving

    func saveVideoToPhotos(_ videoURL: URL) {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("Error: Video file not found")
            return
        }

        UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, self, #selector(video(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func video(_ videoPath: String, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if error == nil {
            let url = URL(fileURLWithPath: videoPath)
            try? FileManager.default.removeItem(at: url)
        }
        Task { @MainActor in
            self.onVideoSavedToPhotos?(error)
        }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate
    
    /// Called when recording starts successfully
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("Started recording to: \(fileURL)")
    }

    /// Called when recording finishes
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.onRecordingFinished?(outputFileURL, error)
        }
    }

    // MARK: - Private Helpers

    private func calculateISO(old shutterOld: CMTime, new shutterNew: CMTime, current ISO: Float) -> Float {
        let factor = shutterOld.seconds / shutterNew.seconds
        return ISO * Float(factor)
    }

    private func getFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format {
        let allFormats = device.formats

        let hasCorrectResolution: (AVCaptureDevice.Format) -> Bool = { format in
            format.formatDescription.dimensions.width == Int(CameraSettings.resolution.width) &&
            format.formatDescription.dimensions.height == Int(CameraSettings.resolution.height)
        }

        let supportsFrameRate: (AVCaptureDevice.Format) -> Bool = { format in
            format.videoSupportedFrameRateRanges.contains { (range: AVFrameRateRange) in
                range.minFrameRate <= CameraSettings.frameRate && CameraSettings.frameRate <= range.maxFrameRate
            }
        }

        guard let targetFormat = (allFormats.first { format in
            hasCorrectResolution(format) &&
            supportsFrameRate(format)
        }) else {
            fatalError("No supported format")
        }

        return targetFormat
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let currentTime = sampleBuffer.presentationTimeStamp

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Fail to get pixel buffer!")
            return
        }

        onFrameCaptured?(pixelBuffer, currentTime)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let currentTime = sampleBuffer.presentationTimeStamp
        onFrameDropped?(currentTime)
    }
}
