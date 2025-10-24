import Foundation
import CryptoKit

struct CacheEntry: Codable {
    let urlKey: String
    let timestamp: TimeInterval
    let etag: String?
    let data: Data
}

final class ResponseCache {
    private let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL) {
        self.directory = directory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func filename(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    func url(for key: String) -> URL { directory.appendingPathComponent(filename(for: key)).appendingPathExtension("json") }

    func loadEntry(for key: String) -> CacheEntry? {
        let url = url(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
    }

    func saveEntry(_ entry: CacheEntry, for key: String) {
        let url = url(for: key)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func clear(for key: String) {
        try? fileManager.removeItem(at: url(for: key))
    }
}

