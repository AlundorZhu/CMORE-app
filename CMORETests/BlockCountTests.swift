//
//  BlockCountTests.swift
//  CMORETests
//

import Testing
import CoreImage
import CoreML
import Vision
import AVFoundation
@testable import CMORE

// Bundle anchor for locating test resources
private class TestBundleAnchor {}

struct BlockCountTests {
    enum TestError: Error {
        case resourceNotFound(String)
    }

    // MARK: - Helpers

    /// Locates the test video in the test bundle.
    private func testVideoURL() throws -> URL {
        let bundle = Bundle(for: TestBundleAnchor.self)
        guard let url = bundle.url(
            forResource: "CMORE_Recording_1771377474.842218",
            withExtension: "MOV"
        ) else {
            throw TestError.resourceNotFound("CMORE_Recording_1771377474.842218.MOV not found in test bundle")
        }
        return url
    }

    // MARK: - Tests

    @Test("Video file meets minimum requirements")
    func videoValidation() async throws {
        let url = try testVideoURL()
        let extractor = VideoFrameExtractor(url: url)
        let validationError = await extractor.validate()
        #expect(validationError == nil, "Video should be valid but got: \(validationError ?? "")")
    }

    @Test("End-to-end block counting produces correct count",
          .timeLimit(.minutes(10)))
    func endToEndBlockCounting() async throws {
        let url = try testVideoURL()
        let expectedCount = 14

        let vm = VideoProcessingViewModel()
        vm.loadVideo(url: url)
        await vm.startProcessing()

        // Wait for processing to complete
        while !vm.isDone {
            try await Task.sleep(for: .milliseconds(100))
        }

        // Read the block count from the last saved session
        let sessions = SessionStore.shared.loadAll()
        let lastSession = try #require(sessions.last, "Should have saved a session")
        let blockCount = lastSession.blockCount

        print("Block count result: \(blockCount) (expected: \(expectedCount))")
        #expect(blockCount == expectedCount,
                "Expected \(expectedCount) blocks but counted \(blockCount)")

        // Clean up: remove the session created by the test
        SessionStore.shared.delete(lastSession)
    }
}
