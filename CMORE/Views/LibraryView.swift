//
//  LibraryView.swift
//  CMORE
//

import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions Yet",
                        systemImage: "video.slash",
                        description: Text("Tap + to record a new session")
                    )
                } else {
                    List(viewModel.sessions) { session in
                        SessionRow(session: session)
                    }
                }
            }
            .navigationTitle("Library")
            .overlay(alignment: .bottom) {
                NavigationLink {
                    CameraContainerView()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white, .black)
                        .shadow(radius: 4)
                }
            }
        }
    }
}

// MARK: - Session Row
private struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 60, height: 44)
                .overlay(
                    Image(systemName: "video.fill")
                        .foregroundColor(.secondary)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(session.date, style: .date)
                    .font(.headline)
                Text(session.date, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(session.blockCount) blocks")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Wrapper that owns the CMOREViewModel so the camera only initializes
/// when the user navigates to this screen.
struct CameraContainerView: View {
    @StateObject private var viewModel = CMOREViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CMOREView(viewModel: viewModel)
            .task {
                await viewModel.startCamera()
            }
            .navigationBarBackButtonHidden(true)
            .onAppear {
                OrientationManager.shared.lockToLandscape = true
                // Force the device to rotate to landscape right
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                }
            }
            .onDisappear {
                OrientationManager.shared.lockToLandscape = false
                // Allow rotation back to current device orientation
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
                }
            }
            .onChange(of: viewModel.showSaveConfirmation) { wasShowing, isShowing in
                // When the alert dismisses (user tapped Save or Discard), go back to library
                if wasShowing && !isShowing {
                    dismiss()
                }
            }
    }
}

#Preview {
    LibraryView()
}
