//
//  VideoProcessingViewModel.swift
//  CMORE
//

import Vision
import AVFoundation
import UIKit

class VideoProcessingViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var overlay: FrameResult?
    @Published var currentFrame: UIImage?
    @Published var handedness: HumanHandPoseObservation.Chirality = .right
    @Published var isProcessing = false
    @Published var isDone = false

    // MARK: - Private Properties

    private var frameProcessor: FrameProcessor!
    private var extractor: VideoFrameExtractor?
    private var videoURL: URL?

    /// The single stream continuation that lives across both phases
    private var continuation: AsyncStream<(CIImage, CMTime)>.Continuation?

    private enum Phase { case scanning, counting }
    private var phase: Phase = .scanning

    private let ciContext = CIContext()

    // MARK: - Initialization

    init() {
        self.frameProcessor = FrameProcessor(
            onCross: { /* no sound during video processing */ },
            partialResult: { [weak self] result in
                guard let self else { return }

                Task { @MainActor in
                    self.overlay = result
                }

                // Each processed frame triggers the next one
                self.onFrameProcessed(result)
            }
        )
    }

    // MARK: - Public Methods

    func loadVideo(url: URL) {
        self.videoURL = url
        self.extractor = VideoFrameExtractor(url: url)
    }

    /// Starts the two-phase processing with a single persistent stream.
    func startProcessing() async {
        guard let extractor else { return }

        await MainActor.run { isProcessing = true }

        do {
            try await extractor.prepare()
        } catch {
            print("Failed to prepare video: \(error)")
            await MainActor.run { isProcessing = false; isDone = true }
            return
        }

        // Create the single stream that spans both phases
        let (stream, continuation) = AsyncStream.makeStream(of: (CIImage, CMTime).self)
        self.continuation = continuation

        phase = .scanning

        // Start FrameProcessor consuming the stream (runs until continuation.finish())
        await frameProcessor.startProcessing(stream: stream)

        // Yield the first frame to kick things off
        yieldNextFrame()
    }

    // MARK: - Private Methods

    /// Called by perFrame callback after each frame is processed.
    /// Decides what to do next based on the current phase.
    private func onFrameProcessed(_ result: FrameResult) {
        switch phase {
        case .scanning:
            if let box = result.boxDetection {
                // Box found! Rewind and switch to counting
                Task { [weak self] in
                    await self?.transitionToCounting(box: box)
                }
            } else {
                yieldNextFrame()
            }

        case .counting:
            yieldNextFrame()
        }
    }

    /// Rewinds the video and switches to counting mode.
    private func transitionToCounting(box: BoxDetection) async {
        guard let extractor else { return }

        do {
            try await extractor.rewind()
        } catch {
            print("Failed to rewind video: \(error)")
            continuation?.finish()
            return
        }

        phase = .counting
        await frameProcessor.startCountingBlocks(for: handedness, box: box)

        // Yield the first counting frame
        yieldNextFrame()
    }

    /// Pulls the next frame from the extractor and yields it into the stream.
    /// If no more frames, finishes the stream and wraps up.
    private func yieldNextFrame() {
        guard let extractor else { return }

        if let (image, timestamp) = extractor.nextFrame() {
            // Render frame for display
            let uiImage = renderFrame(image)
            Task { @MainActor [weak self] in
                self?.currentFrame = uiImage
            }

            continuation?.yield((image, timestamp))
        } else {
            // End of video
            finishProcessing()
        }
    }

    /// Called when the video ends. Finishes the stream and saves results.
    private func finishProcessing() {
        continuation?.finish()
        continuation = nil

        Task { [weak self] in
            guard let self else { return }

            if self.phase == .counting {
                // Wait briefly for FrameProcessor to drain in-flight tasks
                try? await Task.sleep(for: .milliseconds(500))

                let results = await self.frameProcessor.stopCountingBlocks()
                self.saveSession(results: results)
            }

            await MainActor.run {
                self.isProcessing = false
                self.isDone = true
            }
        }
    }

    private func renderFrame(_ ciImage: CIImage) -> UIImage? {
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func saveSession(results: [FrameResult]) {
        guard let videoURL else { return }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let suffix = Date().timeIntervalSince1970
        let resultsFileName = "CMORE_Results_\(suffix).json"
        let resultsURL = documentsDir.appendingPathComponent(resultsFileName)

        // Copy video to documents directory
        let videoFileName = "CMORE_Import_\(suffix).mov"
        let videoDestURL = documentsDir.appendingPathComponent(videoFileName)

        do {
            try FileManager.default.copyItem(at: videoURL, to: videoDestURL)
        } catch {
            print("Error copying video: \(error)")
        }

        do {
            let data = try JSONEncoder().encode(results)
            try data.write(to: resultsURL)
        } catch {
            print("Error saving results: \(error)")
        }

        let blockCount = results.compactMap(\.blockTransfered).max() ?? 0

        let session = Session(
            id: UUID(),
            date: Date(),
            blockCount: blockCount,
            videoFileName: videoFileName,
            resultsFileName: resultsFileName
        )
        SessionStore.shared.add(session)
    }
}
