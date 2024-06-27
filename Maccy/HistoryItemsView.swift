//import AppKit
//import SwiftUI
//import SwiftData
//import Defaults
//import Settings
//
//struct HistoryItemsView: View {
//  @Environment(\.keyModifierFlags) private var modifierFlags: NSEvent.ModifierFlags
//  @Environment(\.modelContext) private var modelContext
//
//  @Query private var historyItems: [HistoryItem]
////  @State private var sortOrder = SortDescriptor(\HistoryItem.lastCopiedAt)
//
////  private var historyItems: [HistoryItem] {
////    search.search(string: searchQuery, within: allHistoryItems).map { $0.object }
////  }
//
//  private let search = Search()
//  @State private var searchQuery: String = ""
//
//  @FocusState.Binding private var searchFocused: Bool
//  @Binding private var selection: HistoryItem?
//
//  init(sortOrder: [SortDescriptor<HistoryItem>]) {
//    _historyItems = Query(sort: sortOrder)
//  }
//
//  var body: some View {
//    ScrollViewReader { proxy in
//      List(historyItems, id: \.self, selection: $selection) { historyItem in
//        HStack {
//          Text(historyItem.title)
//            .lineLimit(1)
//        }
//        .id(historyItem.id.hashValue)
//        .frame(maxWidth: .infinity, alignment: .leading)
//        .onTapGesture {
//          select(historyItem)
//        }
//        .onHover { hovering in
//          if hovering {
//            selection = historyItem
//          }
//        }
//      }
//      .onKeyPress { press in
//        print(press.key, press.modifiers)
//
//        switch KeyChord(press.key, press.modifiers) {
//        case .clearHistory:
//          print("TODO: clear history")
//          return .ignored
//        case .clearHistoryAll:
//          print("TODO: clear history all")
//          return .ignored
//        case .clearSearch:
//          searchQuery = ""
//          return .handled
//        case .deleteCurrentItem:
//          delete(selection)
//          return .handled
//        case .deleteOneCharFromSearch:
//          searchFocused = true
//          Task {
//            if !searchQuery.isEmpty {
//              searchQuery.removeLast()
//            }
//          }
//          return .handled
//        case .deleteLastWordFromSearch:
//          searchFocused = true
//          Task {
//            searchQuery = searchQuery.split(separator: " ").dropLast().joined(separator: " ")
//          }
//          return .handled
//        case .moveToNext:
//          moveToNext()
//          proxy.scrollTo(selection?.id.hashValue)
//          return .handled
//        case .moveToLast:
//          selection = historyItems.last
//          proxy.scrollTo(selection?.id.hashValue)
//          return .handled
//        case .moveToPrevious:
//          moveToPrevious()
//          proxy.scrollTo(selection?.id.hashValue)
//          return .handled
//        case .moveToFirst:
//          selection = historyItems.first
//          proxy.scrollTo(selection?.id.hashValue)
//          return .handled
//        case .openPreferences:
//          openPreferences()
//          return .handled
//        case .pinOrUnpin:
//          print("TODO: pin")
//          return .handled
//        case .selectCurrentItem:
//          select(selection)
//          return .handled
//        default:
//          return .ignored
//        }
//      }
//    }
//    .onAppear {
//      selection = historyItems.first
//    }
//    .onChange(of: sortBy) {
//      print("called")
//      switch sortBy {
//      case .lastCopiedAt:
//        sortOrder = SortDescriptor(\HistoryItem.lastCopiedAt)
//      case .firstCopiedAt:
//        sortOrder = SortDescriptor(\HistoryItem.firstCopiedAt)
//      case .numberOfCopies:
//        sortOrder = SortDescriptor(\HistoryItem.numberOfCopies)
//      }
//    }
//  }
//
//  private func moveToNext() {
//    if let _selection = selection,
//       let index = historyItems.firstIndex(of: _selection),
//       let prev = historyItems[safe: historyItems.index(after: index)] {
//      selection = prev
//    }
//  }
//
//  private func moveToPrevious() {
//    if let _selection = selection,
//       let index = historyItems.firstIndex(of: _selection),
//       let prev = historyItems[safe: historyItems.index(before: index)] {
//      selection = prev
//    }
//  }
//
//  private func select(_ historyItem: HistoryItem?) {
//    guard let historyItem else { return }
//
//    searchQuery = ""
//    NSApp.hide(self)
//    Task {
//      let modifiers = modifierFlags.subtracting(.command).subtracting(.capsLock)
//      switch modifiers {
//      case HistoryMenuItem.PasteMenuItem.keyEquivalentModifierMask:
//        Clipboard.shared.copy(historyItem)
//        Clipboard.shared.paste()
//      case HistoryMenuItem.PasteWithoutFormattingMenuItem.keyEquivalentModifierMask:
//        Clipboard.shared.copy(historyItem, removeFormatting: true)
//        Clipboard.shared.paste()
//      default:
//        Clipboard.shared.copy(
//          historyItem,
//          removeFormatting: Defaults[.removeFormattingByDefault]
//        )
//        if Defaults[.pasteByDefault] {
//          Clipboard.shared.paste()
//        }
//      }
//
//      selection = historyItems.first
//    }
//  }
//
//  private func delete(_ historyItem: HistoryItem?) {
//    guard let historyItem else { return }
//
//    modelContext.delete(historyItem)
//  }
//
//  private func openPreferences() {
//    let settingsWindowController = SettingsWindowController(
//      panes: [
//        Settings.Pane(
//          identifier: Settings.PaneIdentifier.general,
//          title: NSLocalizedString("Title", tableName: "GeneralSettings", comment: ""),
//          toolbarIcon: NSImage.gearshape!
//        ) {
//          GeneralSettingsPane()
//        },
//        Settings.Pane(
//          identifier: Settings.PaneIdentifier.storage,
//          title: NSLocalizedString("Title", tableName: "StorageSettings", comment: ""),
//          toolbarIcon: NSImage.externaldrive!
//        ) {
//          StorageSettingsPane()
//        },
//        Settings.Pane(
//          identifier: Settings.PaneIdentifier.appearance,
//          title: NSLocalizedString("Title", tableName: "AppearanceSettings", comment: ""),
//          toolbarIcon: NSImage.paintpalette!
//        ) {
//          AppearanceSettingsPane()
//        },
//        Settings.Pane(
//          identifier: Settings.PaneIdentifier.ignore,
//          title: NSLocalizedString("Title", tableName: "IgnoreSettings", comment: ""),
//          toolbarIcon: NSImage.nosign!
//        ) {
//          IgnoreSettingsPane()
//        },
//        Settings.Pane(
//          identifier: Settings.PaneIdentifier.advanced,
//          title: NSLocalizedString("Title", tableName: "AdvancedSettings", comment: ""),
//          toolbarIcon: NSImage.gearshape2!
//        ) {
//          AdvancedSettingsPane()
//        }
//      ]
//    )
//    settingsWindowController.show()
//  }
//}
//
//#Preview {
//  let config = ModelConfiguration(url: URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite"))
//  let container = try! ModelContainer(for: HistoryItem.self, configurations: config)
//
//  return ContentView1()
//    .modelContainer(container)
//}
