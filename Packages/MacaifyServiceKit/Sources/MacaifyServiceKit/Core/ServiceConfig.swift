import Foundation
import Alamofire

public struct ServiceConfig {
    public enum DefaultMode: String { case effective, exact }

    public let baseURL: URL
    public let session: URLSession
    public let afSession: Session?
    public let cacheDirectory: URL
    public let cacheTTL: TimeInterval
    public let enableETag: Bool
    public let allowStaleOnError: Bool
    public let dateProvider: DateProviding

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        cacheDirectory: URL? = nil,
        cacheTTL: TimeInterval = 60 * 60 * 12, // 12 hours
        enableETag: Bool = true,
        allowStaleOnError: Bool = true,
        dateProvider: DateProviding = SystemDateProvider(),
        afSession: Session? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.afSession = afSession
        if let dir = cacheDirectory {
            self.cacheDirectory = dir
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheDirectory = caches.appendingPathComponent("MacaifyServiceKit", isDirectory: true)
        }
        self.cacheTTL = cacheTTL
        self.enableETag = enableETag
        self.allowStaleOnError = allowStaleOnError
        self.dateProvider = dateProvider
    }
}
