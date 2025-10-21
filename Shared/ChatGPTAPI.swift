//
//  ChatGPTAPI.swift
//  XCAChatGPT
//
//  Created by Alfian Losari on 01/02/23.
//

import Foundation
import GPTEncoder
import OpenAI

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

    private var baseURL: String
    private var realBaseURL: String {
        // provider 是 openai，走 openai 或 baseURL
        // baseURL 为空或 provider 不是 openai，走 portkey
        if provider == "openai" {
            baseURL.isEmpty ? "https://api.openai.com" : baseURL
        } else {
            PORTKEY_BASE_URL
        }
    }
    private let urlSession = URLSession.shared
    private var urlRequest: URLRequest {
        get {
            let url = URL(string: "\(realBaseURL)/v1/chat/completions")!
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            headers.forEach {  urlRequest.setValue($1, forHTTPHeaderField: $0) }
            return urlRequest
        }
    }
    
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
    
    private var headers: [String: String] {
        [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(apiKey)",
            "x-portkey-provider": provider,
            "x-portkey-custom-host": baseURL
        ]
    }
    
    // MARK: - paw/openai
    private var configuration: OpenAI.Configuration {
        .init(token: apiKey, baseURL: realBaseURL, headers: headers)
    }
    
    var openai: OpenAI {
        return OpenAI(configuration: configuration)
    }
    
    private var lastTask: URLSessionDataTask? = nil

    init(apiKey: String, model: String = "gpt-4o-mini", provider: String = "openai", maxToken: Int, systemPrompt: String = "You are a helpful assistant", temperature: Double = 0, baseURL: String = "", withContext: Bool = true) {
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxToken = maxToken
        self.withContext = withContext
        self.provider = provider
        self.baseURL = baseURL
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
    
    private func appendToHistoryList(userText: String, responseText: String) {
        self.historyList.append(.init(role: "user", content: userText))
        self.historyList.append(.init(role: "assistant", content: responseText))
    }
    
    func chatsStream(text: String) async throws -> AsyncThrowingStream<ChatStreamResult, Error> {
        let msgs = generateMessages(from: text).map {
            ChatQuery.ChatCompletionMessageParam(role: .init(rawValue: $0.role) ?? .user, content: $0.content)!
        }

        let upstream: AsyncThrowingStream<ChatStreamResult, Error> = openai.chatsStream(query: .init(messages: msgs, model: model, temperature: 0.5, stream: true))

        // Wrap upstream to accumulate content and persist history when finished
        return AsyncThrowingStream<ChatStreamResult, Error> { continuation in
            Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                do {
                    var responseText = ""
                    for try await chunk in upstream {
                        if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
                            responseText += delta
                        }
                        continuation.yield(chunk)
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
        var urlRequest = self.urlRequest
        urlRequest.httpBody = try jsonBody(text: text)
        print("urlRequest", urlRequest, headers, urlRequest.httpBody.map { String(decoding: $0, as: UTF8.self) })

        let (result, response) = try await urlSession.bytes(for: urlRequest)
        lastTask = result.task
        
        print(result, response)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw "Invalid response"
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            var errorText = ""
            for try await line in result.lines {
                errorText += line
            }
            
            if let data = errorText.data(using: .utf8), let errorResponse = try? jsonDecoder.decode(ErrorRootResponse.self, from: data).error {
                errorText = "\n\(errorResponse.message)"
            }
            
            lastTask = nil
            throw "Bad Response: \(httpResponse.statusCode), \(errorText)"
        }
        
        return AsyncThrowingStream<String, Error> { continuation in
            Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                do {
                    var responseText = ""
                    for try await line in result.lines {
                        if line.hasPrefix("data: "),
                           let data = line.dropFirst(6).data(using: .utf8),
                           let response = try? self.jsonDecoder.decode(StreamCompletionResponse.self, from: data),
                           let text = response.choices.first?.delta.content {
                            responseText += text
//                            print("text \(text)")
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
        var urlRequest = self.urlRequest
        urlRequest.httpBody = try jsonBody(text: text, stream: false)
        
        let (data, response) = try await urlSession.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw "Invalid response"
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            var error = "Bad Response: \(httpResponse.statusCode)"
            if let errorResponse = try? jsonDecoder.decode(ErrorRootResponse.self, from: data).error {
                error.append("\n\(errorResponse.message)")
            }
            throw error
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
