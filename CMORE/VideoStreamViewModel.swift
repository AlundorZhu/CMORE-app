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
class VideoStreamViewModel: NSObject, ObservableObject {
    @Published var image: UIImage?
    @Published var isStreaming = false
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    private let videoOutputQueue = DispatchQueue(label: "videoOutputQueue", qos: .userInitiated)
    
    override init() {
        super.init()
        setupCamera()
    }
    
    deinit {
        stopStreaming()
    }
    
    // MARK: - Public Methods
    func toggleStreaming() {
        if isStreaming {
            stopStreaming()
        } else {
            startStreaming()
        }
    }
    
    func loadVideo(from url: URL) {
        // Stop current streaming if active
        if isStreaming {
            stopStreaming()
        }
        
        // Load first frame from video
        loadVideoFrame(from: url)
    }
    
    // MARK: - Private Methods
    private func setupCamera() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get camera device")
            return
        }
        
        do {
            captureSession = AVCaptureSession()
            captureSession?.sessionPreset = .medium
            
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            
            if captureSession?.canAddInput(cameraInput) == true {
                captureSession?.addInput(cameraInput)
            }
            
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.setSampleBufferDelegate(self, queue: videoOutputQueue)
            
            if captureSession?.canAddOutput(videoOutput!) == true {
                captureSession?.addOutput(videoOutput!)
            }
            
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    private func startStreaming() {
        guard let captureSession = captureSession else { return }
        
        Task {
            captureSession.startRunning()
            await MainActor.run {
                self.isStreaming = true
            }
        }
    }
    
    private func stopStreaming() {
        Task {
            captureSession?.stopRunning()
            await MainActor.run {
                self.isStreaming = false
            }
        }
    }
    
    private func loadVideoFrame(from url: URL) {
        Task {
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            let time = CMTime(seconds: 0, preferredTimescale: 1)
            
            do {
                let cgImage = try await imageGenerator.image(at: time).image
                let uiImage = UIImage(cgImage: cgImage)
                
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
extension VideoStreamViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        Task { @MainActor in
            self.image = uiImage
        }
    }
}

