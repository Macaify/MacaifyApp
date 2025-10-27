import Foundation

enum LaunchAtLoginManager {
    private static var label: String {
        let base = Bundle.main.bundleIdentifier ?? "com.macaify.chatgpt"
        return base + ".launchagent"
    }

    private static var agentsFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private static var plistURL: URL { agentsFolderURL.appendingPathComponent(label + ".plist") }

    static var isEnabled: Bool {
        (try? plistURL.checkResourceIsReachable()) ?? false
    }

    static func set(enabled: Bool) {
        if enabled {
            do { try enable() } catch { /* ignore */ }
        } else {
            do { try disable() } catch { /* ignore */ }
        }
    }

    private static func enable() throws {
        guard let execURL = Bundle.main.executableURL else { return }
        try FileManager.default.createDirectory(at: agentsFolderURL, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "Label": label,
            "ProgramArguments": [execURL.path],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
        // Try to bootstrap immediately (macOS 10.13+). Ignore errors; will launch on next login.
        _ = run(["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    private static func disable() throws {
        // Attempt to unload first; ignore errors.
        _ = run(["bootout", "gui/\(getuid())", label])
        try? FileManager.default.removeItem(at: plistURL)
    }

    @discardableResult
    private static func run(_ args: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        do { try task.run(); task.waitUntilExit(); return task.terminationStatus } catch { return -1 }
    }
}

