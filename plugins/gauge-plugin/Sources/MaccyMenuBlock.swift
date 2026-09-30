//
//  MaccyMenuBlock.swift
//  GaugeMaccyPlugin
//
//  The tray card, per plugins/TRAY-GUIDELINES.md:
//    • Fluid 360–410pt width: no fixedSize(), no fixed frame(width:), every
//      growable text is lineLimit'd + truncationMode, Spacer(minLength:)
//      keeps columns from colliding.
//    • Deterministic first layout: every row renders at FIXED heights with
//      placeholders before any data lands. Rows never appear/disappear —
//      data changes swap TEXT CONTENT only; paging swaps the content of a
//      constant-height rows area (the AI Sessions pattern), so the block
//      height never changes under the host.
//    • No timers that mutate layout structure: the 1s tick updates text only
//      (and only while the menu is open).
//
//  Restore flow: tapping an item copies it back to the pasteboard (marker
//  type set so maccy-agent never re-captures it) and, when Gauge is
//  Accessibility-trusted, arms a one-shot ⌘V that fires when the host closes
//  the popover (menuDidClose) — the paste then lands in the real frontmost
//  app, never inside the popover. Without the grant, items copy only.
//

import SwiftUI
import AppKit

struct MaccyMenuBlock: View {

    @ObservedObject var store: MaccyHistoryStore

    /// 1s text tick ("2m ago" refresh), gated on menu visibility — same
    /// pattern as the squeakd/AI Sessions plugins. Fires are no-ops when
    /// closed.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var now = Date()
    @State private var page = 0
    @State private var pulsing = false

    // Fixed geometry: the host measures this block once per snapshot; a
    // layout-state-driven change would leave a stale host frame.
    static let maxRows = 6
    private static let statusRowHeight: CGFloat = 18
    private static let itemRowHeight: CGFloat = 20
    private static let footerRowHeight: CGFloat = 14

    private var pageCount: Int {
        max(1, (store.items.count + Self.maxRows - 1) / Self.maxRows)
    }

    /// Items for the current page, padded with placeholders to a constant
    /// row count so height never changes between pages.
    private var pageItems: [MaccyHistorySnapshot.MaccyHistoryItem?] {
        let start = min(page, pageCount - 1) * Self.maxRows
        let slice = Array(store.items.dropFirst(start).prefix(Self.maxRows))
        var rows: [MaccyHistorySnapshot.MaccyHistoryItem?] = Array(repeating: nil, count: Self.maxRows)
        for (index, item) in slice.enumerated() where index < Self.maxRows {
            rows[index] = item
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            statusRow
                .frame(height: Self.statusRowHeight, alignment: .center)
            itemsArea
                .frame(height: CGFloat(Self.maxRows) * Self.itemRowHeight, alignment: .top)
            footerRow
                .frame(height: Self.footerRowHeight, alignment: .center)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        // Opaque strip so an independently measured frame still looks coherent.
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(tick) { date in
            guard store.isMenuVisible else { return }
            now = date
        }
        .onChange(of: store.items.count) { _ in page = 0 }
    }

    // MARK: Row 1 — dot + name + summary

    private var statusRow: some View {
        HStack(spacing: 6) {
            statusDot
            Text("Maccy")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 6)
            Text(statusText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .scaleEffect(pulsing ? 1.4 : 1.0)
            .opacity(pulsing ? 0.55 : 1.0)
            .animation(
                pulsing ? Animation.easeInOut(duration: 0.7).repeatForever(autoreverses: true) : nil,
                value: pulsing
            )
            .onChange(of: shouldPulse) { pulsing = $0 }
            .onAppear { pulsing = shouldPulse }
    }

    /// Pulse while a ⌘V paste is armed — the user should close the tray to
    /// release it (visible feedback; never animates while hidden).
    private var shouldPulse: Bool { store.isMenuVisible && store.pendingAutoPaste }

    private var dotColor: Color {
        if store.pendingAutoPaste { return Color.orange }
        return store.isAlive ? Color.green : Color.secondary.opacity(0.55)
    }

    private var statusText: String {
        if store.pendingAutoPaste { return "⌘V armed — close tray to paste" }
        guard store.isAlive else { return "agent not running" }
        var parts: [String] = []
        parts.append("\(store.itemCount) item\(store.itemCount == 1 ? "" : "s")")
        if let last = store.lastCapturedAt {
            parts.append(Self.relative(last, to: now))
        }
        if !store.axTrusted { parts.append("copy only") }
        return parts.joined(separator: " · ")
    }

    // MARK: Rows area — constant height, content swaps per page

    private var itemsArea: some View {
        VStack(spacing: 1) {
            ForEach(Array(pageItems.enumerated()), id: \.offset) { _, item in
                itemRow(item)
                    .frame(height: Self.itemRowHeight, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func itemRow(_ item: MaccyHistorySnapshot.MaccyHistoryItem?) -> some View {
        if let item {
            Button(action: { restore(item) }) {
                HStack(spacing: 5) {
                    Text(glyph(for: item))
                        .font(.system(size: 10))
                        .frame(width: 14, alignment: .center)
                    Text(itemTitle(item))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    if let capturedAt = item.capturedAt {
                        Text(Self.relative(capturedAt, to: now))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Copy \(itemTitle(item)) back to the clipboard")
        } else {
            // Structural empty slot — keeps the rows area exactly maxRows tall.
            Color.clear
        }
    }

    private func glyph(for item: MaccyHistorySnapshot.MaccyHistoryItem) -> String {
        if !(item.fileURLs?.isEmpty ?? true) { return "📎" }
        if item.imageType != nil || item.image != nil { return "🖼" }
        return "•"
    }

    /// Sanitized, single-line preview of the item.
    private func itemTitle(_ item: MaccyHistorySnapshot.MaccyHistoryItem) -> String {
        let raw = item.title ?? item.string ?? "———"
        let cleaned = raw.removingScalarsUnsafeForTitleLayout()
        return cleaned.isEmpty ? "———" : cleaned
    }

    private func restore(_ item: MaccyHistorySnapshot.MaccyHistoryItem) {
        MaccyPasteboard.restore(item)
        store.armAutoPaste()
    }

    // MARK: Footer — paging, or agent affordance when off

    private var footerRow: some View {
        Group {
            if !store.isAlive {
                Button(action: startAgent) {
                    Text("agent not running · Start")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .help("kickstart the maccy-agent LaunchAgent")
            } else if pageCount > 1 {
                HStack(spacing: 4) {
                    Button(action: { page = (page - 1 + pageCount) % pageCount }) {
                        Text("← prev")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(page == 0)
                    Spacer(minLength: 4)
                    Text("\(page + 1)/\(pageCount)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button(action: { page = (page + 1) % pageCount }) {
                        Text("more →")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(page >= pageCount - 1)
                }
            } else {
                // Single page: keep the row slot at fixed height, empty.
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Kickstart the agent LaunchAgent (silent no-op when not installed).
    private func startAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/com.ebowwa.maccy.agent"]
        try? process.run()
    }

    // MARK: Formatting (pure, deterministic)

    /// "2m ago"-style relative time.
    static func relative(_ date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date).rounded()))
        switch seconds {
        case ..<10: return "now"
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }
}

/// Strip scalars that hang CoreText line truncation (mirrors Maccy + agent).
extension String {
    private static let scalarsUnsafeForTitleLayout: Set<Unicode.Scalar> = [
        "\u{FFFC}"
    ]

    var containsScalarsUnsafeForTitleLayout: Bool {
        unicodeScalars.contains { Self.scalarsUnsafeForTitleLayout.contains($0) }
    }

    func removingScalarsUnsafeForTitleLayout() -> String {
        guard containsScalarsUnsafeForTitleLayout else { return self }
        var scalars = String.UnicodeScalarView()
        for scalar in unicodeScalars where !Self.scalarsUnsafeForTitleLayout.contains(scalar) {
            scalars.append(scalar)
        }
        return String(scalars)
    }
}