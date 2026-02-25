//
//  SessionStore.swift
//  CMORE
//

import Foundation
import SwiftData

/// Manages Session persistence via SwiftData.
/// Video and results files remain stored in the Documents directory.
class SessionStore {

    // MARK: - Singleton
    static let shared = SessionStore()

    var context: ModelContext!

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - CRUD

    func add(_ session: Session) {
        context.insert(session)
        try? context.save()
    }

    func delete(_ session: Session) {
        let videoURL = documentsDirectory.appendingPathComponent(session.videoFileName)
        let resultsURL = documentsDirectory.appendingPathComponent(session.resultsFileName)
        try? FileManager.default.removeItem(at: videoURL)
        try? FileManager.default.removeItem(at: resultsURL)

        context.delete(session)
        try? context.save()
    }
}
