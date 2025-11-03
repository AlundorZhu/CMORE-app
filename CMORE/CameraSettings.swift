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
    static let frameRate = 120.0
    
    // Video encoding settings - H.264 for better performance at high frame rates
    static let videoCodec: AVVideoCodecType = .h264
}
