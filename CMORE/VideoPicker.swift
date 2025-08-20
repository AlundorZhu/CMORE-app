//
//  VideoPicker.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/19/25.
//
import SwiftUI
import PhotosUI
import Foundation

struct VideoPicker: UIViewControllerRepresentable {
    let completion: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        
        init(_ parent: VideoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else { 
                parent.dismiss()
                return 
            }

            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                // Always dismiss on main thread after processing
                defer {
                    DispatchQueue.main.async {
                        self.parent.dismiss()
                    }
                }
                
                if let error = error {
                    print("Error loading video file: \(error)")
                    return
                }

                guard let url = url else {
                    print("Failed to get video URL")
                    return
                }

                do {
                    // Copy to temporary location since the provided URL might not be accessible later
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                    
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    
                    // Call completion on main thread
                    DispatchQueue.main.async {
                        self.parent.completion(tempURL)
                    }
                } catch {
                    print("Error copying video file: \(error)")
                }
            }
        }
    }
}
