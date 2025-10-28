import Foundation
import BetterAuth

/// Simple StorageProtocol implementation backed by UserDefaults (no Keychain).
final class PlainStorage: StorageProtocol {
    private let ud = UserDefaults.standard
    private let prefix = "betterauth.storage."

    func get(key: String) -> String? {
        ud.string(forKey: prefix + key)
    }

    @discardableResult
    func save(key: String, value: String) throws -> Bool {
        ud.set(value, forKey: prefix + key)
        return true
    }
}

