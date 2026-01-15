//
//  AIResponseDebugLogger.swift
//  LingCode
//
//  Debug-only helper to dump raw AI responses safely without affecting UI rendering.
//

import Foundation

enum AIResponseDebugLogger {
    static func dump(
        label: String,
        text: String,
        maxPreviewChars: Int = 2000,
        writeFullToTempFile: Bool = true
    ) {
#if DEBUG
        let length = text.count
        let preview = String(text.prefix(maxPreviewChars))
        print("🧾 AI_RESPONSE_DUMP [\(label)]")
        print("   Length: \(length)")
        print("   Preview (first \(min(maxPreviewChars, length)) chars):")
        print(preview)
        print("🧾 AI_RESPONSE_DUMP [\(label)] END_PREVIEW")

        guard writeFullToTempFile else { return }

        do {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let fileURL = tempDir.appendingPathComponent("LingCode-AIResponse-\(sanitizedLabel(label))-\(timestamp()).txt")
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            print("🧾 AI_RESPONSE_DUMP [\(label)] saved full response to: \(fileURL.path)")
        } catch {
            print("🧾 AI_RESPONSE_DUMP [\(label)] failed to save full response: \(error)")
        }
#else
        _ = label
        _ = text
        _ = maxPreviewChars
        _ = writeFullToTempFile
#endif
    }

#if DEBUG
    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }

    private static func sanitizedLabel(_ label: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return label.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.reduce(into: "", { $0.append($1) })
    }
#endif
}

