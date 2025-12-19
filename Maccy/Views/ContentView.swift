import KeyboardShortcuts
import SwiftData
import SwiftUI

struct ContentView: View {
  @State private var appState = AppState.shared
  @State private var modifierFlags = ModifierFlags()
  @State private var scenePhase: ScenePhase = .background

  @FocusState private var searchFocused: Bool

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      KeyHandlingView(searchQuery: $appState.history.searchQuery, searchFocused: $searchFocused) {
        HStack(alignment: .top, spacing: 0) {
          VStack(alignment: .leading, spacing: 0) {
            HeaderView(
              searchFocused: $searchFocused,
              searchQuery: $appState.history.searchQuery
            )

            HistoryListView(
              searchQuery: $appState.history.searchQuery,
              searchFocused: $searchFocused
            )

            FooterView(footer: appState.footer)
          }
          .layoutPriority(1)
          .padding(.horizontal, 5)

          Divider()

          VStack(alignment: .leading, spacing: 0) {
            ScrollView {
              if let selectedItem = appState.history.selectedItem {
                PreviewItemView(item: selectedItem)
                  .frame(maxWidth: .infinity, alignment: .topLeading)
              }
            }
            .scrollIndicators(.automatic, axes: .vertical)
            .scrollBounceBehavior(.basedOnSize)

            previewFooterView(item: appState.history.selectedItem)
          }
          .layoutPriority(1)
          .padding(.horizontal, 10)
        }
      }
      .animation(.default.speed(3), value: appState.history.items)
      .animation(.easeInOut(duration: 0.2), value: appState.searchVisible)
      .padding(.vertical, Popup.verticalPadding)
      .padding(.horizontal, Popup.horizontalPadding)
      .onAppear {
        searchFocused = true
      }
      .onMouseMove {
        appState.isKeyboardNavigating = false
      }
      .task {
        try? await appState.history.load()
      }
    }
    .environment(appState)
    .environment(modifierFlags)
    .environment(\.scenePhase, scenePhase)
    // FloatingPanel is not a scene, so let's implement custom scenePhase..
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
      if let window = $0.object as? NSWindow,
         let bundleIdentifier = Bundle.main.bundleIdentifier,
         window.identifier == NSUserInterfaceItemIdentifier(bundleIdentifier) {
        scenePhase = .active
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
      if let window = $0.object as? NSWindow,
         let bundleIdentifier = Bundle.main.bundleIdentifier,
         window.identifier == NSUserInterfaceItemIdentifier(bundleIdentifier) {
        scenePhase = .background
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSPopover.willShowNotification)) {
      if let popover = $0.object as? NSPopover {
        // Prevent NSPopover from showing close animation when
        // quickly toggling FloatingPanel while popover is visible.
        popover.animates = false
        // Prevent NSPopover from becoming first responder.
        popover.behavior = .semitransient
      }
    }
  }

  @ViewBuilder
  private func previewFooterView(item: HistoryItemDecorator?) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Divider()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)

      if let item = item {
        previewMetadataView(item: item)
        previewShortcutsView()
      }
    }
    .controlSize(.small)
    .padding(.horizontal, 0)
  }

  @ViewBuilder
  private func previewMetadataView(item: HistoryItemDecorator) -> some View {
    if let application = item.application {
      metadataRow(
        label: "Application",
        value: application,
        image: item.applicationImage.nsImage
      )
    }

    metadataRow(
      label: "FirstCopyTime",
      date: item.item.firstCopiedAt
    )

    metadataRow(
      label: "LastCopyTime",
      date: item.item.lastCopiedAt
    )

    metadataRow(
      label: "NumberOfCopies",
      value: String(item.item.numberOfCopies)
    )
    .padding(.bottom)
  }

  @ViewBuilder
  private func metadataRow(label: String, value: String, image: NSImage? = nil) -> some View {
    HStack(spacing: 3) {
      Text(LocalizedStringKey(label), tableName: "PreviewItemView")
      if let image = image {
        Image(nsImage: image)
          .resizable()
          .frame(width: 11, height: 11)
      }
      Text(value)
    }
    .frame(minHeight: Popup.itemHeight)
  }

  @ViewBuilder
  private func metadataRow(label: String, date: Date) -> some View {
    HStack(spacing: 3) {
      Text(LocalizedStringKey(label), tableName: "PreviewItemView")
      Text(date, style: .date)
      Text(date, style: .time)
    }
    .frame(minHeight: Popup.itemHeight)
  }

  @ViewBuilder
  private func previewShortcutsView() -> some View {
    if let pinKey = KeyboardShortcuts.Shortcut(name: .pin) {
      shortcutRow(
        key: "PinKey",
        shortcut: pinKey.description
      )
    }

    if let deleteKey = KeyboardShortcuts.Shortcut(name: .delete) {
      shortcutRow(
        key: "DeleteKey",
        shortcut: deleteKey.description
      )
    }
  }

  @ViewBuilder
  private func shortcutRow(key: String, shortcut: String) -> some View {
    let placeholder = key == "PinKey" ? "{pinKey}" : "{deleteKey}"
    Text(
      NSLocalizedString(key, tableName: "PreviewItemView", comment: "")
        .replacingOccurrences(of: placeholder, with: shortcut)
    )
    .frame(minHeight: Popup.itemHeight)
  }
}

#Preview {
  ContentView()
    .environment(\.locale, .init(identifier: "en"))
    .modelContainer(Storage.shared.container)
}
