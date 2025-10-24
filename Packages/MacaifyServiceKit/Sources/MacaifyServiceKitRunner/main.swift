import Foundation
import Alamofire
import MacaifyServiceKit

@main
struct Runner {
    static func main() async {
        let args = CommandLine.arguments
        var base = "https://localhost:3000"
        var plan: Plan? = nil
        var mode: Mode = .effective
        var provider: String? = nil
        var query: String? = nil

        func readArg(_ key: String) -> String? {
            if let idx = args.firstIndex(of: key), args.count > idx + 1 { return args[idx + 1] }
            return nil
        }

        if let b = readArg("--base") { base = b }
        if let p = readArg("--plan"), let pl = Plan.from(p) { plan = pl }
        if let m = readArg("--mode"), let md = Mode(rawValue: m) { mode = md }
        if let pr = readArg("--provider") { provider = pr }
        if let q = readArg("--q") { query = q }

        guard let baseURL = URL(string: base) else {
            fputs("Invalid --base URL\n", stderr)
            exit(2)
        }

        // Allow self-signed for localhost only
        let trust = ServerTrustManager(evaluators: ["localhost": DisabledTrustEvaluator()])
        let session = Alamofire.Session(configuration: .default, serverTrustManager: trust)

        let config = ServiceConfig(
            baseURL: baseURL,
            session: URLSession(configuration: .default),
            cacheDirectory: nil,
            cacheTTL: 60 * 60,
            enableETag: true,
            allowStaleOnError: true,
            dateProvider: SystemDateProvider(),
            afSession: session
        )

        let api = ModelsAPI(config: config)

        do {
            let data = try await api.fetchAvailableModels(plan: plan, mode: mode, provider: provider, q: query)
            print("success: true")
            print("providers: \(data.providers)")
            print("models count: \(data.models.count)")
            if let first = data.models.first {
                print("first: \(first.id) - \(first.name)")
            }
        } catch {
            fputs("Request failed: \(error)\n", stderr)
            exit(1)
        }
    }
}

