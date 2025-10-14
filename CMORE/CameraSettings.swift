//
//  CameraSettings.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/21/25.
//

import AVFoundation
import CoreGraphics

struct CameraSettings {
    static let resolution: CGSize = CGSize(width: 1920, height: 1080)
//     static var frameRate: CMTime = CMTime(value: 1, timescale: 60)
    static let frameRate = 240.0
    static let minFrameDuration: CMTime = CMTime(value: 1, timescale: 240) // min 30 fps
    // static var fps : Double = 30
    static let maxExposureDuration: CMTime = CMTime(value: 1, timescale: 240) // 1/240 second
    
    // Video encoding settings
    static let videoCodec: AVVideoCodecType = .h264
    static let averageBitRate: Int = 4000000 // 4 Mbps
    static let profileLevel: String = AVVideoProfileLevelH264BaselineAutoLevel
}
