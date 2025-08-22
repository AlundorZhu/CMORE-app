//
//  CameraSettings.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/21/25.
//

import AVFoundation
import CoreGraphics

struct CameraSettings {
    static var resolution: CGSize = CGSize(width: 1920, height: 1080)
    static var frameRate: CMTime = CMTime(value: 1, timescale: 30) // 30 fps
    static var ShutterSpeed: CMTime = CMTime(value: 1, timescale: 500) // 1/500 second
    
    // Video encoding settings
    static var videoCodec: AVVideoCodecType = .h264
    static var averageBitRate: Int = 4000000 // 4 Mbps
    static var profileLevel: String = AVVideoProfileLevelH264BaselineAutoLevel
}
