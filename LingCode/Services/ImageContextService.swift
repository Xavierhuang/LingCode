//
//  ImageContextService.swift
//  LingCode
//
//  Image Context - Attach images to chat for visual context
//  Enables sending screenshots, mockups, and diagrams to AI
//

import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Attached Image Model

struct AttachedImage: Identifiable, Equatable {
    let id: UUID
    let name: String
    let data: Data
    let mimeType: String
    let size: CGSize
    let fileSize: Int
    let source: ImageSource
    let createdAt: Date
    
    enum ImageSource {
        case file(URL)
        case clipboard
        case screenshot
        case dropped
        case dragDrop
    }
    
    init(name: String, data: Data, mimeType: String, size: CGSize, source: ImageSource) {
        self.id = UUID()
        self.name = name
        self.data = data
        self.mimeType = mimeType
        self.size = size
        self.fileSize = data.count
        self.source = source
        self.createdAt = Date()
    }
    
    var base64Encoded: String {
        return data.base64EncodedString()
    }
    
    var nsImage: NSImage? {
        return NSImage(data: data)
    }
    
    /// Alias for nsImage for backward compatibility
    var image: NSImage {
        return nsImage ?? NSImage()
    }
    
    var thumbnail: NSImage? {
        guard let image = nsImage else { return nil }
        
        let thumbnailSize = CGSize(width: 100, height: 100)
        let aspectRatio = image.size.width / image.size.height
        
        var newSize: CGSize
        if aspectRatio > 1 {
            newSize = CGSize(width: thumbnailSize.width, height: thumbnailSize.width / aspectRatio)
        } else {
            newSize = CGSize(width: thumbnailSize.height * aspectRatio, height: thumbnailSize.height)
        }
        
        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        thumbnail.unlockFocus()
        
        return thumbnail
    }
    
    static func == (lhs: AttachedImage, rhs: AttachedImage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Image Context Service

class ImageContextService: ObservableObject {
    static let shared = ImageContextService()
    
    @Published var attachedImages: [AttachedImage] = []
    @Published var isCapturingScreen: Bool = false
    @Published var lastError: String?
    
    private let maxImages = 5
    private let maxImageSize = 20 * 1024 * 1024  // 20MB per image
    private let supportedTypes: [UTType] = [.png, .jpeg, .gif, .webP, .heic]
    
    private init() {}
    
    // MARK: - Add Images
    
    /// Add image from NSImage (used by drag/drop)
    @discardableResult
    func addImage(_ image: NSImage, source: AttachedImage.ImageSource) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return false
        }
        
        do {
            try validateImage(data: pngData)
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let attached = AttachedImage(
                name: "Image \(timestamp)",
                data: pngData,
                mimeType: "image/png",
                size: image.size,
                source: source
            )
            addImage(attached)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
    
    /// Clear all images (alias for removeAllImages)
    func clearImages() {
        removeAllImages()
    }
    
    @discardableResult
    func addFromFile(_ url: URL) -> Bool {
        do {
            try addFromFileThrows(url)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
    
    func addFromFileThrows(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImageError.fileNotFound
        }
        
        let data = try Data(contentsOf: url)
        try validateImage(data: data)
        
        guard let image = NSImage(data: data) else {
            throw ImageError.invalidImage
        }
        
        let mimeType = mimeTypeForExtension(url.pathExtension)
        let attached = AttachedImage(
            name: url.lastPathComponent,
            data: data,
            mimeType: mimeType,
            size: image.size,
            source: .file(url)
        )
        
        addImage(attached)
    }
    
    @discardableResult
    func addFromClipboard() -> Bool {
        do {
            try addFromClipboardThrows()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
    
    func addFromClipboardThrows() throws {
        let pasteboard = NSPasteboard.general
        
        guard let types = pasteboard.types else {
            throw ImageError.noImageInClipboard
        }
        
        // Check for image data
        for type in [NSPasteboard.PasteboardType.tiff, NSPasteboard.PasteboardType.png] {
            if types.contains(type), let data = pasteboard.data(forType: type) {
                try addImageData(data, name: "Clipboard Image", source: .clipboard)
                return
            }
        }
        
        // Check for file URL
        if types.contains(.fileURL),
           let url = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL {
            try addFromFileThrows(url)
            return
        }
        
        throw ImageError.noImageInClipboard
    }
    
    func addFromDrop(_ providers: [NSItemProvider]) async throws {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSImage, Error>) in
                    provider.loadObject(ofClass: NSImage.self) { object, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let image = object as? NSImage {
                            continuation.resume(returning: image)
                        } else {
                            continuation.resume(throwing: ImageError.invalidImage)
                        }
                    }
                }
                
                if let data = image.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: data),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    try await MainActor.run {
                        try addImageData(pngData, name: "Dropped Image", source: .dropped)
                    }
                }
            }
        }
    }
    
    func captureScreen(region: CGRect? = nil) async throws {
        await MainActor.run {
            isCapturingScreen = true
        }
        
        defer {
            Task { @MainActor in
                isCapturingScreen = false
            }
        }
        
        // Use screencapture command
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("lingcode_screenshot_\(UUID().uuidString).png")
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        
        if region != nil {
            // Interactive selection
            task.arguments = ["-i", "-x", tempURL.path]
        } else {
            // Full screen
            task.arguments = ["-x", tempURL.path]
        }
        
        try task.run()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0,
              FileManager.default.fileExists(atPath: tempURL.path) else {
            throw ImageError.screenshotFailed
        }
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let data = try Data(contentsOf: tempURL)
        try await MainActor.run {
            try addImageData(data, name: "Screenshot", source: .screenshot)
        }
    }
    
    private func addImageData(_ data: Data, name: String, source: AttachedImage.ImageSource) throws {
        try validateImage(data: data)
        
        guard let image = NSImage(data: data) else {
            throw ImageError.invalidImage
        }
        
        // Convert to PNG for consistency
        var imageData = data
        var mimeType = "image/png"
        
        if let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData) {
            if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                imageData = pngData
            } else if let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                imageData = jpegData
                mimeType = "image/jpeg"
            }
        }
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let finalName = "\(name) \(timestamp)"
        
        let attached = AttachedImage(
            name: finalName,
            data: imageData,
            mimeType: mimeType,
            size: image.size,
            source: source
        )
        
        addImage(attached)
    }
    
    private func addImage(_ image: AttachedImage) {
        // Remove oldest if at max
        if attachedImages.count >= maxImages {
            attachedImages.removeFirst()
        }
        
        attachedImages.append(image)
    }
    
    // MARK: - Remove Images
    
    func removeImage(_ id: UUID) {
        attachedImages.removeAll { $0.id == id }
    }
    
    func removeAllImages() {
        attachedImages.removeAll()
    }
    
    // MARK: - Validation
    
    private func validateImage(data: Data) throws {
        if data.count > maxImageSize {
            throw ImageError.imageTooLarge(maxSize: maxImageSize)
        }
        
        // Check magic bytes for valid image
        let header = data.prefix(12)
        let bytes = [UInt8](header)
        
        let isValid = isPNG(bytes) || isJPEG(bytes) || isGIF(bytes) || isWebP(bytes) || isHEIC(bytes)
        
        if !isValid {
            throw ImageError.unsupportedFormat
        }
    }
    
    private func isPNG(_ bytes: [UInt8]) -> Bool {
        return bytes.count >= 8 &&
            bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47
    }
    
    private func isJPEG(_ bytes: [UInt8]) -> Bool {
        return bytes.count >= 3 &&
            bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
    }
    
    private func isGIF(_ bytes: [UInt8]) -> Bool {
        return bytes.count >= 6 &&
            bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46
    }
    
    private func isWebP(_ bytes: [UInt8]) -> Bool {
        return bytes.count >= 12 &&
            bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
            bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50
    }
    
    private func isHEIC(_ bytes: [UInt8]) -> Bool {
        return bytes.count >= 12 &&
            bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70
    }
    
    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default: return "image/png"
        }
    }
    
    // MARK: - Generate Context
    
    func generateImagesContext() -> String {
        guard !attachedImages.isEmpty else { return "" }
        
        var context = "## Attached Images\n\n"
        
        for (index, image) in attachedImages.enumerated() {
            context += "### Image \(index + 1): \(image.name)\n"
            context += "- Size: \(Int(image.size.width))x\(Int(image.size.height))\n"
            context += "- File size: \(ByteCountFormatter.string(fromByteCount: Int64(image.fileSize), countStyle: .file))\n"
            context += "- Format: \(image.mimeType)\n\n"
        }
        
        context += "The images are attached to this message for visual reference.\n"
        
        return context
    }
    
    /// Prepare images for AI API (returns array of image data for multimodal models)
    func getImagesForAPI() -> [(data: String, mimeType: String)] {
        return attachedImages.map { image in
            (data: image.base64Encoded, mimeType: image.mimeType)
        }
    }
    
    // MARK: - Image Analysis
    
    func analyzeImage(_ id: UUID) async throws -> String {
        guard let image = attachedImages.first(where: { $0.id == id }) else {
            throw ImageError.imageNotFound
        }
        
        let prompt = """
        Analyze this image and describe:
        1. What you see (objects, text, UI elements)
        2. The layout and structure
        3. Any code or technical content
        4. Suggestions for implementation if it's a design/mockup
        """
        
        var response = ""
        let stream = AIService.shared.streamMessage(
            prompt,
            context: nil,
            images: [image],
            maxTokens: 1000,
            systemPrompt: "You are an image analysis expert. Describe images precisely and technically."
        )
        
        for try await chunk in stream {
            response += chunk
        }
        
        return response
    }
}

// MARK: - Errors

enum ImageError: Error, LocalizedError {
    case fileNotFound
    case invalidImage
    case imageTooLarge(maxSize: Int)
    case unsupportedFormat
    case noImageInClipboard
    case screenshotFailed
    case imageNotFound
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Image file not found"
        case .invalidImage:
            return "Invalid or corrupted image"
        case .imageTooLarge(let maxSize):
            return "Image too large. Maximum size is \(ByteCountFormatter.string(fromByteCount: Int64(maxSize), countStyle: .file))"
        case .unsupportedFormat:
            return "Unsupported image format. Use PNG, JPEG, GIF, or WebP"
        case .noImageInClipboard:
            return "No image found in clipboard"
        case .screenshotFailed:
            return "Failed to capture screenshot"
        case .imageNotFound:
            return "Image not found"
        }
    }
}
