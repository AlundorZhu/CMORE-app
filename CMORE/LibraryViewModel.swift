//
//  LibraryViewModel.swift
//  CMORE
//

import Foundation

class LibraryViewModel: ObservableObject {
    @Published var sessions: [Session] = Session.placeholders
}
