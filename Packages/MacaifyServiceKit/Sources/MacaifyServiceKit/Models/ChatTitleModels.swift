import Foundation

// MARK: - Request/Response models for /api/chat/title

public struct TitleMessage: Codable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct TitleRequest: Encodable, Equatable {
    public let messages: [TitleMessage]?
    public let text: String?
    public let maxLen: Int?

    public init(messages: [TitleMessage]? = nil, text: String? = nil, maxLen: Int? = nil) {
        self.messages = messages
        self.text = text
        self.maxLen = maxLen
    }
}

public struct TitleResponse: Decodable, Equatable {
    public let success: Bool
    public let data: TitleData?
    public let error: String?
}

public struct TitleData: Decodable, Equatable { public let title: String? }

