//
//  FrameProcessor.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/20/25.
//

import Foundation
import CoreImage
import Vision
import simd

// MARK: - error types
fileprivate enum FrameProcessorError: Error {
    case handBoxProjectionFailed
}

// MARK: - constants safe to parallel
fileprivate let handsRequest = DetectHumanHandPoseRequest()
fileprivate let facesRequest = DetectFaceRectanglesRequest()
fileprivate let blockDetector = BlockDetector()
fileprivate let boxRequest = BoxDetector.createBoxDetectionRequest()

/// Detected and filter out the wrong hand by handedness, nil handedness are kepts
fileprivate func detectnFilterHands(in image: CIImage, _ handedness: HumanHandPoseObservation.Chirality) async -> [HumanHandPoseObservation]? {
    guard let allHands = try? await handsRequest.perform(on: image) else {
        return nil
    }
    let hands = allHands.filter { hand in
        return hand.chirality == nil || hand.chirality == handedness
    }
    guard !hands.isEmpty else {
        return nil
    }
    return hands
}

// MARK: - Pure functions

/// Returns true if the block is above the wrist and on the right side of left hand (vice versa)
fileprivate func isInvalidBlock(_ block: RecognizedObjectObservation, _ roi: NormalizedRect, basedOn hand: HumanHandPoseObservation?, _ handedness: HumanHandPoseObservation.Chirality) -> Bool {
    guard let hand = hand else {
        return false
    }
    
    // invalid - above the center and right of the right hand box
    let blockPixel = block.boundingBox.toImageCoordinates(from: roi, imageSize: CameraSettings.resolution)
    
    let handBBoxPixel = hand.boundingBox.toImageCoordinates(CameraSettings.resolution)
    
    if blockPixel.midY < handBBoxPixel.midY {
        return false
    }
    
    if handedness == .left {
        return blockPixel.midX > handBBoxPixel.midX
    } else {
        return blockPixel.midX < handBBoxPixel.midX
    }
}

/// Linear projection of the hand box
fileprivate func projectHandBox(past: (newer: FrameResult, older: FrameResult), now currentTime: CMTime) throws -> CGRect {
    var newerBox = past.newer.hands!.first!.boundingBox.toImageCoordinates(CameraSettings.resolution)
    let olderBox = past.older.hands!.first!.boundingBox.toImageCoordinates(CameraSettings.resolution)
    let deltaTime = (past.newer.presentationTime - past.older.presentationTime)
    
    guard deltaTime < FrameProcessingThresholds.maxProjectionInterval else {
        print("Fail to project hand box: time interval too large")
        throw FrameProcessorError.handBoxProjectionFailed
    }
    

    let deltaX = newerBox.origin.x - olderBox.origin.x
    let deltaY = newerBox.origin.y - olderBox.origin.y
    
    // project the new origin
    newerBox.origin.x += deltaX / deltaTime.seconds * (currentTime - past.newer.presentationTime).seconds
    newerBox.origin.y += deltaY / deltaTime.seconds * (currentTime - past.newer.presentationTime).seconds
    
    return newerBox
}

fileprivate func defineBloackROI(by hands: [HumanHandPoseObservation], _ results: [FrameResult], _ timestamp: CMTime, _ currentBox: BoxDetection, _ handedness: HumanHandPoseObservation.Chirality) -> NormalizedRect? {
    
    /// Calculate the region of interest for block detection
    /// Define ROI by hand
    func expandHandBox(by handBox: CGRect, _ blockSize: CGFloat, _ chirality: HumanHandPoseObservation.Chirality) -> NormalizedRect {
        var roi = handBox
        
        roi.origin.y -=  blockSize * FrameProcessingThresholds.handBoxExpansionMultiplier
        roi.size.width += blockSize * FrameProcessingThresholds.handBoxExpansionMultiplier
        roi.size.height += blockSize * FrameProcessingThresholds.handBoxExpansionMultiplier
        
        if chirality == .left {
            roi.origin.x -= blockSize * FrameProcessingThresholds.handBoxExpansionMultiplier
        }
        
        // right hand don't move the origin.x but extend the width
        
        return NormalizedRect(imageRect: roi, in: CameraSettings.resolution)
    }
    
    var roi: NormalizedRect
    
    if hands.isEmpty {
        let last2Hands = results
            .lazy 
            .filter { $0.hands != nil && $0.hands!.count > 0 }
            .suffix(2)
        
        guard last2Hands.count == 2 else {
            return nil
        }
        
        let handBox = try? projectHandBox(past: (last2Hands.last!, last2Hands.first!), now: timestamp)
        guard let handBox = handBox else { return nil }
        
        roi = expandHandBox(by: handBox, CGFloat(blockLengthInPixels(scale: currentBox.cmPerPixel)), handedness)
        
    } else {
        
        roi = expandHandBox(by: hands.first!.boundingBox.toImageCoordinates(CameraSettings.resolution), CGFloat(blockLengthInPixels(scale: currentBox.cmPerPixel)), handedness)
        
    }
    
    return roi
}


/// Calculate the running average of past block bounding box centers
fileprivate func runningAverage(_ detections: [BlockDetection]) -> CGPoint? {
    var totalX: CGFloat = 0
    var totalY: CGFloat = 0
    var count: CGFloat = 0

    for detection in detections {
        // Iterate only if objects exist
        guard let objects = detection.objects else { continue }
        
        for object in objects {
            let block = object.boundingBox.toImageCoordinates(from: detection.ROI, imageSize: CameraSettings.resolution)
            totalX += block.midX
            totalY += block.midY
            count += 1
        }
    }

    // Avoid division by zero
    guard count > 0 else { return nil }

    return CGPoint(x: totalX / count, y: totalY / count)
}

fileprivate func scaleROIcenter(_ center: CGPoint, blockSize: Double) -> NormalizedRect {
    return NormalizedRect(
        imageRect: CGRect(
            x: center.x - FrameProcessingThresholds.blockCenterROIMultiplier * blockSize,
            y: center.y - FrameProcessingThresholds.blockCenterROIMultiplier * blockSize,
            width: 2 * FrameProcessingThresholds.blockCenterROIMultiplier * blockSize,
            height: 2 * FrameProcessingThresholds.blockCenterROIMultiplier * blockSize
        ),
        in: CameraSettings.resolution)
}

// MARK: - Frame Processor
actor FrameProcessor {

    // MARK: - Callbacks

    nonisolated let onCrossed: () -> Void
    nonisolated let partialResult: (FrameResult) -> Void
    nonisolated let fullResult: (FrameResult) -> Void

    // MARK: - Stateful properties

    public private(set) var countingBlocks = false
    public private(set) var blockCounts = 0

    private var boxLastUpdated: CMTime = .zero
    private var results: [FrameResult] = []

    /// Single persistent stream consumer — never cancelled/restarted
    private var mainTask: Task<Void, Never>?

    /// Counting pipeline tasks
    private var processingTask: Task<Void, Never>?

    /// Feeds frames into the counting pipeline when countingBlocks == true
    private var resultContinuation: AsyncStream<(Int, FrameResult, CIImage)>.Continuation?

    /// Used for reordering the results
    private var currentIndex: Int = 0

    private var currentBox: BoxDetection?
    private var currentState: BlockCountingState = .free
    private var handedness: HumanHandPoseObservation.Chirality = .right

    // MARK: - Computed properties

    private var blockSize: Double {
        guard let box = currentBox else { fatalError("No box exist!") }
        return blockLengthInPixels(scale: box.cmPerPixel)
    }

    private var pastBlockCenters: [CGPoint] {
        guard let recentDetection = results.suffix(FrameProcessingThresholds.recentFrameLookback).last(where: {
            !$0.blockDetections.isEmpty &&
            !$0.blockDetections.compactMap { $0.objects }.isEmpty
        }) else { return [] }

        let minDistanceSq = (2*blockSize) * (2*blockSize)

        return recentDetection.blockDetections.reduce(into: [CGPoint]()) { points, detection in
            guard let blocks = detection.objects else { return }

            for block in blocks {
                let rect = block.boundingBox.toImageCoordinates(
                    from: detection.ROI,
                    imageSize: CameraSettings.resolution
                )
                let candidate = CGPoint(x: rect.midX, y: rect.midY)
                let candidateVec = SIMD2<Double>(x: candidate.x, y: candidate.y)

                let isTooClose = points.contains { existingPoint in
                    let existingVec = SIMD2<Double>(x: existingPoint.x, y: existingPoint.y)
                    return simd_distance_squared(candidateVec, existingVec) < minDistanceSq
                }

                if !isTooClose {
                    points.append(candidate)
                }
            }
        }
    }

    // MARK: - Public Methods

    init(
        onCross: @escaping () -> Void = {},
        partialResult: @escaping (FrameResult) -> Void = {_ in },
        fullResult: @escaping (FrameResult) -> Void = { _ in }
    ) {
        self.onCrossed = onCross
        self.partialResult = partialResult
        self.fullResult = fullResult
    }

    /// Start consuming the camera frame stream. A single for-await loop runs for the
    /// stream's entire lifetime, dispatching frames based on the current mode.
    func startProcessing(stream: AsyncStream<(CIImage, CMTime)>) {
        mainTask = Task { [weak self] in
            
            let maxConcurrentTasks = FrameProcessingThresholds.maxConcurrentTasks
            await withTaskGroup(of: Void.self) { group in
                var activeTasks = 0
                
                for await (image, timestamp) in stream {
                    guard let self, !Task.isCancelled else { break }
                    
                    if activeTasks >= maxConcurrentTasks {
                        await group.next()
                        activeTasks -= 1
                    }

                    if await self.countingBlocks {
                        let index = await self.currentIndex
                        await self.incrementIdx()
                        
                        group.addTask {
                            var partialResults = FrameResult(presentationTime: timestamp, state: .free, boxDetection: await self.currentBox)
                            let currentHandedness = await self.handedness
                            
                            partialResults.hands = await detectnFilterHands(in: image, currentHandedness)
                            self.partialResult(partialResults)
                            await self.resultContinuation?.yield((index, partialResults, image))
                        }
                    } else {
                        // Pre-counting: box detection for overlay
                        group.addTask {
                            var boxDetected: BoxDetection?
                            if let boxRequestResult = try? await boxRequest.perform(on: image) as? [CoreMLFeatureValueObservation],
                               let outputArray = boxRequestResult.first?.featureValue.shapedArrayValue(of: Float.self) {
                                boxDetected = BoxDetector.processKeypointOutput(outputArray)
                            }

                            let result = FrameResult(
                                presentationTime: timestamp,
                                boxDetection: boxDetected
                            )
                            self.partialResult(result)
                            self.fullResult(result)
                        }
                    }
                    activeTasks += 1
                }
            }
        }
    }
    
    func incrementIdx() {
        currentIndex += 1
    }

    func startCountingBlocks(for handedness: HumanHandPoseObservation.Chirality, box: BoxDetection) {
        self.handedness = handedness
        self.countingBlocks = true
        self.currentBox = box
        self.currentIndex = 0

        // Create reordering stream
        let (stream, continuation) = AsyncStream.makeStream(
            of: (Int, FrameResult, CIImage).self,
            bufferingPolicy: .unbounded
        )
        
        self.resultContinuation = continuation

        // Serial consumer: state machine processing
        processingTask = Task { [weak self] in
            guard let self else { return }

            var buffer = [Int: (FrameResult, CIImage)]()
            var nextIndex: Int = 0

            for await (finishedIndex, result, image) in stream {
                buffer[finishedIndex] = (result, image)
                while let (nextResult, frame) = buffer.removeValue(forKey: nextIndex) {

                    var nextResult = nextResult
                    let timestamp = nextResult.presentationTime
                    let hands = nextResult.hands ?? []
                    let currentBox = nextResult.boxDetection!
                    async let currentState = self.currentState
                    async let results = self.results
                    let blockSize = await self.blockSize
                    let pastBlockCenters = await self.pastBlockCenters

                    var blockROIs: [NormalizedRect] = []
                    switch await currentState {
                    case .crossed:
                        if let handROI = defineBloackROI(by: hands, await results, timestamp, currentBox, handedness) {
                            blockROIs.append(handROI)

                            blockROIs.append(contentsOf: pastBlockCenters.reduce(into: []) { result, blockCenter in
                                let candidateROI = scaleROIcenter(blockCenter, blockSize: blockSize)

                                if candidateROI.percentCovered(by: handROI) < FrameProcessingThresholds.roiOverlapThreshold {
                                    result.append(candidateROI)
                                }
                            })
                        }

                    case .detecting:
                        if let roi = defineBloackROI(by: hands, await results, timestamp, currentBox, handedness) {
                            blockROIs.append(roi)
                        }

                    case .crossedBack:
                        blockROIs.append(contentsOf: pastBlockCenters.map { center in
                            return scaleROIcenter(center, blockSize: blockSize)
                        })

                    default:
                        break
                    }

                    var blockDetections: [BlockDetection] = []
                    for await blockDetection in blockDetector.perforAll(on: frame, in: blockROIs) {
                        var allBlocks = blockDetection
                        if var objects = allBlocks.objects {
                            objects.removeAll { block in
                                isInvalidBlock(block, allBlocks.ROI, basedOn: hands.first, handedness) ||
                                block.confidence < FrameProcessingThresholds.blockConfidenceThreshold
                            }
                            allBlocks.objects = objects
                        }
                        blockDetections.append(allBlocks)
                    }
                    let nextState = await currentState.transition(by: hands, currentBox, blockDetections)

                    await self.updateState(nextState)
                    nextResult.blockTransfered = await self.blockCounts

                    nextResult.state = nextState
                    nextResult.blockDetections = blockDetections
                    self.fullResult(nextResult)
                    await appendResult(nextResult)

                    nextIndex += 1
                }
            }
        }
    }

    func stopCountingBlocks() async -> [FrameResult] {
        // Finish the internal counting stream
        resultContinuation?.finish()
        resultContinuation = nil

        // Wait for pipeline to drain
        await processingTask?.value

        processingTask = nil

        let resultsToReturn = results

        // Reset state — mainTask automatically resumes pre-counting mode
        countingBlocks = false
        results.removeAll()
        currentBox = nil
        currentState = .free
        blockCounts = 0

        return resultsToReturn
    }

    // MARK: - Private functions

    private func updateState(_ newState: BlockCountingState) {
        if newState == .crossed && self.currentState != .crossed {
            onCrossed()
        } else if (currentState == .crossed && newState == .released) ||
                    (currentState == .crossedBack && newState == .released) {
            blockCounts += 1
        }
        currentState = newState
    }

    private func updateBox(from box: BoxDetection, at time: CMTime) {
        if boxLastUpdated < time {
            currentBox = box
        }
    }

    private func appendResult(_ result: FrameResult) {
        results.append(result)
    }
}

