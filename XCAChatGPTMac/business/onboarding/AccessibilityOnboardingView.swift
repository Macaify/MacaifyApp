//
//  AccessibilityOnboardingView.swift
//  XCAChatGPTMac
//
//  Created by Codex on 2025/10/29.
//

import SwiftUI
import AVKit
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// First‑run onboarding to guide enabling macOS Accessibility permission.
/// - Shows a full‑bleed video, concise copy, a button to open System Settings, and an app icon with drag hint.
/// - Auto checks permission again whenever the app becomes active. When granted, shows a primary "开始使用" button.
struct AccessibilityOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isAuthorized: Bool = hasAccessibilityPermission()
    @State private var player: AVPlayer? = nil

    var onFinish: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            videoHero
            content
        }
        .frame(minWidth: 720, maxWidth: 860, minHeight: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .onAppear { setupVideo(); refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
}

// macOS-only: An AVPlayer host that fills its bounds (no controls, no letterboxing)
struct FillingPlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .none
        v.showsFullScreenToggleButton = false
        v.showsFrameSteppingButtons = false
        v.showsSharingServiceButton = false
        v.videoGravity = .resizeAspectFill
        v.player = player
        v.player?.isMuted = true
        return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.videoGravity = .resizeAspectFill
        nsView.controlsStyle = .none
    }
}

    private var videoHero: some View {
        Group {
            if let player {
                FillingPlayerView(player: player)
                    .onAppear {
                        player.isMuted = true
                        player.play()
                        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                            player.seek(to: .zero)
                            player.play()
                        }
                    }
            } else {
                // Fallback: gradient banner if video missing
                ZStack {
                    LinearGradient(colors: [.purple.opacity(0.35), .blue.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 8) {
                        Text(String(localized: "ax_video_title"))
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(String(localized: "ax_video_subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        // .frame(height: 260)
        .clipped()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "ax_onboarding_title"))
                    .font(.title3.weight(.semibold))
                Text(String(localized: "ax_onboarding_body"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if isAuthorized {
                    Button(action: openAccessibilitySettings) {
                        Label(String(localized: "ax_open_system_settings"), systemImage: "gearshape")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .tint(.secondary)

                    Button(action: finish) {
                        Label(String(localized: "ax_get_started"), systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .transition(.opacity)
                } else {
                    Button(action: openAccessibilitySettings) {
                        Label(String(localized: "ax_open_system_settings"), systemImage: "gearshape")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)

                    // Subtle helper while waiting for user to grant permission
                    Text(String(localized: "ax_after_grant_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .onDrag {
                        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
                        let provider = NSItemProvider(object: url as NSURL)
                        provider.suggestedName = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "Macaify"
                        return provider
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "ax_drag_hint_title"))
                    Text(String(localized: "ax_path_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.08))
            )
        }
        .padding(16)
    }

    private func setupVideo() {
        if let url = Bundle.main.url(forResource: "accessibility_guide", withExtension: "mp4") {
            player = AVPlayer(url: url)
        } else {
            player = nil
        }
    }

    private func refreshStatus() {
        isAuthorized = hasAccessibilityPermission()
    }

    private func finish() {
        onFinish()
        dismiss()
    }

    private func openAccessibilitySettings() {
        // Show the system prompt (one-time) to help user jump to Settings
        _ = hasAccessibilityPermission(prompt: true)
        // Best-effort open the System Settings page
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { break }
        }
    }
}
