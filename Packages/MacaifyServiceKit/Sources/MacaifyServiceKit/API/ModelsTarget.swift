import Foundation
import Moya

enum ModelsTarget {
    case available(baseURL: URL, plan: Plan?, mode: Mode, provider: String?, q: String?)
}

extension ModelsTarget: TargetType {
    var baseURL: URL {
        switch self {
        case .available(let base, _, _, _, _):
            return base
        }
    }

    var path: String {
        switch self {
        case .available:
            return "/api/public/models/available"
        }
    }

    var method: Moya.Method { .get }

    var task: Task {
        switch self {
        case .available(_, let plan, let mode, let provider, let q):
            var params: [String: Any] = ["mode": mode.rawValue]
            if let plan { params["plan"] = plan.rawValue }
            if let provider, !provider.isEmpty { params["provider"] = provider }
            if let q, !q.isEmpty { params["q"] = q }
            return .requestParameters(parameters: params, encoding: URLEncoding.queryString)
        }
    }

    var headers: [String : String]? {
        ["Accept": "application/json"]
    }
}

