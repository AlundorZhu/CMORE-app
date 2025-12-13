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
import OrderedCollections

extension HumanHandPoseObservation {
    var fingerTips: [Joint] {
        [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
            .compactMap { joint(for: $0) }
    }
}

// MARK: - Frame Processor
/// Making it an actor so only one frame get processed at a time
/// Handles processing of individual video frames from the camera or video files
/// Processes frames for face detection and can return frames with bounding boxes drawn
actor FrameProcessor {
    
    nonisolated let onCrossed: (() -> Void) // For sound playing
    
    enum State {
        case free
        case detecting
        case crossed
        case crossedBack
    }
    
    public private(set) var countingBlocks = false
    
    private let facesRequest = DetectFaceRectanglesRequest()
    
    private let handsRequest = DetectHumanHandPoseRequest()
    
    private var blocksRequest: CoreMLRequest /// var because the region of interest changes
    
    private lazy var blocksRequestDuplicate: CoreMLRequest = self.blocksRequest /// one ROI follows the hand, another follows the block projectory
    
    private let boxRequest: CoreMLRequest
    
    // MARK: - Stateful properties
    private var results: OrderedDictionary<CMTime, FrameResult> = .init()
    
    private var currentBox: BoxDetection?
    
    private var currentState: State = .free
    
    private var cmPerPixel: Float?
    
    private var handedness: HumanHandPoseObservation.Chirality = .right // none nil default
    
    // MARK: - Public Methods
    
    init(onCross: @escaping () -> Void) {
        
        /// Craft the boxDetection request
        let keypointModelContainer = BoxDetector.createBoxDetector()
        var request = CoreMLRequest(model: keypointModelContainer)
        request.cropAndScaleAction = .scaleToFit
        self.boxRequest = request
        
        /// Craft the blockDetection request
        let blockModelContainer = BlockDetector.createBlockDetector()
        /// Default resize action is scaleToFill
        self.blocksRequest = CoreMLRequest(model: blockModelContainer)
        
        /// When crossing the bivider
        self.onCrossed = onCross
    }
    
    func startCountingBlocks(for handedness: HumanHandPoseObservation.Chirality, box: BoxDetection) {
        self.handedness = handedness
        self.countingBlocks = true
        self.currentBox = box
    }
    
    func stopCountingBlocks() {
        self.countingBlocks = false
    }
    
    /// Processes a single frame from the camera or video
    /// - Parameters:
    ///     - pixelBuffer: The frame to process
    ///     - timestamp: The presentation time of the frame
    func processFrame(_ pixelBuffer: CVImageBuffer, time timestamp: CMTime) async -> FrameResult {
        
        var result = FrameResult(processingState: currentState)
        
        defer { results[timestamp] = result }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        async let faces = try? facesRequest.perform(on: ciImage)
        
        // MARK: - Before the algorithm starts, locate the box
        if !countingBlocks {
            async let box = try? boxRequest.perform(on: ciImage)
            
            var boxDetected: BoxDetection? = nil
            
            if let boxRequestResult = await box as? [CoreMLFeatureValueObservation],
                let outputArray = boxRequestResult.first?.featureValue.shapedArrayValue(of: Float.self) {
                    boxDetected = BoxDetector.processKeypointOutput(outputArray)
                    result.boxDetection = boxDetected
                }
        
            result.faces = await faces
            return result
        }
        
        // MARK: - The block counting algorithm
        guard let currentBox = currentBox else {
            fatalError("Bad Box!")
        }
        result.boxDetection = currentBox
        
        async let hands = try? handsRequest.perform(on: ciImage)
        guard var hands = await hands,
              hands.count > 0 else {
            
            result.faces = await faces
            return result
        }
        result.hands = hands
        
        // MARK: - Filter out the wrong hand
        hands.removeAll { hand in
            return hand.chirality != nil && hand.chirality != handedness
        }
        
        // MARK: - detect the block
        if cmPerPixel == nil {
            cmPerPixel = calculateScaleToCM(currentBox)
        }
        
        switch currentState {
        case .crossed: // look for blocks around the hand plus roi follow block
            
            var roi: NormalizedRect
            
            if hands.isEmpty {
                let last2Hands = results
                    .filter { $1.hands != nil && $1.hands!.count > 0 }
                    .suffix(2)
                
                guard last2Hands.count == 2 else {
                    break
                }
                
                let handBox = projectHandBox(past: last2Hands, now: timestamp)
                roi = defineBlockROI(by: handBox, cmPerPixel: cmPerPixel!, chirality: handedness)
                
            } else {
                
                roi = defineBlockROI(by: hands.first!.boundingBox.toImageCoordinates(CameraSettings.resolution), cmPerPixel: cmPerPixel!, chirality: handedness)
            }
            
            var handROI = BlockDetection(ROI: roi)
            
            blocksRequest.regionOfInterest = handROI.ROI
            
            async let blocksAroundHand = try? blocksRequest.perform(on: ciImage)
            
            var pastBlockDetection: [BlockDetection] = []
            results.filter { $1.blockDetections.count > 0 }.suffix(5).forEach { _, result in
                pastBlockDetection.append(contentsOf: result.blockDetections)
            }
            
            if let hand = hands.first,
                let awayROICenter = runningAverage(pastBlockDetection),
                let awayROI = followBlockROI(roiCenter: awayROICenter, awayFrom: hand) {
                blocksRequestDuplicate.regionOfInterest = awayROI
                let blocksAwayFromHand = try? await blocksRequestDuplicate.perform(on: ciImage)
                if let blocksAwayFromHand = blocksAwayFromHand as? [RecognizedObjectObservation], blocksAwayFromHand.count > 0 {
                    
                    result.blockDetections.append(BlockDetection(
                        ROI: awayROI,
                        objects: blocksAwayFromHand
                    ))
                } else {
                    result.blockDetections.append(BlockDetection(ROI: awayROI))
                }
            }
            
            if let blocks = await blocksAroundHand as? [RecognizedObjectObservation], !blocks.isEmpty {
                handROI.objects = blocks
            }

            result.blockDetections.append(handROI)
            
        case .detecting: // look for block around the hand
            
            var handROI = BlockDetection(ROI: defineBlockROI(by: hands.first!.boundingBox.toImageCoordinates(CameraSettings.resolution), cmPerPixel: cmPerPixel!, chirality: handedness))
            
            blocksRequest.regionOfInterest = handROI.ROI
            
            async let blocksAroundHand = try? blocksRequest.perform(on: ciImage)
            
            if let blocks = await blocksAroundHand as? [RecognizedObjectObservation], !blocks.isEmpty {
                handROI.objects = blocks
            }

            result.blockDetections.append(handROI)
            
        default:
            break
        }
        
        guard !hands.isEmpty else { // state transistion requires hand detected
            result.faces = await faces
            return result
        }
        
        currentState = transition(by: hands.first!)
        
        print("\(currentState)")
        
        result.faces = await faces
        return result
    }
    
    
    // MARK: - Private Methods
    
    private func projectHandBox(past results: [OrderedDictionary<CMTime, FrameResult>.Element], now currentTime: CMTime) -> CGRect {
        let lastResult = results.last!
        let firstResult = results.first!
        
        guard (lastResult.key - firstResult.key) > CMTime(value: 1, timescale: 2) else { // make sure results are not more than half seconds apart
            fatalError("Fail to project hand box: time interval too large")
        }
        
        var handBox = lastResult.value.hands!.first!.boundingBox.toImageCoordinates(CameraSettings.resolution)
        let deltaTime = lastResult.key - firstResult.key
        let deltaX = handBox.origin.x - firstResult.value.hands!.first!.boundingBox.origin.x
        let deltaY = handBox.origin.y - firstResult.value.hands!.first!.boundingBox.origin.y
        
        // project the new origin
        handBox.origin.x += deltaX / deltaTime.seconds * (currentTime - lastResult.key).seconds
        handBox.origin.y += deltaY / deltaTime.seconds * (currentTime - lastResult.key).seconds
        
        return handBox
    }
    
    private func transition(by hand: HumanHandPoseObservation) -> State {
        
        switch currentState {
        case .free: /// free -> detecting
            if isAbove(of: currentBox!["Front divider top"].position.y, hand.fingerTips) {
                return .detecting
            }
        case .crossedBack:
            fallthrough
            /// crossed back -> free
            /// crossed back -> crossed
        case .detecting:
            /// detecting -> free
            if !isAbove(of: max(currentBox!["Back top left"].position.y, currentBox!["Back top right"].position.y), hand.fingerTips) {
                return .free
            }
            /// detecting -> crossed
            if crossed(divider:(currentBox!["Front divider top"], currentBox!["Front top middle"], currentBox!["Back divider top"]), hand.fingerTips, handedness: hand.chirality!) {
                // play a sound
                Task { @MainActor in
                    self.onCrossed()
                }
                return .crossed
            }
        case .crossed:
            if !crossed(divider:(currentBox!["Front divider top"], currentBox!["Front top middle"], currentBox!["Back divider top"]), hand.fingerTips, handedness: hand.chirality!) {
                return .crossedBack
            }
        }
        
        return currentState
    }
    
    /// Returns true if any joints if above the horizon. Assume y increase upwards
    private func isAbove(of horizon: Float, _ keypoints: [Joint]) -> Bool {
        for joint in keypoints {
            if Float(joint.location.y * CameraSettings.resolution.height) > horizon {
                return true
            }
        }
        return false
    }
    
    /// Returns true if any fingertip crosses the divider polyline.
    /// - Parameters:
    ///   - divider: Tuple of three points (front/top, front/middle, back/top) as [x, y] in image space.
    ///   - keypoints: Hand joints to test.
    private func crossed(divider: (Keypoint, Keypoint, Keypoint), _ joints: [Joint], handedness: HumanHandPoseObservation.Chirality) -> Bool {
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
    
    /// Calculate the cm/px ratio
    private func calculateScaleToCM(_ box: BoxDetection) -> Float {
        let dividerHeight: Float = 10.0 // cm
        let keypointHeight = // px
        distance(box["Front divider top"].position, box["Front top middle"].position)
        
        return dividerHeight / keypointHeight
    }
    
    /// Calculate the region of interest for block detection
    /// Define ROI by hand
    func defineBlockROI(by handBox: CGRect, cmPerPixel: Float, chirality: HumanHandPoseObservation.Chirality) -> NormalizedRect {
        var roi = handBox
        let blockSize = CGFloat(2.5 / cmPerPixel)
        
        roi.origin.y -=  blockSize * 2
        roi.size.width += blockSize * 2
        roi.size.height += blockSize * 2
        
        if chirality == .left {
            roi.origin.x -= blockSize * 2
        }
        
        // right hand don't move the origin.x but extend the width
        
        return NormalizedRect(imageRect: roi, in: CameraSettings.resolution)
    }
    
    func runningAverage(_ detections: [BlockDetection]) -> CGPoint? {
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
    
    func followBlockROI(roiCenter: CGPoint, awayFrom hand: HumanHandPoseObservation) -> NormalizedRect? {
        let roiCenter = SIMD2<Double> (
            x: roiCenter.x,
            y: roiCenter.y
        )
        
        // extend the mid point to roi
        let blockSize = 2.5 / cmPerPixel!
        
        for joint in hand.fingerTips {
            if distance(roiCenter, SIMD2<Double>(
                x: joint.location.x * CameraSettings.resolution.width,
                y: joint.location.y * CameraSettings.resolution.height))
            < 0.5 * Double(blockSize) {
                return nil // Don't move away from hand
            }
        }
        
        let x: Double = roiCenter.x - Double(2 * blockSize)
        let y: Double = roiCenter.y - Double(2 * blockSize)
        let width: Double = roiCenter.x + Double(2 * blockSize) - x
        let heigh: Double = roiCenter.y + Double(2 * blockSize) - y
        
        let rect = CGRect(x: x, y: y, width: width, height: heigh)
        
        return NormalizedRect(imageRect: rect, in: CameraSettings.resolution)
    }
}


