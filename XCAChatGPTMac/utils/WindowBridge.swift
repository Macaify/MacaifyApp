import Foundation
import AppKit

final class WindowBridge {
    static let shared = WindowBridge()
    private init() {}
    var openMainWindow: (() -> Void)? = nil
    weak var mainWindow: NSWindow? = nil
    var openingMain: Bool = false
}
