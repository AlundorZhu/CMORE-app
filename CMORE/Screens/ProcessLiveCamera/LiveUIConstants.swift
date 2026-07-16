//
//  BoxShapeConstants.swift
//  CMORE
//

import CoreGraphics

enum LiveUIConstants {
    /// Scales the entire guide box around `scaleOrigin`.
    /// 1.0 keeps the base geometry unchanged, below 1.0 shrinks it, above 1.0 expands it.
    static let guideScale: CGFloat = 0.7

    private static let scaleOrigin = CGPoint(x: 0.5, y: 0.5)

    private static func scaledX(_ value: CGFloat) -> CGFloat {
        scaleOrigin.x + (value - scaleOrigin.x) * guideScale
    }

    private static func scaledY(_ value: CGFloat) -> CGFloat {
        scaleOrigin.y + (value - scaleOrigin.y) * guideScale
    }

    // X-axis is mirrored exactly around 0.5.
    private static let baseBackLeftX: CGFloat = 0.228
    static let backLeftX: CGFloat = scaledX(baseBackLeftX)
    static let backRightX: CGFloat = scaledX(1 - baseBackLeftX)

    private static let baseFrontTopLeftX: CGFloat = 0.07
    static let frontTopLeftX: CGFloat = scaledX(baseFrontTopLeftX)
    static let frontTopRightX: CGFloat = scaledX(1 - baseFrontTopLeftX)

    private static let baseFrontBottomLeftX: CGFloat = 0.09
    static let frontBottomLeftX: CGFloat = scaledX(baseFrontBottomLeftX)
    static let frontBottomRightX: CGFloat = scaledX(1 - baseFrontBottomLeftX)

    static let centerX: CGFloat = scaledX(0.5)

    static let stickTopY: CGFloat = scaledY(0.34)
    static let backRimY: CGFloat = scaledY(0.5)
    static let frontRimY: CGFloat = scaledY(0.75)
    static let bottomY: CGFloat = scaledY(0.95)

    // Maximum normalized distance from keypoint to the UI guide.
    static let offTolerant: Double = 0.12
}
