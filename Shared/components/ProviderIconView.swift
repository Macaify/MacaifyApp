import SwiftUI

#if os(macOS)
import AppKit

// Lightweight SVG loader for small monochrome icons, with caching + fallback.
struct ProviderIconView: View {
    let provider: String
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let img = SVGIconCache.shared.image(for: provider) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Fallback: simple letter-in-circle
                ZStack {
                    Circle().fill(Color.gray.opacity(0.12))
                    Text(String(provider.prefix(1)).uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { SVGIconCache.shared.prewarm(bundle: .main) }
    }
}

final class SVGIconCache {
    static let shared = SVGIconCache()
    private var cache: [String: NSImage] = [:]
    private var prewarmed = false

    func prewarm(bundle: Bundle) {
        guard !prewarmed else { return }
        prewarmed = true
        // Nothing heavy; defer to on-demand loading
    }

    func image(for providerRaw: String) -> NSImage? {
        let key = providerKey(providerRaw)
        if let img = cache[key] { return img }
        guard let url = resourceURL(for: key) else { return nil }
        // Try AppKit's SVG image rep first
        if let reps = NSImageRep.imageReps(withContentsOf: url), let rep = reps.first {
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            cache[key] = image
            return image
        }
        // Fallback to NSImage (may fail for SVG on older systems)
        if let image = NSImage(contentsOf: url) {
            cache[key] = image
            return image
        }
        return nil
    }

    private func resourceURL(for key: String) -> URL? {
        let name = iconFilename(for: key)
        return Bundle.main.url(forResource: name, withExtension: "svg")
    }

    private func providerKey(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: " ", with: "")
    }

    private func iconFilename(for key: String) -> String {
        switch key {
        case "openai": return "openai"
        case "anthropic": return "anthropic"
        case "perplexity": return "perplexity"
        case "google": return "google"
        case "meta", "meta-llama", "llama": return "meta"
        case "mistral", "mistralai": return "mistral"
        case "moonshot", "moonshotai": return "moonshot"
        case "qwen", "alibaba": return "qwen"
        case "deepseek": return "deepseek"
        case "x-ai", "xai": return "xai"
        case "raycast": return "raycast"
        default: return key
        }
    }
}

#else
struct ProviderIconView: View {
    let provider: String
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.12))
            Text(String(provider.prefix(1)).uppercased()).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
    }
}
#endif
