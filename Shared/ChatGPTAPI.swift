//
//  ChatGPTAPI.swift
//  XCAChatGPT
//
//  Created by Alfian Losari on 01/02/23.
//

import Foundation
import GPTEncoder
import OpenAI
#if canImport(BetterAuth)
import BetterAuth
#endif

class ChatGPTAPI: @unchecked Sendable {
    
    private let gptEncoder = GPTEncoder()
    private var systemMessage: Message {
        // gemini-1.0-pro aka gemini-pro 不支持 role: system
        .init(role: model == "gemini-pro" || model == "gemini-1.0-pro" ? "user" : "system", content: systemPrompt)
    }
    private let temperature: Double
    private let maxToken: Int
    private let model: String
    
    private let apiKey: String
    private var historyList = [Message]()
    // 携带上下文
    var withContext: Bool
    
    private var PORTKEY_BASE_URL = "https://aigateway.macaify.com"
    // 对于账户网关与 OpenAI 官方，默认包含 "/v1"，以便路径统一改为 "/chat/completions"
    private let ACCOUNT_GATEWAY_BASE_URL = "http://localhost:3000/api/ai/v1"

    private var baseURL: String
    private var useAccountGateway: Bool
    private var realBaseURL: String {
        // provider 是 openai，走 openai 或 baseURL
        // baseURL 为空或 provider 不是 openai，走 portkey
        if useAccountGateway {
            return ACCOUNT_GATEWAY_BASE_URL
        } else if provider == "openai" {
            // 官方默认附带 /v1；自定义 Base URL 不再强制拼接 /v1（由用户自行填写）
            return baseURL.isEmpty ? "https://api.openai.com/v1" : baseURL
        } else {
            return PORTKEY_BASE_URL
        }
    }
    private let urlSession = URLSession.shared
    
    var systemPrompt: String
    
    let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "YYYY-MM-dd"
        return df
    }()
    
    private let jsonDecoder: JSONDecoder = {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return jsonDecoder
    }()
    
    private var provider: String
    
    enum ChatAPIError: LocalizedError {
        case notLoggedIn
        case unauthorized
        case forbidden
        case tooManyRequests
        case invalidResponse
        case serverError(code: Int, message: String)
        case planNotAllowed(model: String?, currentPlan: String?, requiredPlan: String?)
        case quotaExceeded(currentPlan: String?)
        case trialExpired
        case accountAuthUnavailable
        case network(error: Error)

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:
                return String(localized: "error_not_logged_in_go_to_settings")
            case .unauthorized:
                return String(localized: "error_unauthorized")
            case .forbidden:
                return String(localized: "error_forbidden")
            case .tooManyRequests:
                return String(localized: "error_too_many_requests")
            case .invalidResponse:
                return String(localized: "error_invalid_response")
            case let .serverError(code, message):
                return String(format: String(localized: "server_error_format"), String(code), message)
            case let .planNotAllowed(model, current, required):
                var text = String(localized: "plan_not_allowed")
                if let current { text += String(format: String(localized: "plan_current_suffix_format"), current) }
                if let model { text += String(format: String(localized: "plan_model_suffix_format"), model) }
                if let required { text += String(format: String(localized: "plan_required_suffix_format"), required) }
                return text
            case let .quotaExceeded(current):
                if let current { return String(format: String(localized: "quota_exceeded_with_plan"), current) }
                return String(localized: "quota_exceeded")
            case .trialExpired:
                return String(localized: "trial_expired")
            case .accountAuthUnavailable:
                return String(localized: "account_auth_unavailable")
            case let .network(error):
                return error.localizedDescription
            }
        }
    }

    private func mapServerError(status: Int, code: String?, message: String, context: ErrorContext?) -> ChatAPIError {
        if let code = code {
            switch code {
            case "membership.plan_not_allowed":
                return .planNotAllowed(model: context?.model_id, currentPlan: context?.current_plan, requiredPlan: context?.required_plan)
            case "membership.quota_exceeded":
                return .quotaExceeded(currentPlan: context?.current_plan)
            case "membership.trial_expired":
                return .trialExpired
            case "auth.not_logged_in":
                return .notLoggedIn
            case "auth.unauthorized":
                return .unauthorized
            case "rate.limited":
                return .tooManyRequests
            default:
                break
            }
        }
        // Fallback by status
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 429: return .tooManyRequests
        default: return .serverError(code: status, message: message)
        }
    }

    private func buildHeaders() async throws -> [String: String] {
        if useAccountGateway {
            // Bearer from BetterAuth TokenAuth (if available)
            #if canImport(BetterAuth)
            let bearer = await TokenAuth.shared.getAuthorizationHeader() ?? ""
            guard !bearer.isEmpty else { throw ChatAPIError.notLoggedIn }
            #else
            throw ChatAPIError.accountAuthUnavailable
            #endif
            return [
                "Content-Type": "application/json",
                "Authorization": bearer
            ]
        } else {
            return [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(apiKey)",
                "x-portkey-provider": provider,
                "x-portkey-custom-host": baseURL
            ]
        }
    }
    
    // MARK: - paw/openai
    // Build a client with dynamic headers (Bearer may come from TokenAuth)
    private func buildOpenAI() async throws -> OpenAI {
        let headers = try await buildHeaders()
        let cfg = OpenAI.Configuration(
            token: useAccountGateway ? "" : apiKey,
            baseURL: realBaseURL,
            headers: headers
        )
        return OpenAI(configuration: cfg)
    }
    
    private var lastTask: URLSessionDataTask? = nil

    init(apiKey: String, model: String = "gpt-4o-mini", provider: String = "openai", maxToken: Int, systemPrompt: String = "You are a helpful assistant", temperature: Double = 0, baseURL: String = "", withContext: Bool = true, useAccountGateway: Bool = false) {
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxToken = maxToken
        self.withContext = withContext
        self.provider = provider
        self.baseURL = baseURL
        self.useAccountGateway = useAccountGateway
    }
    
    func disableProxy() {
    }
    
    func useProxy(proxy: String) {
    }
    
    var history: [Message] {
        get {
            historyList
        }
        set(newValue) {
            historyList.removeAll()
            historyList.append(contentsOf: newValue)
        }
    }
    
    private func generateMessages(from text: String) -> [Message] {
        var messages: [Message] = []
        if !systemPrompt.isEmpty {
            messages += [systemMessage]
        }
        if withContext {
            messages += historyList
        }
        messages += [Message(role: "user", content: text)]
        
        let token =  messages.token
//        print("msg token \(token) \(messages)")
        if token > maxToken {
            if withContext && !historyList.isEmpty {
                _ = historyList.removeFirst()
                messages = generateMessages(from: text)
            } else {
//                let lastIndex = max(1, text.count - 100)
                let start = text.index(text.startIndex, offsetBy: 0)
                let end = text.index(text.startIndex, offsetBy: max(0, text.count - 100))
                messages = generateMessages(from: String(text[start...end]))
            }
        }
        return messages
    }
    
    private func jsonBody(text: String, stream: Bool = true) throws -> Data {
        let msgs = generateMessages(from: text)
        print("messages","withContext \(withContext)", msgs)
        let request = Request(model: model, temperature: temperature,
                              messages: msgs, stream: stream)
        return try JSONEncoder().encode(request)
    }
    
    // Extract pure JSON string from a line that may start with custom prefix like "jsonData "
    private func sanitizeJSONText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("jsonData ") {
            return String(trimmed.dropFirst("jsonData ".count))
        }
        return trimmed
    }
    
    private func appendToHistoryList(userText: String, responseText: String) {
        self.historyList.append(.init(role: "user", content: userText))
        self.historyList.append(.init(role: "assistant", content: responseText))
    }
    
    func chatsStream(text: String) async throws -> AsyncThrowingStream<ChatStreamResult, Error> {
        // Build request
        let url = URL(string: "\(realBaseURL)/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        let headers = try await buildHeaders()
        headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        urlRequest.httpBody = try jsonBody(text: text)

        // Start stream
        let (result, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (result, response) = try await urlSession.bytes(for: urlRequest)
        } catch {
            throw ChatAPIError.network(error: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAPIError.invalidResponse
        }
        // Non-2xx: collect payload and map structured error
        guard 200...299 ~= httpResponse.statusCode else {
            var raw = ""
            for try await line in result.lines { raw += line }
            raw = sanitizeJSONText(raw)
            var message = ""
            var code: String? = nil
            var ctx: ErrorContext? = nil
            if let data = raw.data(using: .utf8), let er = try? jsonDecoder.decode(ErrorRootResponse.self, from: data) {
                message = er.error.message
                code = er.error.code
                ctx = er.error.context
            } else if let data = raw.data(using: .utf8), let er2 = try? jsonDecoder.decode(ErrorStringRootResponse.self, from: data) {
                message = er2.error
            } else {
                message = raw
            }
            throw mapServerError(status: httpResponse.statusCode, code: code, message: message, context: ctx)
        }

        // 2xx: parse SSE
        return AsyncThrowingStream<ChatStreamResult, Error> { continuation in
            Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                do {
                    var responseText = ""
                    var firstNonEmptySeen = false
                    var sseErrorMode = false
                    for try await raw in result.lines {
                        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !line.isEmpty else { continue }
                        if !firstNonEmptySeen {
                            firstNonEmptySeen = true
                            // If plain JSON returned mistakenly
                            if line.hasPrefix("{") || line.hasPrefix("jsonData ") {
                                let body = sanitizeJSONText(line)
                                if let data = body.data(using: .utf8) {
                                    if let er = try? self.jsonDecoder.decode(ErrorRootResponse.self, from: data) {
                                        throw self.mapServerError(status: 200, code: er.error.code, message: er.error.message, context: er.error.context)
                                    } else if let er2 = try? self.jsonDecoder.decode(ErrorStringRootResponse.self, from: data) {
                                        throw self.mapServerError(status: 200, code: nil, message: er2.error, context: nil)
                                    }
                                }
                                throw ChatAPIError.invalidResponse
                            }
                        }
                        if line.hasPrefix("event:") && line.contains("error") { sseErrorMode = true; continue }
                        if sseErrorMode, line.hasPrefix("data: ") {
                            let body = sanitizeJSONText(String(line.dropFirst(6)))
                            if let data = body.data(using: .utf8) {
                                if let er = try? self.jsonDecoder.decode(ErrorRootResponse.self, from: data) {
                                    throw self.mapServerError(status: 200, code: er.error.code, message: er.error.message, context: er.error.context)
                                } else if let er2 = try? self.jsonDecoder.decode(ErrorStringRootResponse.self, from: data) {
                                    throw self.mapServerError(status: 200, code: nil, message: er2.error, context: nil)
                                }
                            }
                            throw ChatAPIError.invalidResponse
                        }
                        if line.hasPrefix("data: ") {
                            let body = String(line.dropFirst(6))
                            if let data = body.data(using: .utf8), let chunk = try? self.jsonDecoder.decode(ChatStreamResult.self, from: data) {
                                if let delta = chunk.choices.first?.delta.content, !delta.isEmpty { responseText += delta }
                                continuation.yield(chunk)
                            }
                        }
                    }
                    self.appendToHistoryList(userText: text, responseText: responseText)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func sendMessageStream(text: String) async throws -> AsyncThrowingStream<String, Error> {
        print("send message stream", model, text)
        let url = URL(string: "\(realBaseURL)/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        let headers = try await buildHeaders()
        headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        urlRequest.httpBody = try jsonBody(text: text)
        print("urlRequest", urlRequest, headers, urlRequest.httpBody.map { String(decoding: $0, as: UTF8.self) })

        let (result, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (result, response) = try await urlSession.bytes(for: urlRequest)
        } catch {
            throw ChatAPIError.network(error: error)
        }
        lastTask = result.task
        
        print(result, response)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAPIError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            var raw = ""
            for try await line in result.lines { raw += line }
            raw = sanitizeJSONText(raw)
            var message = raw
            var code: String? = nil
            var ctx: ErrorContext? = nil
            if let data = raw.data(using: .utf8), let er = try? jsonDecoder.decode(ErrorRootResponse.self, from: data) {
                message = er.error.message
                code = er.error.code
                ctx = er.error.context
            } else if let data = raw.data(using: .utf8), let er2 = try? jsonDecoder.decode(ErrorStringRootResponse.self, from: data) {
                message = er2.error
            }
            lastTask = nil
            throw mapServerError(status: httpResponse.statusCode, code: code, message: message, context: ctx)
        }
        
        return AsyncThrowingStream<String, Error> { continuation in
            Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                do {
                    var responseText = ""
                    var firstNonEmptySeen = false
                    var sseErrorMode = false
                    for try await raw in result.lines {
                        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !line.isEmpty else { continue }
                        if !firstNonEmptySeen {
                            firstNonEmptySeen = true
                            // If the server returned plain JSON instead of SSE
                            if line.hasPrefix("{") {
                                if let data = line.data(using: .utf8) {
                                    if let er = try? self.jsonDecoder.decode(ErrorRootResponse.self, from: data) {
                                        throw self.mapServerError(status: 200, code: er.error.code, message: er.error.message, context: er.error.context)
                                    } else if let er2 = try? self.jsonDecoder.decode(ErrorStringRootResponse.self, from: data) {
                                        throw self.mapServerError(status: 200, code: nil, message: er2.error, context: nil)
                                    }
                                }
                                throw ChatAPIError.invalidResponse
                            }
                        }
                        if line.hasPrefix("event:") && line.contains("error") {
                            sseErrorMode = true
                            continue
                        }
                        if sseErrorMode, line.hasPrefix("data: ") {
                            let body = String(line.dropFirst(6))
                            if let data = body.data(using: .utf8) {
                                if let er = try? self.jsonDecoder.decode(ErrorRootResponse.self, from: data) {
                                    throw self.mapServerError(status: 200, code: er.error.code, message: er.error.message, context: er.error.context)
                                } else if let er2 = try? self.jsonDecoder.decode(ErrorStringRootResponse.self, from: data) {
                                    throw self.mapServerError(status: 200, code: nil, message: er2.error, context: nil)
                                }
                            }
                            throw ChatAPIError.invalidResponse
                        }
                        if line.hasPrefix("data: "),
                           let data = line.dropFirst(6).data(using: .utf8),
                           let response = try? self.jsonDecoder.decode(StreamCompletionResponse.self, from: data),
                           let text = response.choices.first?.delta.content {
                            responseText += text
                            continuation.yield(text)
                        }
                    }
                    self.appendToHistoryList(userText: text, responseText: responseText)
                    lastTask = nil
                    continuation.finish()
                } catch {
                    lastTask = nil
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func sendMessage(_ text: String) async throws -> String {
        let url = URL(string: "\(realBaseURL)/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        let headers = try await buildHeaders()
        headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        urlRequest.httpBody = try jsonBody(text: text, stream: false)
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch {
            throw ChatAPIError.network(error: error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAPIError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            var message = ""
            var code: String? = nil
            var ctx: ErrorContext? = nil
            if let er = try? jsonDecoder.decode(ErrorRootResponse.self, from: data) {
                message = er.error.message
                code = er.error.code
                ctx = er.error.context
            } else if let er2 = try? jsonDecoder.decode(ErrorStringRootResponse.self, from: data) {
                message = er2.error
            }
            // As a last resort, look into headers
            if code == nil, let hdr = (response as? HTTPURLResponse)?.allHeaderFields {
                if let c = hdr["X-Error-Code"] as? String { code = c }
            }
            throw mapServerError(status: httpResponse.statusCode, code: code, message: message, context: ctx)
        }
        
        do {
            let completionResponse = try self.jsonDecoder.decode(CompletionResponse.self, from: data)
            let responseText = completionResponse.choices.first?.message.content ?? ""
            self.appendToHistoryList(userText: text, responseText: responseText)
            return responseText
        } catch {
            throw error
        }
    }
    
    func deleteHistoryList() {
        self.historyList.removeAll()
    }
    
    func interupt() {
        lastTask?.cancel()
        lastTask = nil
    }
}

extension String: CustomNSError {
    
    public var errorUserInfo: [String : Any] {
        [
            NSLocalizedDescriptionKey: self
        ]
    }
}
