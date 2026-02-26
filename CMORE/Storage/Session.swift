//
//  Session.swift
//  CMORE
//

import Foundation
import SwiftData

@Model
final class Session {
    @Attribute(.unique) var id: UUID
    var date: Date
    var blockCount: Int
    var videoFileName: String
    var resultsFileName: String

    init(id: UUID = UUID(), date: Date, blockCount: Int, videoFileName: String, resultsFileName: String) {
        self.id = id
        self.date = date
        self.blockCount = blockCount
        self.videoFileName = videoFileName
        self.resultsFileName = resultsFileName
    }
}
