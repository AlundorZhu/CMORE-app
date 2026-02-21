//
//  LibraryViewModel.swift
//  CMORE
//

import Foundation

class LibraryViewModel: ObservableObject {
    @Published var sessions: [Session] = []

    func loadSessions() {
        sessions = SessionStore.shared.loadAll()
        #if DEBUG
        print("Library View Model: sessions loaded: \(sessions)")
        #endif
    }

    func deleteSessions(at offsets: IndexSet) {
        let sessionsToDelete = offsets.compactMap { index in
            sessions.indices.contains(index) ? sessions[index] : nil
        }
        sessionsToDelete.forEach { SessionStore.shared.delete($0) }
        sessions.remove(atOffsets: offsets)
    }
}
