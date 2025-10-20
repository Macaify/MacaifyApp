import AppKit
import SwiftUI

// High-performance chat list using NSTableView + NSHostingView cell reuse.
struct ChatTableView: NSViewRepresentable {
    @ObservedObject var vm: ViewModel
    var onRetry: (MessageRow) -> Void
    @Binding var scrollSignal: Int
    @EnvironmentObject var globalConfig: GlobalConfig

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = context.coordinator.tableView
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = tableView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Reset coordinator state when switching to a different ViewModel to avoid stale counts
        if ObjectIdentifier(context.coordinator.parent.vm) != ObjectIdentifier(self.vm) {
            context.coordinator.lastMessagesCount = -1
        }
        context.coordinator.parent = self
        context.coordinator.reloadIfNeeded()
        // Scroll on external signal
        if context.coordinator.lastScrollSignal != scrollSignal {
            context.coordinator.lastScrollSignal = scrollSignal
            context.coordinator.scrollToBottom(animated: true)
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ChatTableView
        let tableView = NSTableView()
        private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
        var lastMessagesCount: Int = -1
        var lastScrollSignal: Int = 0
        var lastScrollTime: Double = 0
        let scrollThrottle: Double = 0.12

        init(_ parent: ChatTableView) {
            self.parent = parent
            super.init()

            tableView.headerView = nil
            tableView.gridStyleMask = []
            tableView.selectionHighlightStyle = .none
            tableView.backgroundColor = .clear
            tableView.usesAutomaticRowHeights = true
            tableView.intercellSpacing = NSSize(width: 0, height: 0)

            column.width = 10
            tableView.addTableColumn(column)
            tableView.delegate = self
            tableView.dataSource = self
        }

        func reloadIfNeeded() {
            let count = parent.vm.messages.count
            let prev = lastMessagesCount
            let wasNearBottom = isNearBottom()
            if prev == -1 {
                lastMessagesCount = count
                tableView.reloadData()
                if wasNearBottom { scrollToBottom(animated: false) }
                return
            }
            if count > prev {
                let newRange = prev..<count
                lastMessagesCount = count
                let indexes = IndexSet(integersIn: newRange)
                tableView.beginUpdates()
                tableView.insertRows(at: indexes, withAnimation: [.effectFade])
                tableView.endUpdates()
                if wasNearBottom { scrollToBottom(animated: parent.vm.isInteractingWithChatGPT) }
            } else if count < prev {
                // Clear/trim: reload for correctness
                lastMessagesCount = count
                tableView.reloadData()
                if wasNearBottom { scrollToBottom(animated: false) }
            } else if parent.vm.isInteractingWithChatGPT && count > 0 {
                // Streaming: update last row only
                let row = count - 1
                tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
                if wasNearBottom { scrollToBottom(animated: false) }
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.vm.messages.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("cell")
            if let cell = tableView.makeView(withIdentifier: id, owner: self) as? HostingCell {
                cell.render(message: parent.vm.messages[row], onRetry: parent.onRetry, globalConfig: parent.globalConfig)
                return cell
            }
            let cell = HostingCell(frame: .zero)
            cell.identifier = id
            cell.render(message: parent.vm.messages[row], onRetry: parent.onRetry, globalConfig: parent.globalConfig)
            return cell
        }

        func scrollToBottom(animated: Bool) {
            let now = Date.timeIntervalSinceReferenceDate
            if now - lastScrollTime < scrollThrottle { return }
            lastScrollTime = now
            let count = tableView.numberOfRows
            guard count > 0 else { return }
            tableView.scrollRowToVisible(count - 1)
        }

        private func isNearBottom() -> Bool {
            guard let sv = tableView.enclosingScrollView else { return true }
            let visibleMaxY = sv.contentView.documentVisibleRect.maxY
            let contentMaxY = tableView.bounds.maxY
            return contentMaxY - visibleMaxY < 60
        }

        // MARK: - Hosting cell
        final class HostingCell: NSTableCellView {
            private var host: NSHostingView<AnyView> = NSHostingView(rootView: AnyView(EmptyView()))

            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                host.translatesAutoresizingMaskIntoConstraints = false
                addSubview(host)
                NSLayoutConstraint.activate([
                    host.leadingAnchor.constraint(equalTo: leadingAnchor),
                    host.trailingAnchor.constraint(equalTo: trailingAnchor),
                    host.topAnchor.constraint(equalTo: topAnchor),
                    host.bottomAnchor.constraint(equalTo: bottomAnchor)
                ])
            }

            required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

            func render(message: MessageRow, onRetry: @escaping (MessageRow) -> Void, globalConfig: GlobalConfig) {
                host.rootView = AnyView(
                    MessageRowView(message: message, tag: String(message.id.uuidString.prefix(1)), retryCallback: onRetry)
                        .environmentObject(globalConfig)
                )
            }
        }
    }
}
