//
//  AppUpdaterLink.swift
//  Macaify
//
//  Created by lixindong on 2024/9/29.
//

import Foundation
import SwiftUI
import AppUpdater

struct AppUpdaterLink: View {
    @EnvironmentObject var updater: AppUpdater
    var onOpenSettings: (() -> Void)? = nil

    var body: some View {
        Group {
            if #available(macOS 13.0, *) {
                // macOS 13+: do not trigger check/install here. Show an indicator if update is available.
                Button(action: { onOpenSettings?() }) {
                    HStack(spacing: 8) {
                        Text("check_for_updates")
                        if hasUpdateIndicator {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .accessibilityLabel(Text("update_available"))
                        }
                    }
                }
                // .buttonStyle(.plain)
            } else {
                // macOS 12 and below: keep original behavior (check/install inline)
                switch updater.state {
                case .none, .newVersionDetected:
                    Button { updater.check() } label: { Text("check_for_updates") }
                case .downloading(_, _, fraction: let fraction):
                    Text("Downloading \(Int(fraction * 10000) / 100)%")
                case .downloaded(_, _, let bundle):
                    Button { updater.install(bundle) } label: { Text("install_and_restart") }
                }
            }
        }
    }

    private var hasUpdateIndicator: Bool {
        switch updater.state {
        case .newVersionDetected, .downloading, .downloaded: return true
        default: return false
        }
    }
}
