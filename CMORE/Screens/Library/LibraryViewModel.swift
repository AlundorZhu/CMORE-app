//
//  LibraryViewModel.swift
//  CMORE
//

import Foundation

class LibraryViewModel: ObservableObject {
    @Published var sessions: [Session] = []

    func loadSessions() {
        sessions = SessionStore.shared.loadAll()
    }
}
