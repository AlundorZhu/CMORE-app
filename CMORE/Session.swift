//
//  Session.swift
//  CMORE
//

import Foundation

struct Session: Identifiable {
    let id = UUID()
    let date: Date
    let blockCount: Int
}

// MARK: - Placeholder Data
extension Session {
    static let placeholders: [Session] = [
        Session(date: Calendar.current.date(byAdding: .hour, value: -2, to: .now)!, blockCount: 47),
        Session(date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!, blockCount: 32),
        Session(date: Calendar.current.date(byAdding: .day, value: -3, to: .now)!, blockCount: 55),
        Session(date: Calendar.current.date(byAdding: .day, value: -7, to: .now)!, blockCount: 28),
    ]
}
