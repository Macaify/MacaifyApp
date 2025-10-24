import Foundation
import Moya

public final class ModelsAPI {
    private let config: ServiceConfig
    private let cache: ResponseCache
    private let decoder = JSONDecoder()
    private let provider: MoyaProvider<ModelsTarget>

    public init(config: ServiceConfig) {
        self.config = config
        self.cache = ResponseCache(directory: config.cacheDirectory)
        let etagPlugin = ETagRequestPlugin(cache: cache, enabled: config.enableETag)
        if let session = config.afSession {
            self.provider = MoyaProvider<ModelsTarget>(session: session, plugins: [etagPlugin])
        } else {
            self.provider = MoyaProvider<ModelsTarget>(plugins: [etagPlugin])
        }
    }

    // MARK: Public
    @discardableResult
    public func fetchAvailableModels(
        plan: Plan? = nil,
        mode: Mode = .effective,
        provider providerFilter: String? = nil,
        q: String? = nil
    ) async throws -> AvailableModelsData {
        let target = ModelsTarget.available(baseURL: config.baseURL, plan: plan, mode: mode, provider: providerFilter, q: q)
        do {
            let response = try await request(target)
            let urlString = response.response?.url?.absoluteString ?? target.baseURL.appendingPathComponent(target.path).absoluteString
            switch response.statusCode {
            case 200...299:
                do {
                    let decoded = try decoder.decode(AvailableModelsResponse.self, from: response.data)
                    let etag = response.response?.value(forHTTPHeaderField: "ETag") ?? response.response?.value(forHTTPHeaderField: "Etag")
                    let entry = CacheEntry(urlKey: urlString, timestamp: config.dateProvider.now.timeIntervalSince1970, etag: etag, data: response.data)
                    cache.saveEntry(entry, for: urlString)
                    return decoded.data
                } catch {
                    throw APIError.decoding(error)
                }
            case 304:
                if let entry = cache.loadEntry(for: urlString) {
                    let decoded = try decoder.decode(AvailableModelsResponse.self, from: entry.data)
                    return decoded.data
                } else {
                    throw APIError.emptyCache
                }
            default:
                if config.allowStaleOnError, let entry = cache.loadEntry(for: urlString) {
                    let decoded = try decoder.decode(AvailableModelsResponse.self, from: entry.data)
                    return decoded.data
                }
                throw APIError.httpStatus(response.statusCode)
            }
        } catch {
            // network-level failure
            let target = ModelsTarget.available(baseURL: config.baseURL, plan: plan, mode: mode, provider: providerFilter, q: q)
            let urlString = target.baseURL.appendingPathComponent(target.path).absoluteString + buildQueryString(plan: plan, mode: mode, provider: providerFilter, q: q)
            if config.allowStaleOnError, let entry = cache.loadEntry(for: urlString) {
                let decoded = try decoder.decode(AvailableModelsResponse.self, from: entry.data)
                return decoded.data
            }
            throw APIError.network(error)
        }
    }

    public func cachedAvailableModelsIfFresh(
        plan: Plan? = nil,
        mode: Mode = .effective,
        provider: String? = nil,
        q: String? = nil
    ) -> AvailableModelsData? {
        let key = cachedKey(plan: plan, mode: mode, provider: provider, q: q)
        guard let entry = cache.loadEntry(for: key) else { return nil }
        let age = config.dateProvider.now.timeIntervalSince1970 - entry.timestamp
        guard age <= config.cacheTTL else { return nil }
        return try? JSONDecoder().decode(AvailableModelsResponse.self, from: entry.data).data
    }

    // MARK: - Helpers
    private func request(_ target: ModelsTarget) async throws -> Moya.Response {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Moya.Response, Error>) in
            provider.request(target) { result in
                switch result {
                case .success(let response): cont.resume(returning: response)
                case .failure(let error): cont.resume(throwing: error)
                }
            }
        }
    }

    private func cachedKey(plan: Plan?, mode: Mode, provider: String?, q: String?) -> String {
        let base = config.baseURL.appendingPathComponent("/api/public/models/available").absoluteString
        return base + buildQueryString(plan: plan, mode: mode, provider: provider, q: q)
    }

    private func buildQueryString(plan: Plan?, mode: Mode, provider: String?, q: String?) -> String {
        var comps = URLComponents()
        comps.queryItems = [URLQueryItem(name: "mode", value: mode.rawValue)]
        if let plan { comps.queryItems?.append(URLQueryItem(name: "plan", value: plan.rawValue)) }
        if let provider, !provider.isEmpty { comps.queryItems?.append(URLQueryItem(name: "provider", value: provider)) }
        if let q, !q.isEmpty { comps.queryItems?.append(URLQueryItem(name: "q", value: q)) }
        let qstr = comps.url?.absoluteString ?? ""
        return qstr
    }
}
