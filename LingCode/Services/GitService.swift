//
//  GitService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation

enum GitStatus {
    case clean
    case modified
    case added
    case deleted
    case untracked
}

struct GitFileStatus {
    let path: String
    let status: GitStatus
}

class GitService {
    static let shared = GitService()
    
    private init() {}
    
    func getStatus(for directory: URL) -> [GitFileStatus] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--porcelain"]
        process.currentDirectoryURL = directory
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }
            
            return parseGitStatus(output)
        } catch {
            return []
        }
    }
    
    func getDiff(for file: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", file.path]
        process.currentDirectoryURL = file.deletingLastPathComponent()
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    func isGitRepository(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let gitDir = url.appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    
    private func parseGitStatus(_ output: String) -> [GitFileStatus] {
        var results: [GitFileStatus] = []
        
        for line in output.components(separatedBy: .newlines) {
            guard line.count >= 3 else { continue }
            
            let index = line.index(line.startIndex, offsetBy: 2)
            let statusCode = String(line[..<index])
            let path = String(line[index...]).trimmingCharacters(in: .whitespaces)
            
            let status: GitStatus
            if statusCode.hasPrefix("??") {
                status = .untracked
            } else if statusCode.hasPrefix("D") {
                status = .deleted
            } else if statusCode.hasPrefix("A") {
                status = .added
            } else if statusCode.contains("M") {
                status = .modified
            } else {
                status = .clean
            }
            
            results.append(GitFileStatus(path: path, status: status))
        }
        
        return results
    }
}








