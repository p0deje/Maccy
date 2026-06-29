import Defaults
import SwiftUI

/// Describes how a row's corners should be shaped based on its selection state
/// relative to neighboring selected rows, so contiguous runs render as a single
/// rounded capsule.
enum SelectionAppearance {
  case none
  case topConnection
  case bottomConnection
  case topBottomConnection

  /// Returns a shape with the appropriate corners rounded for this appearance.
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

/// A single history list row: optional app icon, thumbnail or accessory image,
/// title, selection index badge, and keyboard-shortcut hints.
///
/// Row geometry is intentionally fixed (see the `.frame(height:)` in `body`):
/// the thumbnail is bounded to the row height with aspect-fit so an asynchronously
/// arriving image can never change the row's height. Without this, the height
/// change would force the enclosing `LazyVStack` to re-measure every visible row
/// on each thumbnail landing.
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
    let row = HStack(spacing: 0) {
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
        // Thumbnails are pre-sized by the off-main image pipeline, so the image
        // fills its frame without scaling artifacts; `.resizable()` lets SwiftUI
        // lay it out to the row height rather than at natural pixel size.
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
    // Fixed (not minimum) row height: a floor let image rows grow when an async
    // thumbnail landed, which fed a layout-feedback loop in the enclosing
    // `LazyVStack`. A fixed height keeps row geometry invariant to thumbnail
    // state.
    .frame(height: Popup.itemHeight)
    .id(id)
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(isSelected ? Color.white : .primary)
    // macOS 26 broke hovering if no background is present.
    // The slight opcaity white background is a workaround
    .background(isSelected ? Color.accentColor.opacity(0.8) : .white.opacity(0.001))
    .clipShape(selectionAppearance.rect(cornerRadius: Popup.cornerRadius))
    .hoverSelectionId(selectionId)

    // Apply `.help` only when a tooltip string is provided. An always-on
    // `.help("")` would materialize an empty `HelpView` AttributeGraph node per
    // realized row for no benefit, since no row currently shows a tooltip.
    if let help {
      row.help(help)
    } else {
      row
    }
  }
}
