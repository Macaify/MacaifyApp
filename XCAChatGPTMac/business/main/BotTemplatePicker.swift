//
//  BotTemplatePicker.swift
//  XCAChatGPTMac
//
//  Created by Codex on 2025/10/27.
//

import SwiftUI

struct BotTemplatePicker: View {
    @StateObject private var store = PromptStore()
    var resetKey: Int = 0
    var onPick: (PromptTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "选择机器人模板"))
                    .font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "搜索"), text: $store.searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 220)
                }
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.filteredPrompts, id: \.title) { tpl in
                        row(tpl)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .id(resetKey)
    }

    @ViewBuilder
    private func row(_ item: PromptTemplate) -> some View {
        Button {
            onPick(item)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let d = item.desc, !d.isEmpty {
                        Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text(item.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

