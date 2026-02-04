//
//  PrivacyModeService.swift
//  LingCode
//
//  Privacy Mode - Control data sharing and cloud features
//  Allows users to disable cloud features for sensitive projects
//

import Foundation
import Combine

// MARK: - Privacy Settings

struct PrivacySettings: Codable, Equatable {
    var isPrivacyModeEnabled: Bool
    var useLocalModelsOnly: Bool
    var disableTelemetry: Bool
    var disableCodeSharing: Bool
    var redactSensitiveData: Bool
    var excludedPatterns: [String]
    var trustedDomains: [String]
    
    static let `default` = PrivacySettings(
        isPrivacyModeEnabled: false,
        useLocalModelsOnly: false,
        disableTelemetry: false,
        disableCodeSharing: false,
        redactSensitiveData: true,
        excludedPatterns: [
            ".env*",
            "*secret*",
            "*password*",
            "*token*",
            "*key*",
            "credentials*",
            "*.pem",
            "*.key"
        ],
        trustedDomains: [
            "api.openai.com",
            "api.anthropic.com"
        ]
    )
}

// MARK: - Sensitive Data Types

enum SensitiveDataType: String, CaseIterable {
    case apiKey = "API Key"
    case password = "Password"
    case token = "Token"
    case secret = "Secret"
    case privateKey = "Private Key"
    case connectionString = "Connection String"
    case email = "Email"
    case phone = "Phone Number"
    case ssn = "SSN"
    case creditCard = "Credit Card"
    
    var patterns: [String] {
        switch self {
        case .apiKey:
            return [
                #"(?i)(api[_-]?key|apikey)\s*[:=]\s*['"]?[\w\-]+"#,
                #"sk-[a-zA-Z0-9]{20,}"#,
                #"AIza[a-zA-Z0-9_-]{35}"#
            ]
        case .password:
            return [
                #"(?i)(password|passwd|pwd)\s*[:=]\s*['"][^'"]+['"]"#
            ]
        case .token:
            return [
                #"(?i)(token|bearer|auth)\s*[:=]\s*['"]?[\w\-\.]+"#,
                #"ghp_[a-zA-Z0-9]{36}"#,
                #"gho_[a-zA-Z0-9]{36}"#
            ]
        case .secret:
            return [
                #"(?i)secret\s*[:=]\s*['"][^'"]+['"]"#
            ]
        case .privateKey:
            return [
                #"-----BEGIN (?:RSA |EC )?PRIVATE KEY-----"#,
                #"-----BEGIN OPENSSH PRIVATE KEY-----"#
            ]
        case .connectionString:
            return [
                #"(?i)(mongodb|postgres|mysql|redis):\/\/[^\s]+"#,
                #"(?i)Server=.+;Database=.+;User Id=.+;Password=.+"#
            ]
        case .email:
            return [
                #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#
            ]
        case .phone:
            return [
                #"\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}"#
            ]
        case .ssn:
            return [
                #"\b\d{3}-\d{2}-\d{4}\b"#
            ]
        case .creditCard:
            return [
                #"\b(?:\d{4}[-\s]?){3}\d{4}\b"#
            ]
        }
    }
}

// MARK: - Privacy Mode Service

class PrivacyModeService: ObservableObject {
    static let shared = PrivacyModeService()
    
    @Published var settings: PrivacySettings
    @Published var projectPrivacyOverrides: [URL: Bool] = [:]
    @Published var detectedSensitiveData: [SensitiveDataDetection] = []
    
    private let settingsURL: URL
    
    struct SensitiveDataDetection: Identifiable {
        let id = UUID()
        let file: String
        let line: Int
        let type: SensitiveDataType
        let match: String
        let isRedacted: Bool
    }
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let lingcodeDir = appSupport.appendingPathComponent("LingCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: lingcodeDir, withIntermediateDirectories: true)
        settingsURL = lingcodeDir.appendingPathComponent("privacy_settings.json")
        
        settings = PrivacyModeService.loadSettings(from: settingsURL)
    }
    
    // MARK: - Settings Management
    
    func updateSettings(_ newSettings: PrivacySettings) {
        settings = newSettings
        saveSettings()
    }
    
    func enablePrivacyMode() {
        settings.isPrivacyModeEnabled = true
        settings.useLocalModelsOnly = true
        settings.disableTelemetry = true
        settings.disableCodeSharing = true
        saveSettings()
    }
    
    func disablePrivacyMode() {
        settings.isPrivacyModeEnabled = false
        saveSettings()
    }
    
    func setProjectPrivacyMode(_ projectURL: URL, enabled: Bool) {
        projectPrivacyOverrides[projectURL] = enabled
    }
    
    func isPrivacyEnabled(for projectURL: URL? = nil) -> Bool {
        if let url = projectURL, let override = projectPrivacyOverrides[url] {
            return override
        }
        return settings.isPrivacyModeEnabled
    }
    
    // MARK: - Sensitive Data Detection
    
    func scanForSensitiveData(in content: String, filename: String) -> [SensitiveDataDetection] {
        var detections: [SensitiveDataDetection] = []
        let lines = content.components(separatedBy: "\n")
        
        for (lineIndex, line) in lines.enumerated() {
            for dataType in SensitiveDataType.allCases {
                for pattern in dataType.patterns {
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                        let range = NSRange(line.startIndex..., in: line)
                        let matches = regex.matches(in: line, options: [], range: range)
                        
                        for match in matches {
                            if let matchRange = Range(match.range, in: line) {
                                let matchedText = String(line[matchRange])
                                let detection = SensitiveDataDetection(
                                    file: filename,
                                    line: lineIndex + 1,
                                    type: dataType,
                                    match: matchedText,
                                    isRedacted: false
                                )
                                detections.append(detection)
                            }
                        }
                    }
                }
            }
        }
        
        return detections
    }
    
    func scanProject(_ projectURL: URL) async -> [SensitiveDataDetection] {
        var allDetections: [SensitiveDataDetection] = []
        let fm = FileManager.default
        
        func scanDirectory(_ url: URL) {
            guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
            
            for item in contents {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                
                if isDir {
                    // Skip common non-code directories
                    let name = item.lastPathComponent
                    if !["node_modules", ".git", "build", "dist", "Pods", "DerivedData"].contains(name) {
                        scanDirectory(item)
                    }
                } else {
                    // Scan file
                    if let content = try? String(contentsOf: item, encoding: .utf8) {
                        let relativePath = item.path.replacingOccurrences(of: projectURL.path + "/", with: "")
                        let detections = scanForSensitiveData(in: content, filename: relativePath)
                        allDetections.append(contentsOf: detections)
                    }
                }
            }
        }
        
        scanDirectory(projectURL)
        
        await MainActor.run {
            detectedSensitiveData = allDetections
        }
        
        return allDetections
    }
    
    // MARK: - Data Redaction
    
    func redactSensitiveData(in content: String) -> String {
        guard settings.redactSensitiveData else { return content }
        
        var redacted = content
        
        for dataType in SensitiveDataType.allCases {
            for pattern in dataType.patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(redacted.startIndex..., in: redacted)
                    redacted = regex.stringByReplacingMatches(
                        in: redacted,
                        options: [],
                        range: range,
                        withTemplate: "[REDACTED_\(dataType.rawValue.uppercased().replacingOccurrences(of: " ", with: "_"))]"
                    )
                }
            }
        }
        
        return redacted
    }
    
    func shouldExcludeFile(_ path: String) -> Bool {
        let filename = (path as NSString).lastPathComponent.lowercased()
        let fullPath = path.lowercased()
        
        for pattern in settings.excludedPatterns {
            let lowercasePattern = pattern.lowercased()
            
            if lowercasePattern.hasPrefix("*") {
                // Wildcard at start
                let suffix = String(lowercasePattern.dropFirst())
                if filename.hasSuffix(suffix) || filename.contains(suffix.replacingOccurrences(of: "*", with: "")) {
                    return true
                }
            } else if lowercasePattern.hasSuffix("*") {
                // Wildcard at end
                let prefix = String(lowercasePattern.dropLast())
                if filename.hasPrefix(prefix) {
                    return true
                }
            } else if lowercasePattern.contains("*") {
                // Wildcard in middle - simple contains check
                let parts = lowercasePattern.components(separatedBy: "*")
                var matches = true
                var searchStart = fullPath.startIndex
                for part in parts where !part.isEmpty {
                    if let range = fullPath.range(of: part, range: searchStart..<fullPath.endIndex) {
                        searchStart = range.upperBound
                    } else {
                        matches = false
                        break
                    }
                }
                if matches { return true }
            } else {
                // Exact match
                if filename == lowercasePattern || filename.contains(lowercasePattern) {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Request Filtering
    
    func shouldAllowRequest(to url: URL) -> Bool {
        guard settings.isPrivacyModeEnabled else { return true }
        
        guard let host = url.host else { return false }
        
        // Allow local requests
        if host == "localhost" || host == "127.0.0.1" {
            return true
        }
        
        // Check trusted domains
        for domain in settings.trustedDomains {
            if host.hasSuffix(domain) {
                return !settings.useLocalModelsOnly
            }
        }
        
        return false
    }
    
    func prepareContextForAI(_ context: String, projectURL: URL?) -> String {
        var prepared = context
        
        // Redact if privacy mode is on
        if isPrivacyEnabled(for: projectURL) && settings.redactSensitiveData {
            prepared = redactSensitiveData(in: prepared)
        }
        
        return prepared
    }
    
    // MARK: - Persistence
    
    private static func loadSettings(from url: URL) -> PrivacySettings {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .default
        }
        
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PrivacySettings.self, from: data)
        } catch {
            print("PrivacyModeService: Failed to load settings: \(error)")
            return .default
        }
    }
    
    private func saveSettings() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL)
        } catch {
            print("PrivacyModeService: Failed to save settings: \(error)")
        }
    }
    
    // MARK: - Privacy Report
    
    func generatePrivacyReport(for projectURL: URL) async -> String {
        let detections = await scanProject(projectURL)
        
        var report = "# Privacy Report\n\n"
        report += "**Project:** \(projectURL.lastPathComponent)\n"
        report += "**Date:** \(Date().formatted())\n\n"
        
        report += "## Privacy Mode Status\n\n"
        report += "- Privacy Mode: \(isPrivacyEnabled(for: projectURL) ? "ENABLED" : "Disabled")\n"
        report += "- Local Models Only: \(settings.useLocalModelsOnly ? "Yes" : "No")\n"
        report += "- Telemetry: \(settings.disableTelemetry ? "Disabled" : "Enabled")\n"
        report += "- Code Sharing: \(settings.disableCodeSharing ? "Disabled" : "Enabled")\n\n"
        
        report += "## Sensitive Data Detected\n\n"
        
        if detections.isEmpty {
            report += "No sensitive data detected.\n"
        } else {
            report += "Found \(detections.count) potential sensitive data items:\n\n"
            
            let byType = Dictionary(grouping: detections) { $0.type }
            for (type, items) in byType.sorted(by: { $0.value.count > $1.value.count }) {
                report += "### \(type.rawValue) (\(items.count))\n\n"
                for item in items.prefix(5) {
                    report += "- `\(item.file):\(item.line)`\n"
                }
                if items.count > 5 {
                    report += "- ... and \(items.count - 5) more\n"
                }
                report += "\n"
            }
        }
        
        report += "## Recommendations\n\n"
        if !detections.isEmpty {
            report += "1. Review detected sensitive data and move to environment variables\n"
            report += "2. Add sensitive files to .gitignore and .lingcodeignore\n"
            report += "3. Enable Privacy Mode for this project\n"
        } else {
            report += "- No immediate actions required\n"
        }
        
        return report
    }
}
