import Defaults
import SwiftUI

enum SelectionAppearance {
  case none
  case topConnection
  case bottomConnection
  case topBottomConnection

  func rect(cornerRadius: CGFloat) -> some Shape {
    var cornerRadii = RectangleCornerRadii()
    switch self {
    case .none:
      cornerRadii.topLeading = cornerRadius
      cornerRadii.topTrailing = cornerRadius
      cornerRadii.bottomLeading = cornerRadius
      cornerRadii.bottomTrailing = cornerRadius
    case .topConnection:
      cornerRadii.bottomLeading = cornerRadius
      cornerRadii.bottomTrailing = cornerRadius
    case .bottomConnection:
      cornerRadii.topLeading = cornerRadius
      cornerRadii.topTrailing = cornerRadius
    case .topBottomConnection:
      break
    }
    return .rect(cornerRadii: cornerRadii)
  }
}

struct ListItemView<Title: View, ID: Hashable>: View {
  var id: ID
  var selectionId: UUID
  var appIcon: ApplicationImage?
  var image: NSImage?
  var accessoryImage: NSImage?
  var attributedTitle: AttributedString?
  var shortcuts: [KeyShortcut]
  var isSelected: Bool
  var selectionIndex: Int?
  var help: LocalizedStringKey?
  var selectionAppearance: SelectionAppearance = .none
  @ViewBuilder var title: () -> Title

  @Default(.showApplicationIcons) private var showIcons
  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags

  var body: some View {
    HStack(spacing: 0) {
      if showIcons, let appIcon {
        VStack {
          Spacer(minLength: 0)
          AppImageView(appImage: appIcon, size: NSSize(width: 15, height: 15))
          Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.vertical, 5)
      }

      Spacer()
        .frame(width: showIcons ? 5 : 10)

      if let accessoryImage {
        Image(nsImage: accessoryImage)
          .accessibilityIdentifier("copy-history-item")
          .padding(.trailing, 5)
          .padding(.vertical, 5)
      }

      if let image {
        // IMG-020: thumbnails are pre-sized by the off-main pipeline, so the
        // image fills its frame without scaling artifacts; .resizable() lets
        // SwiftUI lay it out to the row height instead of natural pixels.
        //
        // P0 (2026-06-21 render-feedback stopgap): the thumbnail is given a
        // FIXED height (row height minus the vertical padding) + aspect-fit so
        // its arrival can NEVER change the row's height. Previously the image
        // branch had no frame, so an async thumbnail landing grew the row
        // (imageMaxHeight path) → LazyVStack re-measured every row → CoreText
        // text-measurement storm (spindump: StyledTextLayoutEngine.sizeThatFits
        // → _NSOptimalLineBreaker) → ~400s mixed-list hang. Fixed row height
        // (see the `.frame(height:)` below) + this bounded aspect-fit image
        // make row geometry stable regardless of thumbnail state.
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
          .frame(height: Popup.itemHeight - 10)
          .accessibilityIdentifier("copy-history-item")
          .padding(.trailing, 5)
          .padding(.vertical, 5)
      } else {
        ListItemTitleView(attributedTitle: attributedTitle, title: title)
          .padding(.trailing, 5)
      }

      Spacer()

      HStack(spacing: 5) {
        if let index = selectionIndex {
          Text("\(index + 1)")
            .font(.caption)
            .frame(minWidth: 10, alignment: .center)
            .padding(3)
            .background(
              Color.secondary.opacity(isSelected ? 0.5 : 0.8),
              in: Capsule()
            )
            .foregroundStyle(Color.white)
        }

        if !shortcuts.isEmpty {
          ZStack(alignment: .trailing) {
            ForEach(shortcuts) { shortcut in
              let visible = shortcut.isVisible(shortcuts, modifierFlags.flags)
              KeyboardShortcutView(shortcut: shortcut)
                .opacity(visible ? 1 : 0)
                .frame(width: visible ? nil : 0)
            }
          }
        }
      }
      .padding(.trailing, 10)
    }
    // P0 (2026-06-21): FIXED row height (was `minHeight`). A floor let image
    // rows grow when async thumbnails landed, feeding a LazyVStack layout-
    // feedback storm (CoreText re-measure per row). A fixed height makes row
    // geometry invariant to thumbnail state — the direct fix for the mixed-list
    // ~400s hang. (imageMaxHeight is dead in production — max(340,h)=340 — so
    // clamping here is safe and matches the setting's "look like text items"
    // intent; see docs/audit/2026-06-21-render-feedback-stopgap.md.)
    .frame(height: Popup.itemHeight)
    .id(id)
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(isSelected ? Color.white : .primary)
    // macOS 26 broke hovering if no background is present.
    // The slight opcaity white background is a workaround
    .background(isSelected ? Color.accentColor.opacity(0.8) : .white.opacity(0.001))
    .clipShape(selectionAppearance.rect(cornerRadius: Popup.cornerRadius))
    .hoverSelectionId(selectionId)
    .help(help ?? "")
  }
}
