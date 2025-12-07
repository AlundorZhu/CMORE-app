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
    }
    
    public private(set) var countingBlocks = false
    
    private lazy var handedness: HumanHandPoseObservation.Chirality = .right
    
    private let facesRequest = DetectFaceRectanglesRequest()
    
    private let handsRequest = DetectHumanHandPoseRequest()
    
    private var blocksRequest: CoreMLRequest /// var because the region of interest changes
    
//    private lazy var blocksRequestDuplicate: CoreMLRequest = self.blocksRequest /// one ROI follows the hand, another follows the block projectory
    
    private let boxRequest: CoreMLRequest
    
    private lazy var results: OrderedDictionary<CMTime, FrameResult> = .init()
    
    private var currentBox: BoxDetection?
    
    private var currentState: State = .free
    
    private var cmPerPixel: Float?
    
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
    /// - Parameter ciImage: The frame to process as a Core Image
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
        
        guard !hands.isEmpty else {
            result.faces = await faces
            return result
        }
        
        // MARK: - detect the block
        if cmPerPixel == nil {
            cmPerPixel = calculateScaleToCM(currentBox)
        }
        
        currentState = transition(by: hands.first!)
        
        print("\(currentState)")
        
        switch currentState {
        case .free:
            break
            
        case .detecting: // look for block around the hand
            
            var handROI = Blocks(ROI: defineBlockROI(by: hands.first!, cmPerPixel: cmPerPixel!))
            
            blocksRequest.regionOfInterest = handROI.ROI
            
            async let blocksAroundHand = try? blocksRequest.perform(on: ciImage)
            if let blocks = await blocksAroundHand as? [RecognizedObjectObservation], !blocks.isEmpty {
                handROI.objects = blocks
            }
            
            result.blocks = handROI
            
        case .crossed: // plus roi follow block
            
            var ROI: NormalizedRect
            if let awayROI = followBlockROI(awayFrom: hands.first!) {
                ROI = awayROI
            } else {
                ROI = defineBlockROI(by: hands.first!, cmPerPixel: cmPerPixel!)
            }
            
            
            blocksRequest.regionOfInterest = ROI
            
            var blockROI = Blocks(ROI: ROI)
            
            async let blocksAroundHand = try? blocksRequest.perform(on: ciImage)
            if let blocks = await blocksAroundHand as? [RecognizedObjectObservation], !blocks.isEmpty {
                blockROI.objects = blocks
            }
            
            result.blocks = blockROI
            
        default:
            break
        }
        
        result.faces = await faces
        return result
    }
    
    
    // MARK: - Private Methods
    
    private func transition(by hand: HumanHandPoseObservation) -> State {
        let allJoints = hand.allJoints()
        let jointNames: [HumanHandPoseObservation.JointName] = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
        var fingerTips: [Joint] = []
        
        for jointName in jointNames {
            
            /// was going to just use the fingerTips if the joint(for:) func isn't broken
            if let joint = allJoints[jointName] {
                fingerTips.append(joint)
            }
        }
        
        if currentState == .free &&
            isAbove(of: currentBox!["Front divider top"].position.y, fingerTips) {
            return .detecting
        } else if currentState == .detecting &&
                    !isAbove(of: max(currentBox!["Back top left"].position.y, currentBox!["Back top right"].position.y), fingerTips) {
            return .free
        } else if currentState == .detecting &&
                    crossed(divider:(currentBox!["Front divider top"], currentBox!["Front top middle"], currentBox!["Back divider top"]), fingerTips, handedness: hand.chirality!) {
            // play a sound
            Task { @MainActor in
                self.onCrossed()
            }
            return .crossed
        } else if currentState == .crossed &&
                    !crossed(divider:(currentBox!["Front divider top"], currentBox!["Front top middle"], currentBox!["Back divider top"]), fingerTips, handedness: hand.chirality!) &&
                    !isAbove(of: max(currentBox!["Back top left"].position.y, currentBox!["Back top right"].position.y), fingerTips) {
            return .free
        } else {
            return currentState
        }
    }
    
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
    func defineBlockROI(by hand: HumanHandPoseObservation, cmPerPixel: Float) -> NormalizedRect {
        var roi = hand.boundingBox.toImageCoordinates(CameraSettings.resolution)
        let blockSize = CGFloat(2.5 / cmPerPixel)
        
        roi.origin.y -=  blockSize * 2
        roi.size.width += blockSize * 2
        roi.size.height += blockSize * 2
        
        if hand.chirality == .left {
            roi.origin.x -= blockSize * 2
        }
        
        // right hand don't move the origin.x but extend the width
        
        return NormalizedRect(imageRect: roi, in: CameraSettings.resolution)
    }
    
    func followBlockROI(awayFrom hand: HumanHandPoseObservation) -> NormalizedRect? {
        let allJoints = hand.allJoints()
        let jointNames: [HumanHandPoseObservation.JointName] = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
        var fingerTips: [Joint] = []
        
        for jointName in jointNames {
            
            /// was going to just use the fingerTips if the joint(for:) func isn't broken
            if let joint = allJoints[jointName] {
                fingerTips.append(joint)
            }
        }
        
        if results.count < 3 {
            return nil
        }
        
        // calculate the running average of block centers
        var boxes: [CGRect] = []
        // in the last 3 framesResults
        for i in 0..<3 {
            let lastResult = results.elements[results.count - i - 1].value
            guard let blocks = lastResult.blocks,
                  let objects = blocks.objects,
                  !objects.isEmpty
            else {
                return nil
            }
            
            for object in objects {
                let box = object.boundingBox.toImageCoordinates(from: blocks.ROI, imageSize: CameraSettings.resolution)
                boxes.append(box)
            }
        }
        
        var average: SIMD2<Double> = .zero
        for box in boxes {
            average.x += Double(box.midX)
            average.y += Double(box.midY)
        }
        
        average.x /= Double(boxes.count)
        average.y /= Double(boxes.count)
        
        // extend the mid point to roi
        let blockSize = 2.5 / cmPerPixel!
        
        for joint in fingerTips {
            if distance(average, SIMD2<Double>(x: joint.location.x * CameraSettings.resolution.width, y: joint.location.y * CameraSettings.resolution.height)) > 0.5 * Double(blockSize) {
                
                let x: Double = average.x - Double(2 * blockSize)
                let y: Double = average.y - Double(2 * blockSize)
                let width: Double = average.x + Double(2 * blockSize) - x
                let heigh: Double = average.y + Double(2 * blockSize) - y
                
                let rect = CGRect(x: x, y: y, width: width, height: heigh)
                
                return NormalizedRect(imageRect: rect, in: CameraSettings.resolution)
            }
        }
        return nil
    }
}


