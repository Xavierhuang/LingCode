//
//  WebSearchService.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import Foundation
import Combine

/// Service for web search to provide context to AI
class WebSearchService: ObservableObject {
    static let shared = WebSearchService()
    
    @Published var isSearching: Bool = false
    @Published var lastSearchResults: [WebSearchResult] = []
    
    private init() {}
    
    // MARK: - Search Methods
    
    /// Search the web using DuckDuckGo Instant Answer API (no API key required)
    func search(
        query: String,
        maxResults: Int = 5,
        onComplete: @escaping ([WebSearchResult]) -> Void
    ) {
        guard !query.isEmpty else {
            onComplete([])
            return
        }
        
        isSearching = true
        
        // Use DuckDuckGo Instant Answer API
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.duckduckgo.com/?q=\(encodedQuery)&format=json&no_html=1&skip_disambig=1"
        
        guard let url = URL(string: urlString) else {
            isSearching = false
            onComplete([])
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("LingCode/1.0", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer {
                DispatchQueue.main.async {
                    self.isSearching = false
                }
            }
            
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    onComplete([])
                }
                return
            }
            
            do {
                let results = try self.parseDuckDuckGoResponse(data, maxResults: maxResults)
                DispatchQueue.main.async {
                    self.lastSearchResults = results
                    onComplete(results)
                }
            } catch {
                print("Failed to parse search results: \(error)")
                DispatchQueue.main.async {
                    onComplete([])
                }
            }
        }.resume()
    }
    
    /// Search using Google Custom Search API (requires API key)
    func searchGoogle(
        query: String,
        apiKey: String,
        searchEngineId: String,
        maxResults: Int = 5,
        onComplete: @escaping ([WebSearchResult]) -> Void
    ) {
        guard !query.isEmpty else {
            onComplete([])
            return
        }
        
        isSearching = true
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://www.googleapis.com/customsearch/v1?key=\(apiKey)&cx=\(searchEngineId)&q=\(encodedQuery)&num=\(maxResults)"
        
        guard let url = URL(string: urlString) else {
            isSearching = false
            onComplete([])
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            defer {
                DispatchQueue.main.async {
                    self.isSearching = false
                }
            }
            
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    onComplete([])
                }
                return
            }
            
            do {
                let results = try self.parseGoogleResponse(data)
                DispatchQueue.main.async {
                    self.lastSearchResults = results
                    onComplete(results)
                }
            } catch {
                print("Failed to parse Google results: \(error)")
                DispatchQueue.main.async {
                    onComplete([])
                }
            }
        }.resume()
    }
    
    /// Fetch content from a URL
    func fetchContent(from url: URL, onComplete: @escaping (String?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("LingCode/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil,
                  let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    onComplete(nil)
                }
                return
            }
            
            // Extract text content from HTML
            let text = self.extractTextFromHTML(html)
            
            DispatchQueue.main.async {
                onComplete(text)
            }
        }.resume()
    }
    
    // MARK: - Context Building
    
    /// Build context string from search results
    func buildContext(from results: [WebSearchResult], maxLength: Int = 4000) -> String {
        guard !results.isEmpty else {
            return ""
        }
        
        var context = "## Web Search Results\n\n"
        var currentLength = context.count
        
        for (index, result) in results.enumerated() {
            let resultText = """
            ### \(index + 1). \(result.title)
            Source: \(result.url)
            \(result.snippet)
            
            """
            
            if currentLength + resultText.count > maxLength {
                break
            }
            
            context += resultText
            currentLength += resultText.count
        }
        
        return context
    }
    
    /// Search and build context in one call
    func searchAndBuildContext(
        query: String,
        maxResults: Int = 5,
        maxLength: Int = 4000,
        onComplete: @escaping (String) -> Void
    ) {
        search(query: query, maxResults: maxResults) { results in
            let context = self.buildContext(from: results, maxLength: maxLength)
            onComplete(context)
        }
    }
    
    // MARK: - Parsing
    
    private func parseDuckDuckGoResponse(_ data: Data, maxResults: Int) throws -> [WebSearchResult] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        
        var results: [WebSearchResult] = []
        
        // Abstract (main answer)
        if let abstract = json["Abstract"] as? String, !abstract.isEmpty,
           let abstractURL = json["AbstractURL"] as? String, !abstractURL.isEmpty,
           let abstractSource = json["AbstractSource"] as? String {
            results.append(WebSearchResult(
                title: abstractSource,
                url: abstractURL,
                snippet: abstract
            ))
        }
        
        // Related Topics
        if let relatedTopics = json["RelatedTopics"] as? [[String: Any]] {
            for topic in relatedTopics.prefix(maxResults - results.count) {
                if let text = topic["Text"] as? String,
                   let firstURL = topic["FirstURL"] as? String {
                    let title = text.components(separatedBy: " - ").first ?? text
                    results.append(WebSearchResult(
                        title: String(title.prefix(100)),
                        url: firstURL,
                        snippet: text
                    ))
                }
            }
        }
        
        // Results (if available)
        if let searchResults = json["Results"] as? [[String: Any]] {
            for result in searchResults.prefix(maxResults - results.count) {
                if let text = result["Text"] as? String,
                   let firstURL = result["FirstURL"] as? String {
                    results.append(WebSearchResult(
                        title: String(text.prefix(100)),
                        url: firstURL,
                        snippet: text
                    ))
                }
            }
        }
        
        return results
    }
    
    private func parseGoogleResponse(_ data: Data) throws -> [WebSearchResult] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }
        
        var results: [WebSearchResult] = []
        
        for item in items {
            if let title = item["title"] as? String,
               let link = item["link"] as? String,
               let snippet = item["snippet"] as? String {
                results.append(WebSearchResult(
                    title: title,
                    url: link,
                    snippet: snippet
                ))
            }
        }
        
        return results
    }
    
    private func extractTextFromHTML(_ html: String) -> String {
        // Simple HTML tag removal
        var text = html
        
        // Remove script and style tags with content
        let scriptPattern = #"<script[^>]*>[\s\S]*?</script>"#
        let stylePattern = #"<style[^>]*>[\s\S]*?</style>"#
        
        if let scriptRegex = try? NSRegularExpression(pattern: scriptPattern, options: .caseInsensitive) {
            text = scriptRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        
        if let styleRegex = try? NSRegularExpression(pattern: stylePattern, options: .caseInsensitive) {
            text = styleRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        
        // Remove all HTML tags
        let tagPattern = #"<[^>]+>"#
        if let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: []) {
            text = tagRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        
        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        
        // Clean up whitespace
        let whitespacePattern = #"\s+"#
        if let wsRegex = try? NSRegularExpression(pattern: whitespacePattern, options: []) {
            text = wsRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Supporting Types

struct WebSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let url: String
    let snippet: String
    
    var displayURL: String {
        guard let urlObj = URL(string: url) else { return url }
        return urlObj.host ?? url
    }
}

