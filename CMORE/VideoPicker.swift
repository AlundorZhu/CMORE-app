//
//  VideoPicker.swift
//  HandDetectionDemo
//
//  Created by Sam King on 10/19/24.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct VideoPicker: UIViewControllerRepresentable {
    /// Returns picked video URL copied into app temp dir.
    /// Returns nil on cancel/failure.
    var completion: (URL?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let completion: (URL?) -> Void

        init(completion: @escaping (URL?) -> Void) {
            self.completion = completion
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let result = results.first else {
                completion(nil) // user cancelled
                return
            }

            let provider = result.itemProvider
            let typeId = UTType.movie.identifier

            guard provider.hasItemConformingToTypeIdentifier(typeId) else {
                completion(nil)
                return
            }

            provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, error in
                if let error {
                    print("VideoPicker load error: \(error.localizedDescription)")
                    DispatchQueue.main.async { self.completion(nil) }
                    return
                }

                guard let sourceURL = url else {
                    DispatchQueue.main.async { self.completion(nil) }
                    return
                }

                do {
                    let tempDir = FileManager.default.temporaryDirectory
                    let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
                    let destURL = tempDir.appendingPathComponent("\(UUID().uuidString).\(ext)")

                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)

                    DispatchQueue.main.async {
                        self.completion(destURL)
                    }
                } catch {
                    print("VideoPicker copy error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.completion(nil)
                    }
                }
            }
        }
    }
}
