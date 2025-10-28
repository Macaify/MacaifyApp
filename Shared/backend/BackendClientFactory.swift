import Foundation

#if canImport(MacaifyServiceKit)
import MacaifyServiceKit
import Alamofire

public enum BackendClientFactory {
    public static func makeModelsAPI() -> ModelsAPI {
        let base = BackendEnvironment.baseURL
        // In Debug, if host is localhost, allow self-signed.
        let trust: ServerTrustManager?
        if base.host == "localhost" {
            trust = ServerTrustManager(evaluators: ["localhost": DisabledTrustEvaluator()])
        } else {
            trust = nil
        }
        let af = Alamofire.Session(configuration: .default, serverTrustManager: trust)
        let config = ServiceConfig(
            baseURL: base,
            session: URLSession(configuration: .default),
            cacheDirectory: nil,
            cacheTTL: 60 * 60 * 12,
            enableETag: true,
            allowStaleOnError: true,
            dateProvider: SystemDateProvider(),
            afSession: af
        )
        return ModelsAPI(config: config)
    }

    public static func makeTitlesAPI() -> TitlesAPI {
        let base = BackendEnvironment.baseURL
        let trust: ServerTrustManager?
        if base.host == "localhost" {
            trust = ServerTrustManager(evaluators: ["localhost": DisabledTrustEvaluator()])
        } else {
            trust = nil
        }
        let af = Alamofire.Session(configuration: .default, serverTrustManager: trust)
        let config = ServiceConfig(
            baseURL: base,
            session: URLSession(configuration: .default),
            cacheDirectory: nil,
            cacheTTL: 0,
            enableETag: false,
            allowStaleOnError: false,
            dateProvider: SystemDateProvider(),
            afSession: af
        )
        return TitlesAPI(config: config)
    }
}

#else
// Fallback shim so app builds even if MacaifyServiceKit isn't linked yet.
public enum BackendClientFactory {}
#endif
