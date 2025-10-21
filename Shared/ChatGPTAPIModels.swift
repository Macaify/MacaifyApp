//
//  ChatGPTAPIModels.swift
//  XCAChatGPT
//
//  Created by Alfian Losari on 03/03/23.
//

import Foundation

struct Message: Codable {
    let role: String
    let content: String
}

extension Array where Element == Message {
    
    var contentCount: Int { reduce(0, { $0 + $1.content.count })}
}

struct Request: Codable {
    let model: String
    let temperature: Double
    let messages: [Message]
    let stream: Bool
}

struct ErrorRootResponse: Decodable {
    let error: ErrorResponse
}

struct ErrorContext: Decodable {
    let current_plan: String?
    let required_plan: String?
    let model_id: String?
    let alternatives: [String]?
    let upgrade_url: String?
}

// Fallback shape when backend returns {"success": false, "error": "...", ...}
struct ErrorStringRootResponse: Decodable {
    let success: Bool?
    let error: String
}

struct ErrorResponse: Decodable {
    let code: String?
    let message: String
    let type: String?
    let context: ErrorContext?
}

struct StreamCompletionResponse: Decodable {
    let choices: [StreamChoice]
}

struct CompletionResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?
}

struct Usage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
}

struct Choice: Decodable {
    let message: Message
    let finishReason: String?
}

struct StreamChoice: Decodable {
    let finishReason: String?
    let delta: StreamMessage
}

struct StreamMessage: Decodable {
    let role: String?
    let content: String?
}
