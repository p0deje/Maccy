import Defaults
import SwiftUI

/// Original and compact presentations share the same actions and keyboard navigation.
struct FooterView: View {
  @Bindable var footer: Footer

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Default(.showFooter) private var showFooter
  @Default(.compactFooter) private var compactFooter
  @State private var showClearAll = false

  private var clearAllModifiersPressed: Bool {
    let clearModifiers = footer.items[0].shortcuts.first?.modifierFlags ?? []
    let clearAllModifiers = footer.items[1].shortcuts.first?.modifierFlags ?? []
    return !modifierFlags.flags.isEmpty
      && !modifierFlags.flags.isSubset(of: clearModifiers)
      && modifierFlags.flags.isSubset(of: clearAllModifiers)
  }

  var body: some View {
    VStack(spacing: 0) {
      if compactFooter {
        compactContent
      } else {
        originalContent
      }
    }
    .invisible(!showFooter)
    .frame(maxHeight: showFooter ? nil : 0)
    .padding(.bottom, showFooter ? Popup.verticalPadding : 0)
    .readHeight(appState, into: \.popup.footerHeight)
    .onChange(of: appState.popup.footerHeight) {
      appState.popup.needsResize = true
    }
    .onChange(of: modifierFlags.flags, initial: true) {
      updateClearAllSelection()
    }
  }

  private var compactContent: some View {
    VStack(spacing: 0) {
      Divider()
        .padding(.horizontal, Popup.horizontalSeparatorPadding)
        .padding(.bottom, 5)
      HStack(spacing: 0) {
        Spacer(minLength: 0)
        // Keep both confirmation presenters alive when modifier keys are released.
        ZStack {
          actionButton(item: footer.items[0], symbol: "trash", tint: .primary)
            .invisible(showClearAll)
            .allowsHitTesting(!showClearAll)
          actionButton(item: footer.items[1], symbol: "trash", tint: .primary)
            .invisible(!showClearAll)
            .allowsHitTesting(showClearAll)
        }
        actionButton(item: footer.items[2], symbol: "gearshape", tint: .primary)
        actionButton(item: footer.items[3], symbol: "info.circle", tint: .primary)
        actionButton(item: footer.items[4], symbol: "power", tint: .red)
        Spacer(minLength: 0)
      }
      .padding(3)
      .background(.quaternary.opacity(0.6), in: Capsule())
      .overlay(Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
      .fixedSize(horizontal: true, vertical: false)
      .frame(maxWidth: .infinity)
      .padding(.bottom, 3)
      .offset(y: 1)
    }
  }

  private var originalContent: some View {
    VStack(spacing: 0) {
      Divider()
        .padding(.horizontal, Popup.horizontalSeparatorPadding)
        .padding(.bottom, Popup.verticalSeparatorPadding)
      ZStack {
        FooterItemView(item: footer.items[0])
          .invisible(showClearAll)
          .allowsHitTesting(!showClearAll)
        FooterItemView(item: footer.items[1])
          .invisible(!showClearAll)
          .allowsHitTesting(showClearAll)
      }
      ForEach(footer.items.suffix(from: 2)) { item in
        FooterItemView(item: item)
      }
    }
  }

  private func updateClearAllSelection() {
    let clearAll = clearAllModifiersPressed
    showClearAll = clearAll
    footer.items[0].isVisible = !clearAll
    footer.items[1].isVisible = clearAll
    if appState.footer.selectedItem == footer.items[clearAll ? 0 : 1] {
      appState.navigator.select(footerItem: footer.items[clearAll ? 1 : 0])
    }
  }

  private func actionButton(item: FooterItem, symbol: String, tint: Color) -> some View {
    ConfirmationView(item: item) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(item.isSelected ? Color.white : tint)
        .frame(width: 33, height: 26)
        .background {
          Capsule().fill(item.isSelected ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.001))
        }
        .contentShape(Rectangle())
        .accessibilityLabel(Text(LocalizedStringKey(item.title)))
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
        .help(item.help ?? LocalizedStringKey(item.title))
    }
    .hoverSelectionId(item.id)
    .onHover { hovering in
      if hovering && appState.preview.state.isOpen {
        appState.preview.togglePreview()
      }
    }
  }
}
