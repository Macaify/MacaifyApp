import Foundation

public enum APIError: Error, LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case decoding(Error)
    case network(Error)
    case emptyCache

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpStatus(let code): return "HTTP error: \(code)"
        case .decoding(let err): return "Decoding error: \(err.localizedDescription)"
        case .network(let err): return "Network error: \(err.localizedDescription)"
        case .emptyCache: return "Cached data unavailable"
        }
    }
}
