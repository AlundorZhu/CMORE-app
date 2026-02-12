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

extension HumanHandPoseObservation {
    var fingerTips: [Joint] {
        [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
            .compactMap { joint(for: $0) }
    }
}

extension NormalizedRect {
    func percentCovered(by other: NormalizedRect) -> CGFloat {
        // 1. Calculate Intersection (same as above)
        let x1 = max(self.origin.x, other.origin.x)
        let y1 = max(self.origin.y, other.origin.y)
        let x2 = min(self.origin.x + self.width, other.origin.x + other.width)
        let y2 = min(self.origin.y + self.height, other.origin.y + other.height)
        
        let intersectionArea = max(0, x2 - x1) * max(0, y2 - y1)
        
        // 2. Calculate Self Area
        let selfArea = self.width * self.height
        
        // 3. Return Percentage
        return selfArea > 0 ? intersectionArea / selfArea : 0.0
    }
}

extension Array where Element: Comparable {
    mutating func insertSorted(_ element: Element) {

        if let last = self.last, element >= last {
            self.append(element)
            return
        }
        
        // Binary search for the correct insertion index
        var low = 0
        var high = self.count
        while low < high {
            let mid = low + (high - low) / 2
            if self[mid] < element {
                low = mid + 1
            } else {
                high = mid
            }
        }
        self.insert(element, at: low)
    }
}

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
/// Returns true if any joints if above the horizon. Assume y increase upwards
fileprivate func isAbove(of horizon: Float, _ keypoints: [Joint]) -> Bool {
    for joint in keypoints {
        if Float(joint.location.y * CameraSettings.resolution.height) > horizon {
            return true
        }
    }
    return false
}

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
    
    guard deltaTime < CMTime(value: 1, timescale: 2) else { // make sure results are not more than half seconds apart
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
        
        roi.origin.y -=  blockSize * 2
        roi.size.width += blockSize * 2
        roi.size.height += blockSize * 2
        
        if chirality == .left {
            roi.origin.x -= blockSize * 2
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

/// Returns true if any fingertip crosses the divider polyline.
/// - Parameters:
///   - divider: Tuple of three points (front/top, front/middle, back/top) as [x, y] in image space.
///   - keypoints: Hand joints to test.
fileprivate func isCrossed(divider: (Keypoint, Keypoint, Keypoint), _ joints: [Joint], handedness: HumanHandPoseObservation.Chirality) -> Bool {
    let (frontTop, frontMiddle, backTop) = divider

    // Compute the divider's x-position for a given y by clamping to the end points
    // and linearly interpolating between them.
    func dividerX(at y: Float) -> Float {
        let start: SIMD2<Float>
        let end: SIMD2<Float>
        
        if y <= frontTop.position.y {
            // Case A: Top Section
            start = frontTop.position
            end = frontMiddle.position
        }
        else if y >= backTop.position.y {
            // Case B: Bottom Section (Parallel Projection)
            // Vector Math: Calculate direction (B - A) and add to C
            // No manual loops needed; SIMD handles the subtraction/addition.
            let direction = frontMiddle.position - frontTop.position
            
            start = backTop.position
            end = backTop.position + direction
        }
        else {
            // Case C: Middle Section
            start = frontTop.position
            end = backTop.position
        }
        
        // 2. Solve for X
        // Calculate vertical progress 't' (0.0 to 1.0)
        let dy = end.y - start.y
        
        // Safety: Avoid division by zero
        guard abs(dy) > .leastNormalMagnitude else { return start.x }
        
        let t = (y - start.y) / dy
        
        // 3. Built-in Interpolation
        // simd_mix(a, b, t) is the hardware-optimized version of "a + (b - a) * t"
        return simd_mix(start.x, end.x, t)
    }

    return joints.contains { joint in
        let x = Float(joint.location.x * CameraSettings.resolution.width)
        let y = Float(joint.location.y * CameraSettings.resolution.height)
        switch handedness {
            case .left:
                return x < dividerX(at: y)
            case .right:
                return x > dividerX(at: y)
            @unknown default:
                fatalError("Unknown handedness")
        }
    }
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
            x: center.x - 2 * blockSize,
            y: center.y - 2 * blockSize,
            width: 4 * blockSize,
            height: 4 * blockSize
        ),
        in: CameraSettings.resolution)
}

fileprivate func isBlockApart(from hand: HumanHandPoseObservation, distanceThreshold: Double, _ blockCenters: [SIMD2<Double>]) -> Bool {
    
    guard !blockCenters.isEmpty else { return false }
    
    let fingerTips = hand.fingerTips.map { joint in
        SIMD2<Double>(
            x: joint.location.x * CameraSettings.resolution.width,
            y: joint.location.y * CameraSettings.resolution.height
        )
    }

    let thresholdSquared = distanceThreshold * distanceThreshold

    
    for blockCenter in blockCenters {
        // Returns .released ONLY if EVERY fingertip is further than the threshold
        if fingerTips.allSatisfy({ simd_distance_squared($0, blockCenter) > thresholdSquared }) {
            return true
        }
    }
    return false
}

// MARK: - Frame Processor
actor FrameProcessor {
    
    nonisolated let onCrossed: () -> Void // For sound playing
    
    nonisolated let perFrame: (FrameResult) -> Void // Visualize the frame count and decrement the count to receive new frame
    
    enum State: String, Codable {
        case free
        case detecting
        case crossed
        case crossedBack
        case released
        
        func transition(by hands: [HumanHandPoseObservation], _ box: BoxDetection, _ blockDetections: [BlockDetection]) -> State {
            guard let hand = hands.first else {
                return self
            }
            
            /// In frame coordinates
            var blockCenters: [SIMD2<Double>] {
                var result: [SIMD2<Double>] = []
                for detection in blockDetections {
                    let roi = detection.ROI
                    
                    guard let blocks = detection.objects else {
                        continue
                    }
                    
                    for block in blocks {
                        result.append(SIMD2<Double>(
                            x: block.boundingBox.toImageCoordinates(from: roi, imageSize: CameraSettings.resolution).midX,
                            y: block.boundingBox.toImageCoordinates(from: roi, imageSize: CameraSettings.resolution).midY
                        ))
                    }
                }
                return result
            }
            
            switch self {
            case .free: /// free -> detecting
                if isAbove(of: box["Front divider top"].position.y, hand.fingerTips) &&
                    !isCrossed(divider:(box["Front divider top"], box["Front top middle"], box["Back divider top"]), hand.fingerTips, handedness: hand.chirality!) {
                    return .detecting
                }
            case .released:
                /// released -> free
                if !isAbove(of: max(box["Back top left"].position.y, box["Back top right"].position.y), hand.fingerTips) &&
                    !isCrossed(divider:(box["Front divider top"], box["Front top middle"], box["Back divider top"]), hand.fingerTips, handedness: hand.chirality!) {
                    return .free
                }
            case .crossedBack:
                /// crossed back -> block released
                if isBlockApart(from: hand, distanceThreshold: 2 * blockLengthInPixels(scale: box.cmPerPixel), blockCenters) {
                    return .released
                }
                
                /// crossed back -> free
                if !isAbove(of: max(box["Back top left"].position.y, box["Back top right"].position.y), hand.fingerTips) {
                    return .free
                }
                /// crossed back -> crossed
                if isCrossed(divider:(box["Front divider top"], box["Front top middle"], box["Back divider top"]), hand.fingerTips, handedness: hand.chirality!) {
                    return.crossed
                }
                
            case .detecting:
                /// detecting -> free
                if !isAbove(of: max(box["Back top left"].position.y, box["Back top right"].position.y), hand.fingerTips) &&
                    !isCrossed(divider:(box["Front divider top"], box["Front top middle"], box["Back divider top"]), hand.fingerTips, handedness: hand.chirality!) {
                    return .free
                }
                /// detecting -> crossed
                if isCrossed(divider:(box["Front divider top"], box["Front top middle"], box["Back divider top"]), hand.fingerTips, handedness: hand.chirality!) {
                    return .crossed
                }
            case .crossed:
                /// crossed -> block released
                if isBlockApart(from: hand, distanceThreshold: 1.5 * blockLengthInPixels(scale: box.cmPerPixel), blockCenters) {
                    return .released
                }
                
                /// crossed -> crossed back
                if !isCrossed(divider:(box["Front divider top"], box["Front top middle"], box["Back divider top"]), hand.fingerTips, handedness: hand.chirality!) {
                    return .crossedBack
                }
            }
            return self
        }
    }
    
    // MARK: - Stateful properties
    
    public private(set) var countingBlocks = false
    
    public private(set) var blockCounts = 0
    
    private var boxLastUpdated: CMTime = .zero
    
    private var results: [FrameResult] = []
    
    private var continuation: AsyncStream<(CIImage, CMTime)>.Continuation?
    
    private var frameStream: AsyncStream<(CIImage, CMTime)>?

    private var processingTask: Task<Void, Never>?

    private var currentBox: BoxDetection?
    
    private var currentState: State = .free
    
    private var handedness: HumanHandPoseObservation.Chirality = .right // none nil default
    
    private var lastUpdated: CMTime = .zero
    
    // MARK: - computed properties
    
    private var blockSize: Double {
        guard let box = currentBox else { fatalError("No box exist!") }
        return blockLengthInPixels(scale: box.cmPerPixel)
    }
    
    // Return ROIs centered on past blocks
    private var pastBlockCenters: [CGPoint] {
        
        // look in the last 6 frames to find one where we detected some blocks
        guard let recentDetection = results.suffix(6).last(where: {
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
    
    func startCountingBlocks(for handedness: HumanHandPoseObservation.Chirality, box: BoxDetection) {
        self.handedness = handedness
        self.countingBlocks = true
        self.currentBox = box
        
        // create a stream
        guard frameStream == nil else {
            fatalError("Tried to start a stream when one is already running")
        }
        let stream = AsyncStream<(CIImage, CMTime)>(bufferingPolicy: .bufferingNewest(12)) { continuation in
            self.continuation = continuation
        }
        frameStream = stream
        
        
        processingTask = Task { [weak self] in
            guard let self else { return }
            
            let (resultStream, resultContinuation) = AsyncStream.makeStream(
                of: (Int, FrameResult, CIImage).self,
                bufferingPolicy: .unbounded
            )
            
            
            // Process stream in parallel and produce
            let producerTask = Task {
                await withTaskGroup(of: Void.self) { group in
                    var currentIndex = 0
                    
                    for await (image, timestamp) in stream {
                        let index = currentIndex
                        currentIndex += 1

                        var result = FrameResult(presentationTime: timestamp, state: .free , boxDetection: box)
                        let currentHandedness = await self.handedness

                        group.addTask {
                            result.hands = await detectnFilterHands(in: image, currentHandedness)
                            self.perFrame(result)
                            resultContinuation.yield((index, result, image))
                        }
                    }
                }
                resultContinuation.finish()
            }
            
            // Serial process
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
                                if candidateROI.percentCovered(by: handROI) < 0.8 {
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
                                block.confidence < 0.5
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
            
            
            await producerTask.value
        }
    }
    
    func stopCountingBlocks() async -> [FrameResult] {
        // send the stop signal
        continuation?.finish()
        
        // wait for stream to finish and clean up
        await processingTask?.value
        continuation = nil
        frameStream = nil
        processingTask = nil
        
        let resultsToReturn = results
        
        // reset states
        countingBlocks = false
        results.removeAll()
        currentBox = nil
        currentState = .free
        blockCounts = 0
        
        return resultsToReturn
    }
    
    /// Processes a single frame from the camera or video
    /// The entry point for the processing pipeline.
    /// - Parameters:
    ///     - pixelBuffer: The frame to process
    ///     - timestamp: The presentation time of the frame
    nonisolated func processFrame(_ pixelBuffer: CVImageBuffer, time timestamp: CMTime) {
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        Task {
            // Before the algorithm starts, locate the box
            if await !countingBlocks {
                async let box = try? boxRequest.perform(on: ciImage)
                
                var boxDetected: BoxDetection?
                
                if let boxRequestResult = await box as? [CoreMLFeatureValueObservation],
                   let outputArray = boxRequestResult.first?.featureValue.shapedArrayValue(of: Float.self) {
                    boxDetected = BoxDetector.processKeypointOutput(outputArray)
                }
                
                
                perFrame(FrameResult(
                    presentationTime: timestamp,
                    state: .free,
                    blockTransfered: 0,
                    faces: nil,
                    boxDetection: boxDetected
                ))
                
                return
            }
            
            // else
            // The block counting algorithm
            guard let continuation = await continuation else {
                fatalError("Stream not created!")
            }
            
            continuation.yield((ciImage, timestamp))
        }
    }
    
    // MARK: - Private functions
    
    private func updateState(_ newState: State) {
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

