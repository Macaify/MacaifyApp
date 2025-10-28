import Foundation
import Moya

public final class TitlesAPI {
    private let config: ServiceConfig
    private let provider: MoyaProvider<TitlesTarget>
    private let decoder = JSONDecoder()

    public init(config: ServiceConfig) {
        self.config = config
        if let session = config.afSession {
            self.provider = MoyaProvider<TitlesTarget>(session: session)
        } else {
            self.provider = MoyaProvider<TitlesTarget>()
        }
    }

    /// Generate a chat title from either messages or plain text.
    /// - Parameters:
    ///   - messages: Optional two-turn messages (e.g., system + user) or last few turns.
    ///   - text: Optional plain text; ignored when `messages` is present.
    ///   - maxLen: Preferred max title length; server default is 30.
    ///   - authHeader: Optional Authorization header (e.g., "Bearer ...").
    /// - Returns: Title string on success.
    public func generateChatTitle(
        messages: [TitleMessage]? = nil,
        text: String? = nil,
        maxLen: Int = 30,
        authHeader: String? = nil
    ) async throws -> String {
        let payload = TitleRequest(messages: messages, text: text, maxLen: maxLen)
        let target = TitlesTarget.generate(baseURL: config.baseURL, payload: payload, authHeader: authHeader)
        let response: Moya.Response = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Moya.Response, Error>) in
            provider.request(target) { result in
                switch result {
                case .success(let resp): cont.resume(returning: resp)
                case .failure(let err): cont.resume(throwing: err)
                }
            }
        }
        guard (200...299).contains(response.statusCode) else {
            let urlStr = response.request?.url?.absoluteString ?? "<unknown>"
            let bodyStr = String(data: response.data, encoding: .utf8) ?? "<non-utf8>"
            let snippet = bodyStr.count > 600 ? String(bodyStr.prefix(600)) + "…" : bodyStr
            print("[TitlesAPI] HTTP \(response.statusCode) url=\(urlStr) body=\(snippet)")
            throw APIError.httpStatus(response.statusCode)
        }
        let decoded = try decoder.decode(TitleResponse.self, from: response.data)
        guard decoded.success, let t = decoded.data?.title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let raw = String(data: response.data, encoding: .utf8) ?? "<non-utf8>"
            print("[TitlesAPI] Decode failure body=\(raw)")
            throw APIError.decoding(NSError(domain: "TitlesAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: decoded.error ?? "Invalid title response"]))
        }
        return t
    }

    // Intentionally no cookie handling: auth is expected via Bearer
}
