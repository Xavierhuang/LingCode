//
//  ImageContextService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import AppKit
import Combine
import CoreGraphics

/// Service for handling images as AI context (like Cursor)
class ImageContextService: ObservableObject {
    static let shared = ImageContextService()
    
    @Published var attachedImages: [AttachedImage] = []
    @Published var isProcessing: Bool = false
    
    private init() {}
    
    // MARK: - Image Management
    
    /// Add an image from clipboard
    func addFromClipboard() -> Bool {
        let pasteboard = NSPasteboard.general
        
        // Try to get image from pasteboard
        if let image = NSImage(pasteboard: pasteboard) {
            return addImage(image, source: .clipboard)
        }
        
        // Try to get image from file URL
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            for url in urls {
                if isImageFile(url) {
                    if let image = NSImage(contentsOf: url) {
                        return addImage(image, source: .file(url))
                    }
                }
            }
        }
        
        return false
    }
    
    /// Add an image from file
    func addFromFile(_ url: URL) -> Bool {
        guard isImageFile(url) else { return false }
        guard let image = NSImage(contentsOf: url) else { return false }
        return addImage(image, source: .file(url))
    }
    
    /// Add an image from NSImage
    func addImage(_ image: NSImage, source: ImageSource) -> Bool {
        guard attachedImages.count < 5 else {
            // Limit to 5 images
            return false
        }
        
        // Resize if too large
        let maxDimension: CGFloat = 1024
        let resizedImage = resizeImage(image, maxDimension: maxDimension)
        
        // Convert to base64 for API
        guard let base64 = imageToBase64(resizedImage) else {
            return false
        }
        
        let attached = AttachedImage(
            image: resizedImage,
            base64: base64,
            source: source,
            size: resizedImage.size
        )
        
        DispatchQueue.main.async {
            self.attachedImages.append(attached)
        }
        
        return true
    }
    
    /// Remove an attached image
    func removeImage(_ id: UUID) {
        attachedImages.removeAll { $0.id == id }
    }
    
    /// Remove all attached images
    func clearImages() {
        attachedImages.removeAll()
    }
    
    // MARK: - Context Building
    
    /// Build context with images for AI
    func buildImageContext() -> [(type: String, data: String)] {
        return attachedImages.map { image in
            (type: "image/png", data: image.base64)
        }
    }
    
    /// Build Anthropic-compatible message content
    func buildAnthropicContent(text: String) -> [[String: Any]] {
        var content: [[String: Any]] = []
        
        // Add images first
        for image in attachedImages {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/png",
                    "data": image.base64
                ]
            ])
        }
        
        // Add text
        content.append([
            "type": "text",
            "text": text
        ])
        
        return content
    }
    
    /// Build OpenAI-compatible message content
    func buildOpenAIContent(text: String) -> [[String: Any]] {
        var content: [[String: Any]] = []
        
        // Add text first
        content.append([
            "type": "text",
            "text": text
        ])
        
        // Add images
        for image in attachedImages {
            content.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/png;base64,\(image.base64)",
                    "detail": "auto"
                ]
            ])
        }
        
        return content
    }
    
    // MARK: - Screenshot
    
    /// Take a screenshot of a window or screen
    func takeScreenshot(type: ScreenshotType) {
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var image: NSImage?
            
            switch type {
            case .fullScreen:
                image = self.captureFullScreen()
            case .window:
                image = self.captureWindow()
            case .selection:
                // Would need user interaction for selection
                image = self.captureFullScreen()
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                if let img = image {
                    _ = self.addImage(img, source: .screenshot)
                }
            }
        }
    }
    
    private func captureFullScreen() -> NSImage? {
        // Use NSScreen to get display bounds
        guard let screen = NSScreen.main else { return nil }
        
        let screenRect = screen.frame
        
        // Note: Actual screenshot capture requires ScreenCaptureKit (macOS 12.3+)
        // or screen recording permission. For now, we'll create a placeholder.
        // In production, you would:
        // 1. Request screen recording permission
        // 2. Use ScreenCaptureKit framework for macOS 12.3+
        // 3. Or use CGWindowListCreateImage with proper permissions
        
        // Create a placeholder image indicating screenshot functionality
        // Users can paste screenshots from clipboard instead
        let image = NSImage(size: screenRect.size)
        image.lockFocus()
        
        // Draw a placeholder
        NSColor.darkGray.setFill()
        NSRect(origin: .zero, size: screenRect.size).fill()
        
        // Add text
        let text = "Screenshot placeholder\n\nUse Cmd+Shift+3 or Cmd+Shift+4\nto take a screenshot, then paste it here"
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.lightGray,
            .font: NSFont.systemFont(ofSize: 16)
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = NSRect(
            x: (screenRect.width - textSize.width) / 2,
            y: (screenRect.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributedString.draw(in: textRect)
        
        image.unlockFocus()
        
        return image
    }
    
    private func captureWindow() -> NSImage? {
        // Window capture requires ScreenCaptureKit (macOS 12.3+) or screen recording permission
        // For now, fallback to full screen placeholder
        return captureFullScreen()
    }
    
    // MARK: - Helpers
    
    private func isImageFile(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }
    
    private func resizeImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }
        
        let scale: CGFloat
        if size.width > size.height {
            scale = maxDimension / size.width
        } else {
            scale = maxDimension / size.height
        }
        
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
    
    private func imageToBase64(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return pngData.base64EncodedString()
    }
}

// MARK: - Supporting Types

struct AttachedImage: Identifiable {
    let id = UUID()
    let image: NSImage
    let base64: String
    let source: ImageSource
    let size: NSSize
    let addedAt = Date()
    
    var sizeDescription: String {
        "\(Int(size.width))x\(Int(size.height))"
    }
}

enum ImageSource {
    case clipboard
    case file(URL)
    case screenshot
    case dragDrop
    
    var description: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .file(let url): return url.lastPathComponent
        case .screenshot: return "Screenshot"
        case .dragDrop: return "Dropped"
        }
    }
}

enum ScreenshotType {
    case fullScreen
    case window
    case selection
}

