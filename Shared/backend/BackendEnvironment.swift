import Foundation

public enum BackendEnvironment {
    /// Optional runtime override via UserDefaults for quick local testing.
    /// Set with: defaults write <bundle> BackendBaseURLOverride "http://localhost:3000"
    private static let overrideKey = "BackendBaseURLOverride"

    public static var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: overrideKey), let url = URL(string: override) {
            return url
        }
#if DEBUG
        return URL(string: "http://localhost:3000")!
#else
        return URL(string: "https://macaify.com")!
#endif
    }
}

