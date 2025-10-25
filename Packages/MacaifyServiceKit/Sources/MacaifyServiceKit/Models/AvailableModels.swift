import Foundation

// MARK: - Public DTOs matching backend schema

public struct AvailableModelsResponse: Codable, Equatable {
    public let success: Bool
    public let data: AvailableModelsData
}

public struct AvailableModelsData: Codable, Equatable {
    public let providers: [String]
    public let models: [ModelInfo]
}

public enum Plan: String, Codable, CaseIterable, Equatable {
    case free = "Free"
    case pro = "Pro"
    case proPlus = "Pro+"

    public static func from(_ raw: String) -> Plan? {
        switch raw {
        case Plan.free.rawValue: return .free
        case Plan.pro.rawValue: return .pro
        case Plan.proPlus.rawValue: return .proPlus
        default: return nil
        }
    }
}

public enum Mode: String, Codable, Equatable {
    case effective
    case exact
}

public struct ModelInfo: Codable, Equatable {
    public let id: String
    public let name: String
    public let description: String?
    public let provider: String
    public let slug: String
    public let recommended: Bool?
    public let context: ContextInfo?
    public let modalities: Modalities?
    public let features: Features?
    public let supportedParameters: [String]?
    public let pricingPerMillion: Pricing?
    public let thinking: Bool?
    public let scores: Scores?
    public let plans: [Plan]?
}

public struct ContextInfo: Codable, Equatable {
    public let tokens: Int?
    public let words: Int?
    public let pages: Int?
}

public struct Modalities: Codable, Equatable {
    public let input: [String]?
    public let output: [String]?
}

public struct Features: Codable, Equatable {
    public let webSearch: Bool?
    public let tools: Bool?
    public let reasoning: Bool?

    enum CodingKeys: String, CodingKey {
        case webSearch = "web_search"
        case tools
        case reasoning
    }
}

public struct Pricing: Codable, Equatable {
    public let prompt: Int?
    public let completion: Int?
}

public struct Scores: Codable, Equatable {
    public let speed: Int?
    public let intelligence: Int?
}
