//
//  ErrorHandlingService.swift
//  LingCode
//
//  Better error messages with actionable suggestions
//

import Foundation

/// Service for providing user-friendly error messages
class ErrorHandlingService {
    static let shared = ErrorHandlingService()
    
    private init() {}
    
    /// Convert error to user-friendly message with actionable suggestions
    func userFriendlyError(_ error: Error) -> (message: String, suggestion: String?) {
        let nsError = error as NSError
        let domain = nsError.domain
        let code = nsError.code
        
        // API Errors
        if domain == "AIService" {
            switch code {
            case 401:
                return (
                    message: "API key is invalid or missing",
                    suggestion: "Please check your API key in Settings (Cmd+,) and make sure it's correct."
                )
            case 402, 429:
                return (
                    message: "API rate limit exceeded",
                    suggestion: "You've hit the rate limit. Please wait a moment and try again, or upgrade your API plan."
                )
            case 500...599:
                return (
                    message: "AI service is temporarily unavailable",
                    suggestion: "The AI service is experiencing issues. Please try again in a few moments."
                )
            default:
                return (
                    message: "Failed to connect to AI service",
                    suggestion: "Check your internet connection and API key settings."
                )
            }
        }
        
        // File System Errors
        if domain == NSCocoaErrorDomain {
            switch code {
            case NSFileReadNoSuchFileError:
                return (
                    message: "File not found",
                    suggestion: "The file may have been moved or deleted. Please check the file path."
                )
            case NSFileWriteFileExistsError:
                return (
                    message: "File already exists",
                    suggestion: "A file with this name already exists. Choose a different name or delete the existing file first."
                )
            case NSFileWriteNoPermissionError:
                return (
                    message: "Permission denied",
                    suggestion: "You don't have permission to write to this location. Check file permissions or choose a different location."
                )
            default:
                return (
                    message: "File operation failed",
                    suggestion: "An error occurred while accessing the file. Please try again."
                )
            }
        }
        
        // Network Errors
        if domain == NSURLErrorDomain {
            switch code {
            case NSURLErrorNotConnectedToInternet:
                return (
                    message: "No internet connection",
                    suggestion: "Please check your internet connection and try again."
                )
            case NSURLErrorTimedOut:
                return (
                    message: "Request timed out",
                    suggestion: "The request took too long. Please check your connection and try again."
                )
            case NSURLErrorCannotFindHost:
                return (
                    message: "Cannot reach server",
                    suggestion: "Unable to connect to the server. Please check your internet connection."
                )
            default:
                return (
                    message: "Network error occurred",
                    suggestion: "A network error occurred. Please check your connection and try again."
                )
            }
        }
        
        // Generic error
        let errorMessage = error.localizedDescription.isEmpty 
            ? "An unexpected error occurred" 
            : error.localizedDescription
        
        return (
            message: errorMessage,
            suggestion: "Please try again. If the problem persists, check the error details."
        )
    }
    
    /// Format error for display in UI
    func formatError(_ error: Error) -> String {
        let (message, suggestion) = userFriendlyError(error)
        
        if let suggestion = suggestion {
            return "\(message)\n\n💡 \(suggestion)"
        }
        
        return message
    }
}







