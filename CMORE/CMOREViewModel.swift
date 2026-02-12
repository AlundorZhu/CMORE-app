//
//  VideoStreamViewModel.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/19/25.
//

import Vision
import AVFoundation
import AudioToolbox

// MARK: - VideoStreamViewModel
/// This class manages camera recording functionality with a simplified interface
/// It uses the MVVM (Model-View-ViewModel) pattern to separate business logic from UI
class CMOREViewModel: ObservableObject {
    // MARK: - Published Properties

    /// Whether the camera is currently recording video
    @Published var isRecording = false

    /// Whether to show the save confirmation dialog
    @Published var showSaveConfirmation = false

    /// Show the visualization overlay in real-time
    @Published var overlay: FrameResult?

    /// Use to help identify which hand we are looking at
    @Published var handedness: HumanHandPoseObservation.Chirality = .right

    /// The main camera capture session — forwarded from CameraManager
    var captureSession: AVCaptureSession? { cameraManager.captureSession }

    // MARK: - Private Properties

    private let cameraManager = CameraManager()

    /// The URL of the current video being processed (temporary)
    private var currentVideoURL: URL?

    /// Suffix for both saved video and result
    private var fileNameSuffix: String?

    /// Timestamp for the start
    private var recordingStartTime: CMTime?

    /// The algorithm and ml results for the video
    private var result: [FrameResult]?

    /// Number of frames currently waiting to get processed
    private var numFrameBehind: Int = 0

    /// Maximum of frames allowed to buffer before droping frames
    private let maxFrameBehind: Int = 6

    /// Tracks the current frame number
    private var frameNum: UInt = 0

    /// Processes each frame through it
    private var frameProcessor: FrameProcessor!

    /// For fps calculation
    private var lastTimestamp: CMTime?

    // MARK: - Initialization

    init() {
        cameraManager.setup()

        self.frameProcessor = FrameProcessor(
            onCross: { AudioServicesPlaySystemSound(1054) },
            perFrame: { result in
                self.numFrameBehind -= 1

                Task { @MainActor in
                    self.overlay = result
                }
            }
        )

        cameraManager.onFrameCaptured = { [weak self] pixelBuffer, currentTime in
            guard let self else { return }

            self.frameNum += 1

            if self.isRecording && self.recordingStartTime == nil {
                self.recordingStartTime = currentTime
            }

            print(String(repeating: "-", count: 50))

            if let last = self.lastTimestamp {
                let delta = CMTimeGetSeconds(currentTime - last)
                let actualFPS = 1.0 / delta
                print("Actual FPS: \(actualFPS)")
            }

            self.lastTimestamp = currentTime

            guard self.numFrameBehind < self.maxFrameBehind else {
                print("Skipped! Frame: \(self.frameNum)")
                return
            }

            print("Currently \(self.numFrameBehind) frames behind")
            print("Processing Frame: \(self.frameNum)")

            self.numFrameBehind += 1
            self.frameProcessor.processFrame(pixelBuffer, time: currentTime)
        }

        cameraManager.onFrameDropped = { [weak self] currentTime in
            guard let self else { return }
            self.frameNum += 1
            print("Avfundation Dropped frame: \(self.frameNum) automatically!")
            print("Currently \(self.numFrameBehind) frames behind")

            if self.isRecording && self.recordingStartTime == nil {
                self.recordingStartTime = currentTime
            }
        }

        cameraManager.onRecordingFinished = { [weak self] url, error in
            guard let self else { return }
            if let error = error {
                print("Recording error: \(error.localizedDescription)")
                self.currentVideoURL = nil
            } else {
                print("Recording completed! Save or discard?")
                self.showSaveConfirmation = true
            }
        }

        cameraManager.onVideoSavedToPhotos = { error in
            if let error = error {
                print("Error: Failed to save video: \(error.localizedDescription)")
            } else {
                print("Video saved to Photos!")
            }
        }
    }

    deinit {
        cameraManager.stop()
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

    func toggleHandedness() {
        guard !isRecording else {
            print("Handedness change not allowed after recording started!")
            return
        }

        if handedness == .left {
            handedness = .right
        } else {
            handedness = .left
        }
    }

    /// Saves the pending video to Photos library (called when user confirms)
    func saveVideoToPhotos() {
        guard let videoURL = currentVideoURL else { return }
        cameraManager.saveVideoToPhotos(videoURL)
        currentVideoURL = nil
        showSaveConfirmation = false
    }

    /// Discards the pending video (called when user declines)
    func discardVideo() {
        guard let videoURL = currentVideoURL else { return }

        try? FileManager.default.removeItem(at: videoURL)

        Task { @MainActor in
            print("Video discarded")
            self.currentVideoURL = nil
            self.showSaveConfirmation = false
        }
    }

    /// Save the algorithm and ML results to disk
    func saveResults() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        guard let fileNameSuffix = fileNameSuffix else { fatalError() }
        let saveURL = url.appendingPathComponent("CMORE_Results_\(fileNameSuffix).json")

        let encoder = JSONEncoder()

        guard let result = result, let recordingStartTime = recordingStartTime else { fatalError("no result ready to save!") }

        do {
            let data = try encoder.encode(result.map {
                var tmp = $0
                tmp.presentationTime = tmp.presentationTime - recordingStartTime
                return tmp
            })
            try data.write(to: saveURL)
            print("Results saved to: \(saveURL)")
        } catch {
            print("Error saving results: \(error)")
        }

        self.fileNameSuffix = nil
        self.recordingStartTime = nil
    }

    func discardResults() {
        result = nil
        fileNameSuffix = nil
    }

    /// Starts the camera feed
    func startCamera() async {
        await cameraManager.start()
    }

    // MARK: - Private Methods

    /// Starts video recording to a file
    private func startRecording() {
        guard !isRecording, overlay != nil, overlay?.boxDetection != nil else { return }

        isRecording = true

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let suffix = Date().timeIntervalSince1970

        let videoFileName = "CMORE_Recording_\(suffix).mov"
        fileNameSuffix = String(suffix)
        let outputURL = documentsPath.appendingPathComponent(videoFileName)

        currentVideoURL = outputURL

        cameraManager.startRecording(to: outputURL)

        Task {
            await frameProcessor.startCountingBlocks(for: handedness, box: (overlay?.boxDetection)!)
        }
    }

    /// Stops video recording
    private func stopRecording() {
        guard isRecording else { return }

        isRecording = false

        Task {
            result = await frameProcessor.stopCountingBlocks()
        }

        cameraManager.stopRecording()
    }
}
