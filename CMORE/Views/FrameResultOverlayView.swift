//
//  FrameResultOverlayView.swift
//  CMORE
//
//  Created by ZIQIANG ZHU on 9/10/25.
//

import SwiftUI
import Vision

/// A view that displays the frame processing results as an overlay
struct FrameResultOverlayView: View {
    let frameResult: FrameResult
    let viewSize: CGSize
    
    var body: some View {
        Canvas { context, size in
            // Draw bounding boxes for faces
            if let faces = frameResult.faces {
                drawFaces(context: context, faces: faces, size: size)
            }
            
            // Draw box detection keypoints
            if let boxDetection = frameResult.boxDetection {
                drawBoxKeypoints(context: context, boxDetection: boxDetection, size: size)
            }
            
            // Draw processing state indicator
            drawProcessingState(context: context, state: frameResult.processingState, size: size)
        }
        .frame(width: viewSize.width, height: viewSize.height)
    }
    
    // MARK: - Drawing Functions
    
    private func drawFaces(context: GraphicsContext, faces: [BoundingBoxProviding], size: CGSize) {
        for face in faces {
            // Convert normalized coordinates to view coordinates
            let boundingBox = face.boundingBox
            let rect = CGRect(
                x: boundingBox.origin.x * size.width,
                y: (1.0 - boundingBox.origin.y - boundingBox.height) * size.height, // Flip Y coordinate
                width: boundingBox.width * size.width,
                height: boundingBox.height * size.height
            )
            
            // Draw face bounding box
            context.stroke(
                Path(rect),
                with: .color(.red),
                lineWidth: 2.0
            )
            
            // Add face label
            let labelRect = CGRect(
                x: rect.minX,
                y: rect.minY - 25,
                width: 50,
                height: 20
            )
            
            context.fill(
                Path(labelRect),
                with: .color(.red.opacity(0.8))
            )
            
            context.draw(
                Text("Face")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white),
                at: CGPoint(x: labelRect.midX, y: labelRect.midY)
            )
        }
    }
    
    private func drawBoxKeypoints(context: GraphicsContext, boxDetection: BoxDetection, size: CGSize) {
        let cameraResolution = CameraSettings.resolution
        
        // Define keypoint colors and connections
        let keypointColor = Color.blue
        let connectionColor = Color.green
        
        // Draw all keypoints
        for i in 0..<boxDetection.keypoints.count {
            let keypoint = boxDetection.keypoints[i]
            
            // Convert from camera coordinates to view coordinates
            let x = CGFloat(keypoint[0]) * size.width / cameraResolution.width
            let y = CGFloat(keypoint[1]) * size.height / cameraResolution.height
            
            // Draw keypoint circle
            let keypointRect = CGRect(
                x: x - 3,
                y: y - 3,
                width: 6,
                height: 6
            )
            
            context.fill(
                Path(ellipseIn: keypointRect),
                with: .color(keypointColor)
            )
            
            // Draw keypoint label
            let labelText = getKeypointName(for: i)
            context.draw(
                Text(labelText)
                    .font(.system(size: 8))
                    .foregroundColor(.white),
                at: CGPoint(x: x + 10, y: y - 10)
            )
        }
        
        // Draw box connections
        drawBoxConnections(context: context, boxDetection: boxDetection, size: size, color: connectionColor)
    }
    
    private func drawBoxConnections(context: GraphicsContext, boxDetection: BoxDetection, size: CGSize, color: Color) {
        let cameraResolution = CameraSettings.resolution
        
        // Define the connections for the box structure
        let connections: [(String, String)] = [
            // Rectangle
            ("Front top left", "Front bottom left"),
            ("Front top left", "Front top middle"),
            ("Front bottom left", "Front bottom middle"),
            ("Front top middle", "Front top right"),
            ("Front bottom middle", "Front bottom right"),
            ("Front top right", "Front bottom right"),
            
            // Rectangle
            ("Front top left", "Back top left"),
            ("Front top right", "Back top right"),
            ("Back top left", "Back top right"),
            
            // Dividers
            ("Front divider top", "Back divider top"),
            ("Front divider top", "Front top middle")
        ]
        
        for (startName, endName) in connections {
            if let startPoint = getKeypointByName(boxDetection, startName),
               let endPoint = getKeypointByName(boxDetection, endName),
               startPoint.count >= 3 && endPoint.count >= 3 {
                
                let startX = CGFloat(startPoint[0]) * size.width / cameraResolution.width
                let startY = CGFloat(startPoint[1]) * size.height / cameraResolution.height
                let endX = CGFloat(endPoint[0]) * size.width / cameraResolution.width
                let endY = CGFloat(endPoint[1]) * size.height / cameraResolution.height
                
                var path = Path()
                path.move(to: CGPoint(x: startX, y: startY))
                path.addLine(to: CGPoint(x: endX, y: endY))
                
                context.stroke(
                    path,
                    with: .color(color),
                    lineWidth: 1.5
                )
            }
        }
    }
    
    private func drawProcessingState(context: GraphicsContext, state: FrameProcessor.State, size: CGSize) {
        let stateText = state == .detecting ? "DETECTING" : "FREE"
        let stateColor: Color = state == .detecting ? .orange : .green
        
        // Draw state indicator in top-right corner
        let stateRect = CGRect(
            x: size.width - 100,
            y: 10,
            width: 90,
            height: 25
        )
        
        context.fill(
            Path(stateRect),
            with: .color(stateColor.opacity(0.8))
        )
        
        context.draw(
            Text(stateText)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white),
            at: CGPoint(x: stateRect.midX, y: stateRect.midY)
        )
    }
    
    // MARK: - Helper Functions
    
    private func getKeypointName(for index: Int) -> String {
        let keypointNames = ["FTL", "FBL", "FTM", "FBM", "FTR", "FBR", "BDT", "FDT", "BTL", "BTR"]
        return index < keypointNames.count ? keypointNames[index] : "\(index)"
    }
    
    private func getKeypointByName(_ boxDetection: BoxDetection, _ name: String) -> [Float]? {
        let keypointNames = ["Front top left", "Front bottom left", "Front top middle", "Front bottom middle", "Front top right", "Front bottom right", "Back divider top", "Front divider top", "Back top left", "Back top right"]
        
        if let index = keypointNames.firstIndex(of: name),
           index < boxDetection.keypoints.count {
            return boxDetection.keypoints[index]
        }
        return nil
    }
}

// MARK: - Preview
#Preview {
    // Create a mock frame result for preview
    let mockFrameResult = FrameResult(
        processingState: .detecting,
        faces: nil,
        boxDetection: nil,
        handPoses: nil
    )
    
    FrameResultOverlayView(
        frameResult: mockFrameResult,
        viewSize: CGSize(width: 300, height: 200)
    )
}
