import AppKit
import SwiftUI

// "Pinned ›" row at the bottom of the history list. Hovering or clicking it opens the pins submenu.
struct PinsSubmenuRowView: View {
  @Environment(AppState.self) private var appState

  @State private var anchor = AnchorViewHolder()
  @State private var isHovered = false

  private var submenu: PinsSubmenuController { PinsSubmenuController.shared }
  private var isHighlighted: Bool { isHovered || submenu.isVisible }
  private var title: String {
    NSLocalizedString("pins_submenu_title", value: "Pinned", comment: "")
  }

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "pin.fill")
        .font(.caption)
        .accessibilityHidden(true)
      Text(title)
      Spacer()
      Text(verbatim: "\(appState.history.submenuPinnedItems.count)")
        .foregroundStyle(isHighlighted ? Color.white.opacity(0.8) : .secondary)
      Image(systemName: "chevron.right")
        .font(.caption)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity, minHeight: Popup.itemHeight)
    .foregroundStyle(isHighlighted ? Color.white : .primary)
    .background(
      isHighlighted ? Color.accentColor.opacity(0.8) : .white.opacity(0.001),
      in: RoundedRectangle(cornerRadius: Popup.cornerRadius)
    )
    .background(SubmenuAnchorView(holder: anchor))
    .contentShape(Rectangle())
    .onHover { hovering in
      isHovered = hovering
      if hovering {
        openSubmenu()
      }
    }
    .onTapGesture(perform: openSubmenu)
    .onDisappear { submenu.hide() }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: title))
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(.default, openSubmenu)
    .accessibilityIdentifier("pins-submenu-row")
  }

  private func openSubmenu() {
    guard let view = anchor.view else { return }
    submenu.show(anchoredTo: view)
  }
}

// List of pinned items shown inside the submenu panel.
struct PinsSubmenuView: View {
  @Environment(AppState.self) private var appState
  @State private var hoveredItemID: UUID?

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      ScrollView {
        VStack(spacing: 0) {
          ForEach(appState.history.submenuPinnedItems) { item in
            PinsSubmenuItemView(item: item, isHovered: hoveredItemID == item.id)
              .onHover { hovering in
                if hovering {
                  hoveredItemID = item.id
                } else if hoveredItemID == item.id {
                  hoveredItemID = nil
                }
              }
          }
        }
        .padding(PinsSubmenuController.padding)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("pins-submenu")
  }
}

private struct PinsSubmenuItemView: View {
  @Environment(AppState.self) private var appState

  let item: HistoryItemDecorator
  let isHovered: Bool

  private var name: String { item.item.pinName ?? "" }

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: name)
          .lineLimit(1)
        Text(verbatim: item.title)
          .font(.caption)
          .lineLimit(1)
          .foregroundStyle(isHovered ? Color.white.opacity(0.8) : .secondary)
      }
      .truncationMode(.tail)

      Spacer(minLength: 4)

      KeyboardShortcutView(shortcut: item.shortcuts.first)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, 10)
    .frame(height: PinsSubmenuController.rowHeight)
    .foregroundStyle(isHovered ? Color.white : .primary)
    .background(
      isHovered ? Color.accentColor.opacity(0.8) : .white.opacity(0.001),
      in: RoundedRectangle(cornerRadius: Popup.cornerRadius)
    )
    .contentShape(Rectangle())
    .onTapGesture(perform: select)
    .contextMenu {
      Button(NSLocalizedString("pin_rename_action", value: "Rename…", comment: ""), action: rename)
      Button(NSLocalizedString("pin_unpin_action", value: "Unpin", comment: ""), action: unpin)
    }
    .help(item.title)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: "\(name), \(item.accessibilityLabel)"))
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(.default, select)
    .accessibilityAction(named: Text(verbatim: NSLocalizedString("pin_rename_action", value: "Rename…", comment: "")), rename)
    .accessibilityAction(named: Text(verbatim: NSLocalizedString("pin_unpin_action", value: "Unpin", comment: "")), unpin)
    .accessibilityIdentifier("pins-submenu-item")
  }

  private func select() {
    let flags = NSEvent.ModifierFlags.currentModifierFlags
    PinsSubmenuController.shared.hide()
    Task {
      appState.history.select(item, flags: flags)
    }
  }

  private func rename() {
    appState.requestPinName(for: item, mode: .rename)
    PinsSubmenuController.shared.hide()
  }

  private func unpin() {
    appState.history.togglePin(item)
    if appState.history.submenuPinnedItems.isEmpty {
      PinsSubmenuController.shared.hide()
    } else {
      PinsSubmenuController.shared.refresh()
    }
  }
}

final class AnchorViewHolder {
  weak var view: NSView?
}

// Captures the row's NSView so the submenu can be positioned in screen coordinates.
private struct SubmenuAnchorView: NSViewRepresentable {
  let holder: AnchorViewHolder

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    holder.view = view
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    holder.view = nsView
  }
}
