import Foundation
import Moya

enum TitlesTarget {
    case generate(baseURL: URL, payload: TitleRequest, authHeader: String?)
}

extension TitlesTarget: TargetType {
    var baseURL: URL {
        switch self {
        case .generate(let base, _, _):
            return base
        }
    }

    var path: String { "/api/chat/title" }

    var method: Moya.Method { .post }

    var task: Task {
        switch self {
        case .generate(_, let payload, _):
            return .requestJSONEncodable(payload)
        }
    }

    var headers: [String : String]? {
        switch self {
        case .generate(_, _, let authHeader):
            var hdr: [String: String] = [
                "Accept": "application/json",
                "Content-Type": "application/json"
            ]
            if let authHeader, !authHeader.isEmpty {
                hdr["Authorization"] = authHeader
            }
            return hdr
        }
    }
}

