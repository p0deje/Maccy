import Defaults
import SwiftUI

struct HistoryListView: View {
  @Binding var searchQuery: String
  @FocusState.Binding var searchFocused: Bool

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Environment(\.scenePhase) private var scenePhase

  @Default(.pinTo) private var pinTo
  @Default(.previewDelay) private var previewDelay

  private var pinnedItems: [HistoryItemDecorator] {
    let pinned = appState.history.pinnedItems.filter(\.isVisible)
    if pinned.isEmpty { return [] }

    // Break the chain into simpler, explicitly-typed steps to help the type checker.
    let models: [HistoryItem] = pinned.map { $0.item }
    let sortedModels: [HistoryItem] = Sorter().sort(models)

    // Build a fast lookup from the HistoryItem object identity to its decorator.
    var lookup: [ObjectIdentifier: HistoryItemDecorator] = [:]
    lookup.reserveCapacity(pinned.count)
    for decorator in pinned {
      lookup[ObjectIdentifier(decorator.item)] = decorator
    }

    // Map sorted models back to their decorators using identity.
    var result: [HistoryItemDecorator] = []
    result.reserveCapacity(sortedModels.count)
    for model in sortedModels {
      if let decorator = lookup[ObjectIdentifier(model)] {
        result.append(decorator)
      }
    }
    return result
  }

  private var unpinnedItems: [HistoryItemDecorator] {
    appState.history.unpinnedItems.filter(\.isVisible)
  }
  private var showPinsSeparator: Bool {
    !pinnedItems.isEmpty && !unpinnedItems.isEmpty && appState.history.searchQuery.isEmpty
  }

  var body: some View {
    if pinTo == .top {
      LazyVStack(spacing: 0) {
        ForEach(pinnedItems) { item in
          pinnedRow(for: item)
        }

        if showPinsSeparator {
          Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }
      }
      .background {
        GeometryReader { geo in
          Color.clear
            .task(id: geo.size.height) {
              appState.popup.pinnedItemsHeight = geo.size.height
            }
        }
      }
    }

    ScrollView {
      ScrollViewReader { proxy in
        LazyVStack(spacing: 0) {
          ForEach(unpinnedItems) { item in
            HistoryItemView(item: item)
          }
        }
        .task(id: appState.scrollTarget) {
          guard appState.scrollTarget != nil else { return }

          try? await Task.sleep(for: .milliseconds(10))
          guard !Task.isCancelled else { return }

          if let selection = appState.scrollTarget {
            proxy.scrollTo(selection)
            appState.scrollTarget = nil
          }
        }
        .onChange(of: scenePhase) {
          if scenePhase == .active {
            searchFocused = true
            HistoryItemDecorator.previewThrottler.minimumDelay = Double(previewDelay) / 1000
            HistoryItemDecorator.previewThrottler.cancel()
            appState.isKeyboardNavigating = true
            appState.selection = appState.history.unpinnedItems.first?.id ?? appState.history.pinnedItems.first?.id
          } else {
            modifierFlags.flags = []
            appState.isKeyboardNavigating = true
          }
        }
        // Calculate the total height inside a scroll view.
        .background {
          GeometryReader { geo in
            Color.clear
              .task(id: appState.popup.needsResize) {
                try? await Task.sleep(for: .milliseconds(10))
                guard !Task.isCancelled else { return }

                if appState.popup.needsResize {
                  appState.popup.resize(height: geo.size.height)
                }
              }
          }
        }
      }
      .contentMargins(.leading, 10, for: .scrollIndicators)
    }

    if pinTo == .bottom {
      LazyVStack(spacing: 0) {
        if showPinsSeparator {
          Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }

        ForEach(pinnedItems) { item in
          pinnedRow(for: item)
        }
      }
      .background {
        GeometryReader { geo in
          Color.clear
            .task(id: geo.size.height) {
              appState.popup.pinnedItemsHeight = geo.size.height
            }
        }
      }
    }
  }

  @ViewBuilder
  private func pinnedRow(for item: HistoryItemDecorator) -> some View {
    if modifierFlags.flags.contains(.option) || modifierFlags.flags.contains(.control) {
      HistoryItemView(item: item)
        .onDrag {
          NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(of: ["public.text"], isTargeted: nil) { providers in
          handleDrop(providers: providers, before: item)
        }
    } else {
      HistoryItemView(item: item)
    }
  }

  private func handleDrop(providers: [NSItemProvider], before item: HistoryItemDecorator) -> Bool {
    guard let provider = providers.first else { return false }

    // Prefer UTType-based API to avoid bridging issues with NSString.
    // Try plain-text first, fall back to public.text.
    let typeIdentifiers = ["public.plain-text", "public.text"]

    func loadNext(from index: Int) {
      guard index < typeIdentifiers.count else { return }
      let typeID = typeIdentifiers[index]
      provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
        if let data, let idString = String(data: data, encoding: .utf8) {
          DispatchQueue.main.async {
            if let source = appState.history.items.first(where: { $0.id.uuidString == idString }) {
              appState.history.movePinned(source, before: item)
            }
          }
        } else {
          // Try the next type identifier if this one failed.
          loadNext(from: index + 1)
        }
      }
    }

    loadNext(from: 0)
    return true
  }
}
