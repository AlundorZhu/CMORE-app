//
//  SessionStore.swift
//  CMORE
//

import Foundation
import SwiftData
import Vision

/// Manages Session persistence via SwiftData.
/// Video and results files remain stored in the Documents directory.
actor SessionStore {

    // MARK: - Singleton
    static let shared = SessionStore()

    nonisolated let container: ModelContainer
    private let context: ModelContext

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {
        self.container = try! ModelContainer(for: Session.self)
        self.context = ModelContext(container)
    }

    // MARK: - CRUD

    func add(
        id: UUID = UUID(),
        date: Date = Date(),
        name: String,
        blockCount: Int,
        videoFileName: String,
        resultsFileName: String,
        handedness: HumanHandPoseObservation.Chirality
    ) throws {
        let session = Session(
            id: id,
            date: date,
            name: name,
            blockCount: blockCount,
            videoFileName: videoFileName,
            resultsFileName: resultsFileName,
            handedness: handedness
        )
        context.insert(session)
        do {
            try context.save()
        } catch {
            dprint("Session store add error: \(error)")
            throw error
        }
    }

    func delete(_ session: Session) throws {
        let videoURL = documentsDirectory.appendingPathComponent(session.videoFileName)
        let resultsURL = documentsDirectory.appendingPathComponent(session.resultsFileName)
        do {
            try FileManager.default.removeItem(at: videoURL)
            try FileManager.default.removeItem(at: resultsURL)

            context.delete(session)
            try context.save()
        } catch {
            dprint("Session store delete error: \(error)")
            throw error
        }
    }
    
    func loadAll() throws -> [Session] {
        let fetchDescriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(fetchDescriptor)
    }

    func delete(_ id: UUID) throws {
        let predicate = #Predicate<Session> { Session in
            Session.id == id
        }
        
        var fetchDescriptor = FetchDescriptor<Session> (predicate: predicate)
        fetchDescriptor.fetchLimit = 1
        
        let fetchedSessions = try context.fetch(fetchDescriptor)
        
        if let session = fetchedSessions.first {
            try delete(session)
        }
    }

    func rename(_ id: UUID, to name: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let predicate = #Predicate<Session> { Session in
            Session.id == id
        }

        var fetchDescriptor = FetchDescriptor<Session>(predicate: predicate)
        fetchDescriptor.fetchLimit = 1

        guard let session = try context.fetch(fetchDescriptor).first else { return }
        session.name = trimmedName
        
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // move video url
        let oldVideoURL = documentsDir.appendingPathComponent(session.videoFileName)
        let newVideoFileName = "\(session.name).mov"
        let newVideoURL = documentsDir.appendingPathComponent(newVideoFileName)

        do {
            if FileManager.default.fileExists(atPath: newVideoURL.path) {
                try FileManager.default.removeItem(at: newVideoURL)
            }
            try FileManager.default.moveItem(at: oldVideoURL, to: newVideoURL)
            session.videoFileName = newVideoFileName
        } catch {
            print("Stream View Model: Error renaming recording: \(error)")
        }
        
        // move results url
        let oldResultsFileURL = documentsDir.appendingPathComponent(session.resultsFileName)
        let newResultsFileName = "\(session.name).json"
        let newResultsFileURL = documentsDir.appendingPathComponent(newResultsFileName)

        do {
            if FileManager.default.fileExists(atPath: newResultsFileURL.path) {
                try FileManager.default.removeItem(at: newResultsFileURL)
            }
            try FileManager.default.moveItem(at: oldResultsFileURL, to: newResultsFileURL)
            session.resultsFileName = newResultsFileName
        } catch {
            print("Stream View Model: Error renaming results file: \(error)")
        }

        do {
            try context.save()
        } catch {
            dprint("Session store rename error: \(error)")
            throw error
        }
    }
}
