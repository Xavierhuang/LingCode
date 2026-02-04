//
//  DeploymentModels.swift
//  LingCode
//
//  Models for deployment targets, configurations, and results
//

import Foundation

// MARK: - Deployment Target

enum DeploymentPlatform: String, Codable, CaseIterable, Identifiable {
    case vercel = "Vercel"
    case netlify = "Netlify"
    case railway = "Railway"
    case fly = "Fly.io"
    case heroku = "Heroku"
    case docker = "Docker (Local)"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .vercel: return "v.circle.fill"
        case .netlify: return "n.circle.fill"
        case .railway: return "tram.fill"
        case .fly: return "airplane"
        case .heroku: return "h.circle.fill"
        case .docker: return "shippingbox.fill"
        case .custom: return "terminal.fill"
        }
    }
    
    var cliCommand: String? {
        switch self {
        case .vercel: return "vercel"
        case .netlify: return "netlify"
        case .railway: return "railway"
        case .fly: return "fly"
        case .heroku: return "heroku"
        case .docker: return "docker"
        case .custom: return nil
        }
    }
    
    var installInstructions: String {
        switch self {
        case .vercel: return "npm i -g vercel"
        case .netlify: return "npm i -g netlify-cli"
        case .railway: return "npm i -g @railway/cli"
        case .fly: return "brew install flyctl"
        case .heroku: return "brew tap heroku/brew && brew install heroku"
        case .docker: return "brew install --cask docker"
        case .custom: return ""
        }
    }
}

// MARK: - Deployment Configuration

struct DeploymentConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var platform: DeploymentPlatform
    var name: String
    var branch: String
    var buildCommand: String?
    var outputDirectory: String?
    var environment: DeploymentEnvironment
    var environmentVariables: [String: String]
    var preDeployCommands: [String]
    var postDeployCommands: [String]
    var customDeployCommand: String?
    var autoDetected: Bool
    
    init(
        id: UUID = UUID(),
        platform: DeploymentPlatform,
        name: String = "",
        branch: String = "main",
        buildCommand: String? = nil,
        outputDirectory: String? = nil,
        environment: DeploymentEnvironment = .production,
        environmentVariables: [String: String] = [:],
        preDeployCommands: [String] = [],
        postDeployCommands: [String] = [],
        customDeployCommand: String? = nil,
        autoDetected: Bool = false
    ) {
        self.id = id
        self.platform = platform
        self.name = name.isEmpty ? platform.rawValue : name
        self.branch = branch
        self.buildCommand = buildCommand
        self.outputDirectory = outputDirectory
        self.environment = environment
        self.environmentVariables = environmentVariables
        self.preDeployCommands = preDeployCommands
        self.postDeployCommands = postDeployCommands
        self.customDeployCommand = customDeployCommand
        self.autoDetected = autoDetected
    }
}

enum DeploymentEnvironment: String, Codable, CaseIterable {
    case development = "development"
    case staging = "staging"
    case preview = "preview"
    case production = "production"
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var color: String {
        switch self {
        case .development: return "gray"
        case .staging: return "orange"
        case .preview: return "blue"
        case .production: return "green"
        }
    }
}

// MARK: - Deployment Status

enum DeploymentStatus: Equatable {
    case idle
    case validating
    case runningTests
    case building
    case deploying
    case success(url: String?)
    case failed(error: String)
    case cancelled
    
    var isInProgress: Bool {
        switch self {
        case .validating, .runningTests, .building, .deploying:
            return true
        default:
            return false
        }
    }
    
    var displayText: String {
        switch self {
        case .idle: return "Ready to deploy"
        case .validating: return "Validating..."
        case .runningTests: return "Running tests..."
        case .building: return "Building..."
        case .deploying: return "Deploying..."
        case .success(let url):
            if let url = url {
                return "Deployed: \(url)"
            }
            return "Deployment successful"
        case .failed(let error): return "Failed: \(error)"
        case .cancelled: return "Deployment cancelled"
        }
    }
    
    var icon: String {
        switch self {
        case .idle: return "cloud.fill"
        case .validating: return "checkmark.shield"
        case .runningTests: return "testtube.2"
        case .building: return "hammer.fill"
        case .deploying: return "arrow.up.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }
}

// MARK: - Validation Result

struct DeploymentValidationResult {
    var testsPass: Bool
    var buildSucceeds: Bool
    var envVarsValid: Bool
    var cliAvailable: Bool
    var errors: [String]
    var warnings: [String]
    
    var isValid: Bool {
        testsPass && buildSucceeds && envVarsValid && cliAvailable && errors.isEmpty
    }
    
    static var empty: DeploymentValidationResult {
        DeploymentValidationResult(
            testsPass: false,
            buildSucceeds: false,
            envVarsValid: false,
            cliAvailable: false,
            errors: [],
            warnings: []
        )
    }
}

// MARK: - Deployment Result

struct DeploymentResult: Identifiable {
    let id: UUID
    let config: DeploymentConfig
    let status: DeploymentStatus
    let url: String?
    let buildLogs: String
    let deployLogs: String
    let startTime: Date
    let endTime: Date?
    let duration: TimeInterval?
    
    init(
        id: UUID = UUID(),
        config: DeploymentConfig,
        status: DeploymentStatus,
        url: String? = nil,
        buildLogs: String = "",
        deployLogs: String = "",
        startTime: Date = Date(),
        endTime: Date? = nil
    ) {
        self.id = id
        self.config = config
        self.status = status
        self.url = url
        self.buildLogs = buildLogs
        self.deployLogs = deployLogs
        self.startTime = startTime
        self.endTime = endTime
        self.duration = endTime.map { $0.timeIntervalSince(startTime) }
    }
}

// MARK: - Deployment History Entry

struct DeploymentHistoryEntry: Identifiable, Codable {
    let id: UUID
    let platform: DeploymentPlatform
    let environment: DeploymentEnvironment
    let branch: String
    let commitHash: String?
    let commitMessage: String?
    let url: String?
    let success: Bool
    let errorMessage: String?
    let timestamp: Date
    let duration: TimeInterval?
    
    init(
        id: UUID = UUID(),
        platform: DeploymentPlatform,
        environment: DeploymentEnvironment,
        branch: String,
        commitHash: String? = nil,
        commitMessage: String? = nil,
        url: String? = nil,
        success: Bool,
        errorMessage: String? = nil,
        timestamp: Date = Date(),
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.platform = platform
        self.environment = environment
        self.branch = branch
        self.commitHash = commitHash
        self.commitMessage = commitMessage
        self.url = url
        self.success = success
        self.errorMessage = errorMessage
        self.timestamp = timestamp
        self.duration = duration
    }
}

// MARK: - Project Type Detection

enum ProjectType: String {
    case nextjs = "Next.js"
    case react = "React"
    case vue = "Vue"
    case nuxt = "Nuxt"
    case svelte = "Svelte"
    case nodejs = "Node.js"
    case python = "Python"
    case rust = "Rust"
    case go = "Go"
    case swift = "Swift"
    case staticSite = "Static Site"
    case unknown = "Unknown"
    
    var defaultBuildCommand: String? {
        switch self {
        case .nextjs, .react, .vue, .nuxt, .svelte: return "npm run build"
        case .nodejs: return nil
        case .python: return nil
        case .rust: return "cargo build --release"
        case .go: return "go build"
        case .swift: return "swift build -c release"
        case .staticSite, .unknown: return nil
        }
    }
    
    var defaultOutputDirectory: String? {
        switch self {
        case .nextjs: return ".next"
        case .react: return "build"
        case .vue: return "dist"
        case .nuxt: return ".output"
        case .svelte: return "build"
        case .rust: return "target/release"
        case .go: return "."
        case .swift: return ".build/release"
        default: return nil
        }
    }
    
    var recommendedPlatforms: [DeploymentPlatform] {
        switch self {
        case .nextjs: return [.vercel, .netlify, .railway]
        case .react, .vue, .svelte, .staticSite: return [.vercel, .netlify]
        case .nuxt: return [.vercel, .netlify, .railway]
        case .nodejs, .python: return [.railway, .fly, .heroku]
        case .rust, .go: return [.fly, .railway, .docker]
        case .swift: return [.docker, .fly]
        case .unknown: return DeploymentPlatform.allCases
        }
    }
}
