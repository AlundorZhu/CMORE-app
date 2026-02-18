//
//  Session.swift
//  CMORE
//

import Foundation

struct Session: Identifiable, Codable {
    let id: UUID
    let date: Date
    let blockCount: Int
    let videoFileName: String
    let resultsFileName: String
}
