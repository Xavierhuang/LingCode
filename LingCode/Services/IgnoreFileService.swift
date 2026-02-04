//
//  IgnoreFileService.swift
//  LingCode
//
//  .lingcodeignore / .cursorignore support for excluding files from AI context
//

import Foundation
import Combine

// MARK: - Ignore Pattern

struct IgnorePattern {
    let pattern: String
    let isNegation: Bool  // Patterns starting with ! include rather than exclude
    let isDirectory: Bool // Patterns ending with / match only directories
    let regex: NSRegularExpression?
    
    init(pattern: String) {
        var cleanPattern = pattern.trimmingCharacters(in: .whitespaces)
        
        // Check for negation
        self.isNegation = cleanPattern.hasPrefix("!")
        if isNegation {
            cleanPattern = String(cleanPattern.dropFirst())
        }
        
        // Check for directory-only
        self.isDirectory = cleanPattern.hasSuffix("/")
        if isDirectory {
            cleanPattern = String(cleanPattern.dropLast())
        }
        
        self.pattern = cleanPattern
        
        // Convert glob to regex
        self.regex = IgnorePattern.globToRegex(cleanPattern)
    }
    
    func matches(path: String, isDirectory: Bool) -> Bool {
        // Directory-only patterns don't match files
        if self.isDirectory && !isDirectory {
            return false
        }
        
        guard let regex = regex else {
            // Fallback to simple contains check
            return path.contains(pattern)
        }
        
        let range = NSRange(path.startIndex..., in: path)
        return regex.firstMatch(in: path, options: [], range: range) != nil
    }
    
    private static func globToRegex(_ glob: String) -> NSRegularExpression? {
        var regexPattern = "^"
        var i = glob.startIndex
        
        while i < glob.endIndex {
            let c = glob[i]
            
            switch c {
            case "*":
                let next = glob.index(after: i)
                if next < glob.endIndex && glob[next] == "*" {
                    // ** matches anything including /
                    regexPattern += ".*"
                    i = next
                } else {
                    // * matches anything except /
                    regexPattern += "[^/]*"
                }
                
            case "?":
                regexPattern += "[^/]"
                
            case "[":
                // Character class
                var j = glob.index(after: i)
                var charClass = "["
                while j < glob.endIndex && glob[j] != "]" {
                    charClass += String(glob[j])
                    j = glob.index(after: j)
                }
                if j < glob.endIndex {
                    charClass += "]"
                    regexPattern += charClass
                    i = j
                } else {
                    regexPattern += "\\["
                }
                
            case ".":
                regexPattern += "\\."
                
            case "/":
                regexPattern += "/"
                
            default:
                // Escape special regex characters
                if "^$+{}|()\\".contains(c) {
                    regexPattern += "\\"
                }
                regexPattern += String(c)
            }
            
            i = glob.index(after: i)
        }
        
        // If pattern doesn't start with /, it can match anywhere
        if !glob.hasPrefix("/") {
            regexPattern = "(^|/)" + regexPattern.dropFirst() // Remove the ^ we added
        }
        
        regexPattern += "(/.*)?$"  // Match the path or any child
        
        return try? NSRegularExpression(pattern: regexPattern, options: [])
    }
}

// MARK: - Ignore File Service

class IgnoreFileService: ObservableObject {
    static let shared = IgnoreFileService()
    
    @Published var patterns: [IgnorePattern] = []
    @Published var isLoaded: Bool = false
    
    /// Files that are always ignored regardless of ignore files
    private let defaultIgnorePatterns: [String] = [
        // Dependencies
        "node_modules/",
        ".npm/",
        "vendor/",
        "Pods/",
        ".bundle/",
        
        // Build outputs
        "build/",
        "dist/",
        "out/",
        ".build/",
        "DerivedData/",
        "*.xcarchive",
        
        // IDE/Editor
        ".idea/",
        ".vscode/",
        "*.swp",
        "*.swo",
        "*~",
        ".DS_Store",
        "Thumbs.db",
        
        // Version control
        ".git/",
        ".svn/",
        ".hg/",
        
        // Logs and caches
        "*.log",
        ".cache/",
        "__pycache__/",
        "*.pyc",
        ".pytest_cache/",
        
        // Environment and secrets
        ".env",
        ".env.local",
        ".env.*.local",
        "*.pem",
        "*.key",
        "credentials.json",
        "secrets.yaml",
        
        // Large binary files
        "*.zip",
        "*.tar",
        "*.gz",
        "*.rar",
        "*.7z",
        "*.dmg",
        "*.iso",
        "*.exe",
        "*.dll",
        "*.so",
        "*.dylib",
        
        // Media files (usually not needed for context)
        "*.mp3",
        "*.mp4",
        "*.wav",
        "*.avi",
        "*.mov",
        "*.mkv",
        
        // Lock files (can be large)
        "package-lock.json",
        "yarn.lock",
        "Podfile.lock",
        "Gemfile.lock",
        "composer.lock"
    ]
    
    private init() {
        // Load default patterns
        for pattern in defaultIgnorePatterns {
            patterns.append(IgnorePattern(pattern: pattern))
        }
    }
    
    // MARK: - Loading
    
    /// Load ignore patterns from project directory
    func loadIgnoreFile(from projectURL: URL) {
        var allPatterns: [IgnorePattern] = []
        
        // Add default patterns
        for pattern in defaultIgnorePatterns {
            allPatterns.append(IgnorePattern(pattern: pattern))
        }
        
        // Check for .lingcodeignore
        let lingcodeIgnoreURL = projectURL.appendingPathComponent(".lingcodeignore")
        if let content = try? String(contentsOf: lingcodeIgnoreURL, encoding: .utf8) {
            let filePatterns = parseIgnoreFile(content)
            allPatterns.append(contentsOf: filePatterns)
        }
        
        // Check for .cursorignore (Cursor compatibility)
        let cursorIgnoreURL = projectURL.appendingPathComponent(".cursorignore")
        if let content = try? String(contentsOf: cursorIgnoreURL, encoding: .utf8) {
            let filePatterns = parseIgnoreFile(content)
            allPatterns.append(contentsOf: filePatterns)
        }
        
        // Check for .gitignore (optional, lower priority)
        let gitIgnoreURL = projectURL.appendingPathComponent(".gitignore")
        if let content = try? String(contentsOf: gitIgnoreURL, encoding: .utf8) {
            let filePatterns = parseIgnoreFile(content)
            allPatterns.append(contentsOf: filePatterns)
        }
        
        patterns = allPatterns
        isLoaded = true
    }
    
    private func parseIgnoreFile(_ content: String) -> [IgnorePattern] {
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { IgnorePattern(pattern: $0) }
    }
    
    // MARK: - Checking
    
    /// Check if a file should be ignored
    func shouldIgnore(path: String, isDirectory: Bool = false) -> Bool {
        // Normalize path
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        
        var ignored = false
        
        for pattern in patterns {
            if pattern.matches(path: normalizedPath, isDirectory: isDirectory) {
                ignored = !pattern.isNegation
            }
        }
        
        return ignored
    }
    
    /// Check if a URL should be ignored
    func shouldIgnore(url: URL, relativeTo baseURL: URL) -> Bool {
        let relativePath = url.path.replacingOccurrences(of: baseURL.path + "/", with: "")
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return shouldIgnore(path: relativePath, isDirectory: exists && isDir.boolValue)
    }
    
    /// Filter a list of files, removing ignored ones
    func filterIgnored(files: [URL], relativeTo baseURL: URL) -> [URL] {
        return files.filter { !shouldIgnore(url: $0, relativeTo: baseURL) }
    }
    
    /// Filter a list of paths, removing ignored ones
    func filterIgnored(paths: [String]) -> [String] {
        return paths.filter { !shouldIgnore(path: $0) }
    }
    
    // MARK: - Pattern Management
    
    /// Add a custom ignore pattern
    func addPattern(_ pattern: String) {
        let ignorePattern = IgnorePattern(pattern: pattern)
        patterns.append(ignorePattern)
    }
    
    /// Remove a pattern
    func removePattern(_ pattern: String) {
        patterns.removeAll { $0.pattern == pattern }
    }
    
    /// Save current patterns to .lingcodeignore
    func saveIgnoreFile(to projectURL: URL) {
        let customPatterns = patterns
            .filter { !defaultIgnorePatterns.contains($0.pattern) }
            .map { pattern -> String in
                var line = ""
                if pattern.isNegation { line += "!" }
                line += pattern.pattern
                if pattern.isDirectory { line += "/" }
                return line
            }
        
        guard !customPatterns.isEmpty else { return }
        
        let content = """
        # LingCode Ignore File
        # Files and directories listed here will be excluded from AI context
        # Syntax is similar to .gitignore
        
        \(customPatterns.joined(separator: "\n"))
        """
        
        let ignoreURL = projectURL.appendingPathComponent(".lingcodeignore")
        try? content.write(to: ignoreURL, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Utility
    
    /// Get a description of why a file is ignored
    func getIgnoreReason(for path: String) -> String? {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        
        for pattern in patterns {
            if pattern.matches(path: normalizedPath, isDirectory: false) && !pattern.isNegation {
                return "Matched pattern: \(pattern.pattern)"
            }
        }
        
        return nil
    }
    
    /// Check if a file is in a sensitive category
    func isSensitiveFile(path: String) -> Bool {
        let sensitivePatterns = [
            ".env",
            "credentials",
            "secrets",
            ".pem",
            ".key",
            "password",
            "token",
            "apikey",
            "api_key"
        ]
        
        let lowercasePath = path.lowercased()
        return sensitivePatterns.contains { lowercasePath.contains($0) }
    }
    
    /// Get all currently ignored directories
    func getIgnoredDirectories() -> [String] {
        return patterns
            .filter { $0.isDirectory && !$0.isNegation }
            .map { $0.pattern }
    }
    
    /// Get all file extensions being ignored
    func getIgnoredExtensions() -> [String] {
        return patterns
            .filter { $0.pattern.hasPrefix("*.") && !$0.isNegation }
            .map { String($0.pattern.dropFirst(2)) }
    }
}

// MARK: - Convenience Extensions

extension IgnoreFileService {
    /// Quick check for common large/binary files
    func isLikelyBinaryOrLarge(filename: String) -> Bool {
        let binaryExtensions = Set([
            // Executables
            "exe", "dll", "so", "dylib", "a", "o", "obj",
            // Archives
            "zip", "tar", "gz", "rar", "7z", "bz2", "xz",
            // Images
            "png", "jpg", "jpeg", "gif", "bmp", "ico", "webp", "tiff", "psd",
            // Videos
            "mp4", "avi", "mov", "mkv", "wmv", "flv", "webm",
            // Audio
            "mp3", "wav", "flac", "aac", "ogg", "m4a",
            // Documents (binary)
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            // Databases
            "db", "sqlite", "sqlite3",
            // Other
            "dmg", "iso", "pkg", "deb", "rpm"
        ])
        
        let ext = (filename as NSString).pathExtension.lowercased()
        return binaryExtensions.contains(ext)
    }
    
    /// Check if file is likely a lock file
    func isLockFile(filename: String) -> Bool {
        let lockFiles = Set([
            "package-lock.json",
            "yarn.lock",
            "pnpm-lock.yaml",
            "Podfile.lock",
            "Gemfile.lock",
            "composer.lock",
            "Cargo.lock",
            "poetry.lock",
            "go.sum"
        ])
        
        return lockFiles.contains(filename)
    }
}
