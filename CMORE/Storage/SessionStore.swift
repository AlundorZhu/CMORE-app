//
//  SessionStore.swift
//  CMORE
//

import Foundation

/// Persists sessions as a JSON index file (sessions.json) in the Documents directory.
/// Video and results files are also stored in Documents, referenced by file name.
class SessionStore {
    static let shared = SessionStore()

    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var indexURL: URL {
        documentsDirectory.appendingPathComponent("sessions.json")
    }

    // MARK: - Public Methods

    func loadAll() -> [Session] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: indexURL)
            return try JSONDecoder().decode([Session].self, from: data)
        } catch {
            print("Failed to load sessions: \(error)")
            return []
        }
    }

    func add(_ session: Session) {
        var sessions = loadAll()
        sessions.insert(session, at: 0) // newest first
        save(sessions)
    }

    func delete(_ session: Session) {
        // Remove video and results files
        let videoURL = documentsDirectory.appendingPathComponent(session.videoFileName)
        let resultsURL = documentsDirectory.appendingPathComponent(session.resultsFileName)
        try? fileManager.removeItem(at: videoURL)
        try? fileManager.removeItem(at: resultsURL)

        // Remove from index
        var sessions = loadAll()
        sessions.removeAll { $0.id == session.id }
        save(sessions)
    }

    // MARK: - Private

    private func save(_ sessions: [Session]) {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: indexURL)
        } catch {
            print("Failed to save sessions index: \(error)")
        }
    }
}
