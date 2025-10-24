import Foundation
import Moya

final class ETagRequestPlugin: PluginType {
    private let cache: ResponseCache
    private let enabled: Bool

    init(cache: ResponseCache, enabled: Bool) {
        self.cache = cache
        self.enabled = enabled
    }

    func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        guard enabled, let url = request.url?.absoluteString else { return request }
        if let etag = cache.loadEntry(for: url)?.etag, !etag.isEmpty {
            var r = request
            r.addValue(etag, forHTTPHeaderField: "If-None-Match")
            return r
        }
        return request
    }
}

