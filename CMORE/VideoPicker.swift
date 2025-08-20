//
//  VideoPicker.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 8/19/25.
//
import SwiftUI
import PhotosUI
import Foundation

// MARK: - Video Picker
/// A SwiftUI wrapper around PHPickerViewController for selecting videos from the photo library
/// Uses UIViewControllerRepresentable to bridge UIKit and SwiftUI
/// SIMPLIFICATION SUGGESTIONS:
/// 1. Error handling could be improved with user-visible error messages
/// 2. Could add support for multiple video selection if needed
/// 3. The file copying logic could be extracted to a separate utility
struct VideoPicker: UIViewControllerRepresentable {
    // MARK: - Properties
    
    /// Callback function called when user selects a video
    let completion: (URL) -> Void
    
    /// SwiftUI environment value to dismiss this view
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - UIViewControllerRepresentable Methods
    
    /// Creates the PHPickerViewController
    /// - Parameter context: The context containing coordinator and other info
    /// - Returns: Configured picker controller
    func makeUIViewController(context: Context) -> PHPickerViewController {
        // Configure the picker to only show videos
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos // Only show video files
        configuration.selectionLimit = 1 // Allow only one video selection
        
        // Create and configure the picker
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator // Set our coordinator as delegate
        return picker
    }
    
    /// Called when SwiftUI needs to update the view controller (not needed here)
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    /// Creates the coordinator that handles picker delegate methods
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator Class
    /// Handles the PHPickerViewController delegate methods
    /// This is where we process the user's video selection
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        
        init(_ parent: VideoPicker) {
            self.parent = parent
        }
        
        /// Called when user finishes picking videos (or cancels)
        /// - Parameters:
        ///   - picker: The picker controller
        ///   - results: Array of selected items (videos in our case)
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Get the first (and only) selected video
            guard let result = results.first else { 
                // User cancelled - just dismiss the picker
                parent.dismiss()
                return 
            }

            // Load the video file from the photo library
            // SIMPLIFICATION SUGGESTION: This error handling could be more user-friendly
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                // Always dismiss the picker when we're done (success or failure)
                defer {
                    DispatchQueue.main.async {
                        self.parent.dismiss()
                    }
                }
                
                // Handle any errors during file loading
                if let error = error {
                    print("Error loading video file: \(error)")
                    return
                }

                // Make sure we have a valid URL
                guard let url = url else {
                    print("Failed to get video URL")
                    return
                }

                do {
                    // Copy the video to a temporary location we can access later
                    // The original URL from Photos might not be accessible after this method returns
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                    
                    // Remove any existing file at the temp location
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    
                    // Copy the video file
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    
                    // Call the completion handler with our accessible URL
                    DispatchQueue.main.async {
                        self.parent.completion(tempURL)
                    }
                } catch {
                    print("Error copying video file: \(error)")
                    // SIMPLIFICATION SUGGESTION: Could show user-friendly error alert here
                }
            }
        }
    }
}
