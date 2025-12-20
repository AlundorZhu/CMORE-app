//
//  BlockDetector.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 9/15/25.
//

import CoreML
import Vision
import CoreImage

struct BlockDetector {
    private let modelContainer: CoreMLModelContainer
    
    init() {
        let model = try? ObjectDetector()
        
        guard let model = model else {
            fatalError("Failed to load BlockDetector model.")
        }
        
        guard let blockDetectorContainer = try? CoreMLModelContainer(model: model.model) else {
            fatalError(
                "Failed to convert BlockDetector model to CoreMLModelContainer."
            )
        }
        
        modelContainer = blockDetectorContainer
    }
    
    func perforAll(on ciImage: CIImage, in ROIs: [NormalizedRect]) -> AsyncStream<BlockDetection> {
        return AsyncStream { continuation in
            Task {
                await withTaskGroup(of: BlockDetection.self) { group in
                    for roi in ROIs {
                        group.addTask {
                            var request = CoreMLRequest(model: modelContainer)
                            request.regionOfInterest = roi
                            return BlockDetection(
                                ROI: roi,
                                objects: try? await request.perform(on: ciImage) as? [RecognizedObjectObservation]
                            )
                        }
                    }
                    
                    for await detection in group {
                        continuation.yield(detection)
                    }
                    
                    continuation.finish()
                }
            }
        }
    }
}

// block length 2.5cm or 1in
func blockLengthInPixels(scale: Double) -> Double {
    return 2.5 / scale
}
