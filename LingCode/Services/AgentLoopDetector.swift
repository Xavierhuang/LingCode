//
//  AgentLoopDetector.swift
//  LingCode
//
//  Action hashing and loop-detection helpers (extracted from AgentService).
//

import Foundation

enum AgentLoopDetector {
    static func buildLoopDetectionHint(failedActions: Set<String>) -> String {
        if failedActions.isEmpty { return "" }
        return "The following actions were already tried and failed. Do NOT repeat them: \(failedActions.joined(separator: ", "))"
    }

    static func calculateActionHash(_ decision: AgentDecision) -> String {
        let command = decision.command ?? ""
        let filePath = decision.filePath ?? ""
        let normalizedCode = normalizeCodeForHashing(decision.code ?? "")
        let codeHash = normalizedCode.hashValue
        return "\(decision.action):\(command):\(filePath):\(codeHash)"
    }

    static func calculateActionHashFromStep(_ step: AgentStep) -> String {
        let description = step.description.lowercased()
        var action = "unknown"
        var filePath = ""

        if description.hasPrefix("read: ") {
            action = "file"
            filePath = String(description.dropFirst("read: ".count))
        } else if description.hasPrefix("write: ") {
            action = "code"
            filePath = String(description.dropFirst("write: ".count))
        } else if description.hasPrefix("exec: ") {
            action = "terminal"
            let command = String(description.dropFirst("exec: ".count))
            return "\(action):\(command)::0"
        }

        return "\(action)::\(filePath):0"
    }

    static func normalizeCodeForHashing(_ code: String) -> String {
        var normalized = code
        let lines = normalized.components(separatedBy: .newlines)
        normalized = lines.map { line in
            if let commentRange = line.range(of: "//") {
                return String(line[..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return line
        }.joined(separator: "\n")

        do {
            let pattern = #"/\*.*?\*/"#
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "")
        } catch {
            normalized = normalized.replacingOccurrences(of: "/*", with: "")
            normalized = normalized.replacingOccurrences(of: "*/", with: "")
        }

        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let trimmedLines = normalized.components(separatedBy: .newlines)
        normalized = trimmedLines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        normalized = normalized.replacingOccurrences(of: " ", with: "")
        normalized = normalized.replacingOccurrences(of: "\n", with: "")
        normalized = normalized.replacingOccurrences(of: "\t", with: "")
        return normalized.lowercased()
    }

    static func normalizeFilePath(_ filePath: String, projectURL: URL?) -> String {
        guard !filePath.isEmpty else { return "" }
        var normalized = filePath

        if let projectURL = projectURL {
            let projectPath = projectURL.path
            if normalized.hasPrefix(projectPath) {
                normalized = String(normalized.dropFirst(projectPath.count))
                if normalized.hasPrefix("/") {
                    normalized = String(normalized.dropFirst())
                }
            } else if normalized.hasPrefix("/") {
                normalized = (normalized as NSString).standardizingPath
            }
        } else if normalized.hasPrefix("/") {
            normalized = (normalized as NSString).standardizingPath
        }

        normalized = normalized.replacingOccurrences(of: "\\", with: "/")
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }
        if normalized.hasPrefix("./") {
            normalized = String(normalized.dropFirst(2))
        }
        return normalized
    }
}
