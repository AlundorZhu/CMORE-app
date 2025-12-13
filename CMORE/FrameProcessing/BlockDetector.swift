//
//  BlockDetector.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 9/15/25.
//

import CoreML
import Vision


struct BlockDetector {
    static func createBlockDetector() -> CoreMLModelContainer {
        let model = try? ObjectDetector()
        
        guard let model = model else {
            fatalError("Failed to load BlockDetector model.")
        }
        
        guard let blockDetectorContainer = try? CoreMLModelContainer(model: model.model) else {
            fatalError(
                "Failed to convert BlockDetector model to CoreMLModelContainer."
            )
        }
        
        return blockDetectorContainer
    }
}

// block length 2.5cm or 1in
func blockLengthInPixels(scale: Float) -> Float {
    return 2.5 / scale
}
