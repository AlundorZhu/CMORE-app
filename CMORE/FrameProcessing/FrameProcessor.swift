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

    nonisolated let onCrossed: (() -> Void)! // For sound playing

    nonisolated let perFrame: ((FrameResult) -> Void)! // Visualize the frame count and decrement the count to receive new frame

    // MARK: - Stateful properties

    public private(set) var countingBlocks = false

    public private(set) var blockCounts = 0

    private var boxLastUpdated: CMTime = .zero

    private var results: [FrameResult] = []

    private var processingTask: Task<Void, Never>?

    private var producerTask: Task<Void, Never>?

    private var preCountingTask: Task<Void, Never>?

    private var currentBox: BoxDetection?

    private var currentState: BlockCountingState = .free

    private var handedness: HumanHandPoseObservation.Chirality = .right // none nil default

    /// The camera frame stream from CameraManager
    private var stream: AsyncStream<(CIImage, CMTime)>?

    // MARK: - computed properties

    private var blockSize: Double {
        guard let box = currentBox else { fatalError("No box exist!") }
        return blockLengthInPixels(scale: box.cmPerPixel)
    }

    // Return ROIs centered on past blocks
    private var pastBlockCenters: [CGPoint] {

        // look in the last # frames to find one where we detected some blocks
        guard let recentDetection = results.suffix(FrameProcessingThresholds.recentFrameLookback).last(where: {
            !$0.blockDetections.isEmpty &&
            !$0.blockDetections.compactMap { $0.objects }.isEmpty
        }) else { return [] }

        let minDistanceSq = (2*blockSize) * (2*blockSize)

        return recentDetection.blockDetections.reduce(into: [CGPoint]()) { points, detection in
            // Handle the optional 'objects' array safely using simple coalescence
            guard let blocks = detection.objects else { return }

            for block in blocks {
                // 1. Calculate the candidate point
                let rect = block.boundingBox.toImageCoordinates(
                    from: detection.ROI,
                    imageSize: CameraSettings.resolution
                )
                let candidate = CGPoint(x: rect.midX, y: rect.midY)
                let candidateVec = SIMD2<Double>(x: candidate.x, y: candidate.y)

                // 2. Check immediately against the points we have accepted SO FAR
                // (No second iteration needed, we check as we build)
                let isTooClose = points.contains { existingPoint in
                    let existingVec = SIMD2<Double>(x: existingPoint.x, y: existingPoint.y)
                    return simd_distance_squared(candidateVec, existingVec) < minDistanceSq
                }

                // 3. Add only if valid
                if !isTooClose {
                    points.append(candidate)
                }
            }
        }
    }

    // MARK: - Public Methods

    init(onCross: @escaping () -> Void, perFrame: @escaping (FrameResult) -> Void) {
        /// When crossing the bivider
        self.onCrossed = onCross
        /// For every frame
        self.perFrame = perFrame
    }

    /// Start consuming the camera frame stream (pre-counting mode: box detection for overlay)
    func startProcessing(stream: AsyncStream<(CIImage, CMTime)>) {
        self.stream = stream
        startPreCountingLoop()
    }

    func startCountingBlocks(for handedness: HumanHandPoseObservation.Chirality, box: BoxDetection) async {
        // Stop pre-counting loop first
        preCountingTask?.cancel()
        await preCountingTask?.value
        preCountingTask = nil

        self.handedness = handedness
        self.countingBlocks = true
        self.currentBox = box

        guard let stream = self.stream else {
            fatalError("No stream available - call startProcessing(stream:) first")
        }

        // Only create the reordering stream
        let (resultStream, resultContinuation) = AsyncStream.makeStream(
            of: (Int, FrameResult, CIImage).self,
            bufferingPolicy: .unbounded
        )

        // Process stream in parallel and produce
        producerTask = Task { [weak self] in
            guard let self else { return }
            
            let maxConcurrentTasks = 1
            await withTaskGroup(of: Void.self) { group in
                var currentIndex = 0
                var activeTasks = 0
                
                for await (image, timestamp) in stream {
                    guard !Task.isCancelled else { break } // get out of the loop
                    
                    if activeTasks >= maxConcurrentTasks {
                        await group.next()
                        activeTasks -= 1
                    }

                    let index = currentIndex
                    currentIndex += 1

                    var partialResult = FrameResult(presentationTime: timestamp, state: .free, boxDetection: box)
                    let currentHandedness = await self.handedness

                    group.addTask {
                        partialResult.hands = await detectnFilterHands(in: image, currentHandedness)
                        self.perFrame(partialResult)
                        resultContinuation.yield((index, partialResult, image))
                    }
                    
                    activeTasks += 1
                }
            }
            resultContinuation.finish()
        }

        // Serial process
        processingTask = Task { [weak self] in
            guard let self else { return }

            var buffer = [Int: (FrameResult, CIImage)]()
            var nextIndex: Int = 0

            for await (finishedIndex, result, image) in resultStream {
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

                    // Define block detection ROI
                    var blockROIs: [NormalizedRect] = []
                    switch await currentState {
                    case .crossed: // look for blocks around the hand plus roi follow block
                        if let handROI = defineBloackROI(by: hands, await results, timestamp, currentBox, handedness) {
                            blockROIs.append(handROI)

                            blockROIs.append(contentsOf: pastBlockCenters.reduce(into: []) { result, blockCenter in
                                let candidateROI = scaleROIcenter(blockCenter, blockSize: blockSize)

                                // don't append the ROI where it's covered by hand already.
                                if candidateROI.percentCovered(by: handROI) < FrameProcessingThresholds.roiOverlapThreshold {
                                    result.append(candidateROI)
                                }
                            })
                        }

                    case .detecting: // look for block around the hand

                        if let roi = defineBloackROI(by: hands, await results, timestamp, currentBox, handedness) {
                            blockROIs.append(roi)
                        }

                    case .crossedBack: // roi follow block

                        blockROIs.append(contentsOf: pastBlockCenters.map { center in
                            return scaleROIcenter(center, blockSize: blockSize)
                        })

                    default:
                        break
                    }

                    // Detect n Process the blocks
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

                    // Save the result
                    nextResult.state = nextState
                    nextResult.blockDetections = blockDetections
                    await appendResult(nextResult)

                    nextIndex += 1
                }
            }
        }
    }

    func stopCountingBlocks() async -> [FrameResult] {
        // Cancel producer to stop accepting new frames
        producerTask?.cancel()

        // Wait for producer to finish (processes remaining in-flight frames)
        await producerTask?.value
        // Wait for serial consumer to finish (processes remaining results)
        await processingTask?.value

        producerTask = nil
        processingTask = nil

        let resultsToReturn = results

        // reset states
        countingBlocks = false
        results.removeAll()
        currentBox = nil
        currentState = .free
        blockCounts = 0

        // Restart pre-counting loop
        startPreCountingLoop()

        return resultsToReturn
    }

    // MARK: - Private functions

    private func startPreCountingLoop() {
        guard let stream = self.stream else { return }
        preCountingTask = Task { [weak self] in
            for await (image, timestamp) in stream {
                guard let self, !Task.isCancelled else { break }

                Task {
                    // Box detection for overlay
                    var boxDetected: BoxDetection?
                    if let boxRequestResult = try? await boxRequest.perform(on: image) as? [CoreMLFeatureValueObservation],
                       let outputArray = boxRequestResult.first?.featureValue.shapedArrayValue(of: Float.self) {
                        boxDetected = BoxDetector.processKeypointOutput(outputArray)
                    }

                    self.perFrame(FrameResult(
                        presentationTime: timestamp,
                        boxDetection: boxDetected
                    ))
                }
            }
        }
    }

    private func updateState(_ newState: BlockCountingState) {
        if newState == .crossed && self.currentState != .crossed {
            onCrossed()
        }else if (currentState == .crossed && newState == .released) ||
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

