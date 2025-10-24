import XCTest
import Alamofire
@testable import MacaifyServiceKit

final class ModelsAPITests: XCTestCase {
    private func makeAFSession() -> Alamofire.Session {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return Alamofire.Session(configuration: config)
    }

    private func makeConfig(baseURL: URL, afSession: Alamofire.Session, ttl: TimeInterval = 3600, date: Date = Date()) -> ServiceConfig {
        struct FixedDate: DateProviding { let fixed: Date; var now: Date { fixed } }
        return ServiceConfig(
            baseURL: baseURL,
            session: URLSession(configuration: .ephemeral),
            cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("MacaifyServiceKitTests-\(UUID().uuidString)", isDirectory: true),
            cacheTTL: ttl,
            enableETag: true,
            allowStaleOnError: true,
            dateProvider: FixedDate(fixed: date),
            afSession: afSession
        )
    }

    private let sampleJSON: String = {
        return """
        {"success":true,"data":{"providers":["anthropic","openai"],"models":[{"id":"anthropic/claude-3.5-sonnet","name":"Anthropic: Claude 3.5 Sonnet","description":"...","provider":"anthropic","slug":"claude-3.5-sonnet","context":{"tokens":1000000,"words":750000,"pages":1500},"modalities":{"input":["text","image"],"output":["text"]},"features":{"web_search":false,"tools":true,"reasoning":true},"supportedParameters":["tools","tool_choice","reasoning"],"pricingPerMillion":{"prompt":3000,"completion":15000},"thinking":true,"scores":{"speed":4,"intelligence":5},"plans":["Pro","Pro+"]}]}}
        """
    }()

    func testDecodingSuccess() async throws {
        let baseURL = URL(string: "https://example.com")!
        let af = makeAFSession()
        let config = makeConfig(baseURL: baseURL, afSession: af)
        let api = ModelsAPI(config: config)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, self.sampleJSON.data(using: .utf8))
        }

        let data = try await api.fetchAvailableModels()
        XCTAssertEqual(data.providers, ["anthropic", "openai"])
        XCTAssertEqual(data.models.count, 1)
        XCTAssertEqual(data.models.first?.id, "anthropic/claude-3.5-sonnet")
        XCTAssertEqual(data.models.first?.plans, [.pro, .proPlus])
    }

    func testQueryConstruction() async throws {
        let baseURL = URL(string: "https://api.example.com")!
        let af = makeAFSession()
        let config = makeConfig(baseURL: baseURL, afSession: af)
        let api = ModelsAPI(config: config)
        var capturedURL: URL?

        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, self.sampleJSON.data(using: .utf8))
        }

        _ = try await api.fetchAvailableModels(plan: .proPlus, mode: .exact, provider: "openai", q: "gpt")

        let comps = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)
        let dict = Dictionary(uniqueKeysWithValues: (comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["plan"], "Pro+")
        XCTAssertEqual(dict["mode"], "exact")
        XCTAssertEqual(dict["provider"], "openai")
        XCTAssertEqual(dict["q"], "gpt")
    }

    func testCacheFallbackOnNetworkError() async throws {
        let baseURL = URL(string: "https://example.com")!
        let af = makeAFSession()
        var date = Date()
        struct MutableDateProvider: DateProviding { var ref: () -> Date; var now: Date { ref() } }
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("MacaifyServiceKitTests-\(UUID().uuidString)", isDirectory: true)
        let config = ServiceConfig(
            baseURL: baseURL,
            session: URLSession(configuration: .ephemeral),
            cacheDirectory: cacheDir,
            cacheTTL: 3600,
            enableETag: true,
            allowStaleOnError: true,
            dateProvider: MutableDateProvider(ref: { date }),
            afSession: af
        )
        let api = ModelsAPI(config: config)

        var call = 0
        MockURLProtocol.requestHandler = { request in
            call += 1
            if call == 1 {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, self.sampleJSON.data(using: .utf8))
            } else {
                throw URLError(.notConnectedToInternet)
            }
        }

        let first = try await api.fetchAvailableModels()
        XCTAssertEqual(first.models.count, 1)

        // advance time a bit (still within TTL)
        date.addTimeInterval(120)
        let second = try await api.fetchAvailableModels()
        XCTAssertEqual(second.models.count, 1)
        XCTAssertGreaterThan(call, 1) // second attempt hit network and failed, then returned cache
    }

    func testETag304ServesCached() async throws {
        let baseURL = URL(string: "https://etag.example.com")!
        let af = makeAFSession()
        let config = makeConfig(baseURL: baseURL, afSession: af)
        let api = ModelsAPI(config: config)

        var etag = "\"v1\""
        var seenIfNoneMatch: String?
        var call = 0

        MockURLProtocol.requestHandler = { request in
            call += 1
            if call == 1 {
                let headers = ["ETag": etag]
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
                return (response, self.sampleJSON.data(using: .utf8))
            } else {
                seenIfNoneMatch = request.value(forHTTPHeaderField: "If-None-Match")
                let response = HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!
                return (response, nil)
            }
        }

        _ = try await api.fetchAvailableModels()
        let second = try await api.fetchAvailableModels()
        XCTAssertEqual(second.models.count, 1)
        XCTAssertEqual(seenIfNoneMatch, etag)
    }

    func testTTLExpiryForcesRefresh() async throws {
        let baseURL = URL(string: "https://ttl.example.com")!
        let af = makeAFSession()
        var date = Date()
        struct MutableDateProvider: DateProviding { var ref: () -> Date; var now: Date { ref() } }
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("MacaifyServiceKitTests-\(UUID().uuidString)", isDirectory: true)
        let config = ServiceConfig(
            baseURL: baseURL,
            session: URLSession(configuration: .ephemeral),
            cacheDirectory: cacheDir,
            cacheTTL: 60, // 1 minute TTL
            enableETag: false,
            allowStaleOnError: false,
            dateProvider: MutableDateProvider(ref: { date }),
            afSession: af
        )
        let api = ModelsAPI(config: config)

        let jsonV1 = sampleJSON
        let jsonV2 = """
        {"success":true,"data":{"providers":["openai"],"models":[{"id":"openai/gpt-4o-mini","name":"OpenAI: GPT-4o mini","description":"...","provider":"openai","slug":"gpt-4o-mini","plans":["Free","Pro"]}]}}
        """

        var call = 0
        MockURLProtocol.requestHandler = { request in
            call += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, (call == 1 ? jsonV1 : jsonV2).data(using: .utf8))
        }

        let first = try await api.fetchAvailableModels()
        XCTAssertEqual(first.models.first?.id, "anthropic/claude-3.5-sonnet")

        // move time beyond TTL so cachedAvailableModelsIfFresh returns nil
        date.addTimeInterval(61)
        let second = try await api.fetchAvailableModels()
        XCTAssertEqual(second.models.first?.id, "openai/gpt-4o-mini")
        XCTAssertEqual(call, 2)
    }
}
