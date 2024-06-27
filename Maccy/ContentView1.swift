import AppKit
import Defaults
import KeyboardShortcuts
import Sauce
import Settings
import SwiftData
import SwiftUI

extension Collection where Indices.Iterator.Element == Index {
  public subscript(safe index: Index) -> Iterator.Element? {
    return (startIndex <= index && index < endIndex) ? self[index] : nil
  }
}

struct KeyModifierFlags: EnvironmentKey {
  static let defaultValue = NSEvent.ModifierFlags([])
}

extension EnvironmentValues {
  var keyModifierFlags: NSEvent.ModifierFlags {
    get { self[KeyModifierFlags.self] }
    set { self[KeyModifierFlags.self] = newValue.intersection(.deviceIndependentFlagsMask) }
  }
}

struct ModifierFlagEnvironment<Content>: View where Content: View {
  @StateObject var flagState = ModifierFlags()
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .environment(\.keyModifierFlags, flagState.modifierFlags)
  }
}

final class ModifierFlags: ObservableObject {
  @Published var modifierFlags = NSEvent.ModifierFlags([])

  init() {
    NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      return event
    }
  }
}

@MainActor
class HistoryItemsViewModel: ObservableObject {
  static let shared = HistoryItemsViewModel()

  @Published private(set) var historyItems: [HistoryItemViewModel] = []
  @Published var searchQuery: String = "" {
    didSet {
      searchThrottler.throttle { [self] in
        historyItems = decorate(
          limit(
            sorter.sort(
              search.search(string: searchQuery, within: allHistoryItems).map { $0.object }
            )
          )
        )
        moveToFirst()
      }
    }
  }
  @Published var selectionUUID: UUID? = nil {
    didSet {
      selection = allItems.first { $0.id == selectionUUID }
    }
  }
  @Published var selection: (any MenuItemViewModel)? = nil
  {
    didSet {
      historyItems.forEach {
        if $0.showPreview {
          $0.showPreview = false
        }
      }
      previewThrottle.cancel()
      previewThrottle.throttle {
        if let selection = self.selection as? HistoryItemViewModel {
          self.previewThrottle.minimumDelay = self.subsequentPreviewDelay
          selection.showPreview = true
        }
      }
    }
  }

  private var allHistoryItems: [HistoryItem] {
    let descriptor = FetchDescriptor<HistoryItem>()
    return try! SwiftDataManager.shared.container.mainContext.fetch(descriptor)
  }

  var allItems: [any MenuItemViewModel] {
    var array: [any MenuItemViewModel] = []
    array.append(contentsOf: historyItems)
    array.append(contentsOf: footerItems)
    return array
  }
  var footerItems: [FooterItemViewModel] = []

  private lazy var searchThrottler = Throttler(minimumDelay: 0.1)
  private lazy var search = Search()
  private lazy var sessionLog: [Int: HistoryItem] = [:]
  private lazy var sorter = Sorter(by: Defaults[.sortBy])

  private let subsequentPreviewDelay = 0.2
  private var initialPreviewDelay: Double { Double(Defaults[.previewDelay]) / 1000 }
  private lazy var previewThrottle = Throttler(minimumDelay: initialPreviewDelay)

  init() {
    footerItems = [
      FooterItemViewModel(
        title: "clear",
        alternateTitle: "clear_all",
        key: .delete,
        modifierFlags: [.option, .command],
        alternateModifierFlags: [.option, .command, .shift],
        help: "clear_tooltip",
        alternateHelp: "clear_all_tooltip",
        needsConfirmation: true,
        select: { [self] in
          try! SwiftDataManager.shared.container.mainContext.delete(
            model: HistoryItem.self,
            where: #Predicate { $0.pin == nil }
          )
          try! SwiftDataManager.shared.container.mainContext.save()

          historyItems = decorate(
            limit(
              sorter.sort(
                search.search(string: searchQuery, within: allHistoryItems).map { $0.object }
              )
            )
          )
          moveToFirst()
        },
        alternateSelect: {
          try! SwiftDataManager.shared.container.mainContext.delete(model: HistoryItem.self)
          try! SwiftDataManager.shared.container.mainContext.save()

          self.historyItems = []
        }
      ),
      FooterItemViewModel(title: "preferences", key: .comma, modifierFlags: [.command]) {
        self.openPreferences()
      },
      FooterItemViewModel(title: "about", help: "about_tooltip") {
        About().openAbout(nil)
      },
      FooterItemViewModel(title: "quit", key: .q, modifierFlags: [.command], help: "quit_tooltip") {
        NSApp.terminate(self)
      },
    ]

    historyItems = decorate(sorter.sort(allHistoryItems))

    Task {
      for await value in Defaults.updates(.sortBy) {
        sorter = Sorter(by: value)
        historyItems = decorate(sorter.sort(historyItems.map({ $0.item })))
      }
    }
    Task {
      for await _ in Defaults.updates(.pinTo) {
        historyItems = decorate(sorter.sort(historyItems.map({ $0.item })))
      }
    }
  }

  func add(_ item: HistoryItem) {
    if let existingHistoryItem = findSimilarItem(item) {
      if isModified(item) == nil {
        item.contents = existingHistoryItem.contents
      }
      item.firstCopiedAt = existingHistoryItem.firstCopiedAt
      item.numberOfCopies += existingHistoryItem.numberOfCopies
      item.pin = existingHistoryItem.pin
      item.title = existingHistoryItem.title
      if !item.fromMaccy {
        item.application = existingHistoryItem.application
      }
      SwiftDataManager.shared.container.mainContext.delete(existingHistoryItem)
    } else {
      Task {
        Notifier.notify(body: item.title, sound: .write)
      }
    }

    sessionLog[Clipboard.shared.changeCount] = item

    var _historyItems = historyItems.map { $0.item }
    _historyItems.append(item)
    historyItems = decorate(sorter.sort(_historyItems))
  }

  func delete(_ item: (any MenuItemViewModel)?) {
    guard let item = item as? HistoryItemViewModel else { return }

    moveToNext()
    SwiftDataManager.shared.container.mainContext.delete(item.item)
    historyItems.removeAll(where: { $0 == item })
  }

  func pinOrUnpin(_ item: (any MenuItemViewModel)?) {
    guard let item = (item as? HistoryItemViewModel)?.item else { return }

    if item.pin != nil {
      item.pin = nil
    } else {
      item.pin = HistoryItem.randomAvailablePin
    }

    let _historyItems = historyItems.map { $0.item }
    historyItems = decorate(sorter.sort(_historyItems))
  }

  func resetPreviewDelay() {
    previewThrottle.minimumDelay = initialPreviewDelay
  }

  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    let descriptor = FetchDescriptor<HistoryItem>()
    if let all = try? SwiftDataManager.shared.container.mainContext.fetch(descriptor) {
      let duplicates = all.filter({ $0 == item || $0.supersedes(item) })
      if duplicates.count > 1 {
        return duplicates.first(where: { $0 != item })
      } else {
        return isModified(item)
      }
    }

    return item
  }

  private func isModified(_ item: HistoryItem) -> HistoryItem? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }

    return nil
  }

  private func decorate(_ historyItems: [HistoryItem]) -> [HistoryItemViewModel] {
    var index = 0
    return historyItems.map { item in
      if let pin = item.pin {
        return HistoryItemViewModel(item, key: Key(character: pin, virtualKeyCode: nil))
      } else if index < 9 {
        index += 1
        return HistoryItemViewModel(item, key: Key(character: String(index), virtualKeyCode: nil))
      } else {
        return HistoryItemViewModel(item)
      }
    }
  }

  private func limit(_ historyItems: [HistoryItem]) -> [HistoryItem] {
    guard Defaults[.maxMenuItems] > 0 else {
      return historyItems
    }

    var pinned = [HistoryItem]()
    var unpinned = [HistoryItem]()
    historyItems.forEach {
      if $0.pin != nil {
        pinned.append($0)
      } else {
        unpinned.append($0)
      }
    }

    return pinned + Array(unpinned.prefix(Defaults[.maxMenuItems]))
  }

  func moveToFirst() {
    selectionUUID = allItems.first?.id
  }

  func moveToPrevious() {
    if let _selection = selectionUUID,
      let index = allItems.firstIndex(where: { $0.id == _selection }),
      let prev = allItems[safe: allItems.index(before: index)]
    {
      selectionUUID = prev.id
    }
  }

  func moveToNext() {
    if let _selection = selectionUUID,
      let index = allItems.firstIndex(where: { $0.id == _selection }),
      let next = allItems[safe: allItems.index(after: index)]
    {
      selectionUUID = next.id
    }
  }

  func moveToLast() {
    selectionUUID = historyItems.last?.id
  }

  func select(_ item: (any MenuItemViewModel)?, alternate: Bool = false) {
    guard let item else { return }

    if let historyItem = item as? HistoryItemViewModel {
      NSApp.hide(self)
      let modifiers =
        (NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? [])
        .subtracting(.capsLock)
      switch modifiers {
      case HistoryMenuItem.PasteMenuItem.keyEquivalentModifierMask:
        Clipboard.shared.copy(historyItem.item)
        Clipboard.shared.paste()
      case HistoryMenuItem.PasteWithoutFormattingMenuItem.keyEquivalentModifierMask:
        Clipboard.shared.copy(historyItem.item, removeFormatting: true)
        Clipboard.shared.paste()
      default:
        Clipboard.shared.copy(
          historyItem.item,
          removeFormatting: Defaults[.removeFormattingByDefault]
        )
        if Defaults[.pasteByDefault] {
          Clipboard.shared.paste()
        }
      }
      searchQuery = ""
      moveToFirst()
    } else if let footerItem = item as? FooterItemViewModel {
      if let alternateSelect = footerItem.alternateSelect, alternate {
        alternateSelect()
      } else {
        footerItem.select()
      }
    }
  }

  func itemByShortcut() -> HistoryItemViewModel? {
    guard let event = NSApp.currentEvent else {
      return nil
    }

    let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      .subtracting(
        .capsLock
      )
    guard !modifierFlags.isEmpty else {
      return nil
    }

    guard modifierFlags == HistoryMenuItem.CopyMenuItem.keyEquivalentModifierMask ||
          modifierFlags == HistoryMenuItem.PasteMenuItem.keyEquivalentModifierMask ||
          modifierFlags == HistoryMenuItem.PasteWithoutFormattingMenuItem.keyEquivalentModifierMask else {
      return nil
    }

    let key = Sauce.shared.key(for: Int(event.keyCode))
    return historyItems.first(where: { $0.key == key })
  }

  func openPreferences() {
    let settingsWindowController = SettingsWindowController(
      panes: [
        Settings.Pane(
          identifier: Settings.PaneIdentifier.general,
          title: NSLocalizedString("Title", tableName: "GeneralSettings", comment: ""),
          toolbarIcon: NSImage.gearshape!
        ) {
          GeneralSettingsPane()
        },
        Settings.Pane(
          identifier: Settings.PaneIdentifier.storage,
          title: NSLocalizedString("Title", tableName: "StorageSettings", comment: ""),
          toolbarIcon: NSImage.externaldrive!
        ) {
          StorageSettingsPane()
        },
        Settings.Pane(
          identifier: Settings.PaneIdentifier.appearance,
          title: NSLocalizedString("Title", tableName: "AppearanceSettings", comment: ""),
          toolbarIcon: NSImage.paintpalette!
        ) {
          AppearanceSettingsPane()
        },
        Settings.Pane(
          identifier: Settings.PaneIdentifier.ignore,
          title: NSLocalizedString("Title", tableName: "IgnoreSettings", comment: ""),
          toolbarIcon: NSImage.nosign!
        ) {
          IgnoreSettingsPane()
        },
        Settings.Pane(
          identifier: Settings.PaneIdentifier.advanced,
          title: NSLocalizedString("Title", tableName: "AdvancedSettings", comment: ""),
          toolbarIcon: NSImage.gearshape2!
        ) {
          AdvancedSettingsPane()
        },
      ]
    )
    settingsWindowController.show()
  }

}

protocol MenuItemViewModel: Equatable, Hashable {
  var id: UUID { get }
}

class FooterItemViewModel: ObservableObject, Equatable, Hashable, Identifiable, MenuItemViewModel {
  static func == (lhs: FooterItemViewModel, rhs: FooterItemViewModel) -> Bool {
    return lhs.id == rhs.id
  }

  let id = UUID()

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  var title: String
  var alternateTitle: String? = nil
  var key: Key?
  var modifierFlags: NSEvent.ModifierFlags = []
  var alternateModifierFlags: NSEvent.ModifierFlags? = nil
  var help: String = ""
  var alternateHelp: String = ""
  var needsConfirmation: Bool = false
  var select: () -> Void
  var alternateSelect: (() -> Void)?

  init(
    title: String,
    alternateTitle: String? = nil,
    key: Key? = nil,
    modifierFlags: NSEvent.ModifierFlags = [],
    alternateModifierFlags: NSEvent.ModifierFlags? = nil,
    help: String = "",
    alternateHelp: String = "",
    needsConfirmation: Bool = false,
    select: @escaping () -> Void,
    alternateSelect: (() -> Void)? = nil
  ) {
    self.title = title
    self.alternateTitle = alternateTitle
    self.key = key
    self.modifierFlags = modifierFlags
    self.alternateModifierFlags = alternateModifierFlags
    self.help = help
    self.alternateHelp = alternateHelp
    self.needsConfirmation = needsConfirmation
    self.select = select
    self.alternateSelect = alternateSelect
  }

  func confirm(view: FooterItemView, suppress: Bool, closure: @escaping () -> Void) {
    guard needsConfirmation || suppress else {
      closure()
      return
    }

    view.showConfirmation = true
  }
}

class HistoryItemViewModel: ObservableObject, Equatable, Hashable, Identifiable, MenuItemViewModel {
  static func == (lhs: HistoryItemViewModel, rhs: HistoryItemViewModel) -> Bool {
    return lhs.id == rhs.id
  }

  let id = UUID()

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(key)
  }

  var title: String { item.title }
  var application: String? {
    if item.universalClipboard {
      return "iCloud"
    }

    guard let bundle = item.application,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
    else {
      return nil
    }

    return url.deletingPathExtension().lastPathComponent
  }
  var text: String {
    if !item.fileURLs.isEmpty {
      item.fileURLs
        .compactMap { $0.absoluteString.removingPercentEncoding }
        .joined(separator: "\n")
    } else if let string = item.rtf?.string {
      string
    } else if let string = item.html?.string {
      string
    } else if let string = item.text {
      string
    } else {
      item.title
    }
  }

  @Published private(set) var key: Key? = nil
  @Published var showPreview: Bool = false

  private(set) var item: HistoryItem

  init(_ item: HistoryItem, key: Key? = nil) {
    self.item = item
    self.key = key
  }
}

struct ContentView1: View {
  //  @Environment(\.keyModifierFlags) private var modifierFlags: NSEvent.ModifierFlags
  //  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase

  @StateObject private var historyItemsList = HistoryItemsViewModel.shared
  @StateObject private var modifierFlags = ModifierFlags()

  @FocusState private var searchFocused: Bool

  var body: some View {
    ScrollViewReader { proxy in
      Header(
        historyItemsList: historyItemsList,
        searchFocused: $searchFocused,
        searchQuery: $historyItemsList.searchQuery
      )

      HistoryItemsList(
        historyItemsList: historyItemsList,
        historyItems: historyItemsList.historyItems,
        footerItems: historyItemsList.footerItems,
        modifierFlags: modifierFlags,
        selection: $historyItemsList.selectionUUID,
        searchFocused: $searchFocused
      )
      .onChange(of: scenePhase) {
        if scenePhase == .active {
          historyItemsList.resetPreviewDelay()
          historyItemsList.moveToFirst()
        }
      }
      .onChange(of: historyItemsList.selectionUUID) {
        if let selection = historyItemsList.selectionUUID {
          proxy.scrollTo(selection)
        }
      }
    }
  }
}

struct Header: View {
  var historyItemsList: HistoryItemsViewModel

  @FocusState.Binding var searchFocused: Bool

  @Binding var searchQuery: String

  @Default(.showTitle) private var showTitle

  var body: some View {
    HStack {
      if showTitle {
        Text("Maccy")
      }

      TextField(text: $searchQuery) {
        Text("type to search")
      }
      .disableAutocorrection(true)
      .textFieldStyle(.roundedBorder)
      .focusEffectDisabled()
      .focused($searchFocused)
      .onKeyPress { press in
        switch KeyChord(press.key, press.modifiers) {
        case .clearHistory:
          historyItemsList.select(historyItemsList.footerItems.first { $0.title == "clear" })
          return .handled
        case .clearHistoryAll:
          historyItemsList.select(
            historyItemsList.footerItems.first { $0.title == "clear" },
            alternate: true
          )
          return .handled
        case .deleteCurrentItem:
          historyItemsList.delete(historyItemsList.selection)
          return .handled
        case .deleteLastWordFromSearch:
          searchFocused = true
          historyItemsList.searchQuery = historyItemsList.searchQuery.split(separator: " ")
            .dropLast()
            .joined(
              separator: " "
            )
          return .handled
        case .moveToNext:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          historyItemsList.moveToNext()
          return .handled
        case .moveToLast:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          historyItemsList.moveToLast()
          return .handled
        case .moveToPrevious:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          historyItemsList.moveToPrevious()
          return .handled
        case .moveToFirst:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          historyItemsList.moveToFirst()
          return .handled
        case .openPreferences:
          historyItemsList.openPreferences()
          return .handled
        case .pinOrUnpin:
          historyItemsList.pinOrUnpin(historyItemsList.selection)
          return .handled
        case .selectCurrentItem:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          if historyItemsList.selection != nil {
            // TODO: Handle alternate
            historyItemsList.select(historyItemsList.selection)
          } else {
            Clipboard.shared.copy(historyItemsList.searchQuery)
            historyItemsList.searchQuery = ""
          }
          return .handled
        default:
          ()
        }

        if let item = historyItemsList.itemByShortcut() {
          historyItemsList.selectionUUID = item.id
          Task {
            try! await Task.sleep(for: .milliseconds(50))
            historyItemsList.select(item)
          }
          return .handled
        }

        return .ignored
      }
    }
    //    .background(.random)
    .padding(.horizontal)
  }
}

extension ShapeStyle where Self == Color {
  static var random: Color {
    Color(
      red: .random(in: 0...1),
      green: .random(in: 0...1),
      blue: .random(in: 0...1)
    )
  }
}

struct HistoryItemsList: View {
  var historyItemsList: HistoryItemsViewModel
  var historyItems: [HistoryItemViewModel]
  var footerItems: [FooterItemViewModel]
  var modifierFlags: ModifierFlags

  @Binding var selection: UUID?
  @FocusState.Binding var searchFocused: Bool

  @Default(.pasteByDefault) private var pasteByDefault
  @Default(.removeFormattingByDefault) private var removeFormattingByDefault
  @Default(.showFooter) private var showFooter

  var body: some View {
    List(selection: $selection) {
      ForEach(historyItems, id: \.id) { historyItem in
        if historyItem.key != nil {
          ShortcutHistoryItemView(
            historyItem: historyItem,
            modifierFlags: modifierFlags,
            historyItemsList: historyItemsList
          )
          .listRowSeparator(.hidden)
        } else {
          HistoryItemView(
            historyItem: historyItem,
            historyItemsList: historyItemsList
          )
          .listRowSeparator(.hidden)
        }
      }

      if showFooter {
        Divider()
        ForEach(footerItems, id: \.id) { footerItem in
          FooterItemView(
            item: footerItem,
            modifierFlags: modifierFlags,
            historyItemsList: historyItemsList
          )
          .listRowSeparator(.hidden)
        }
      }
    }
    .onKeyPress { press in
      switch KeyChord(press.key, press.modifiers) {
      case .clearHistory:
        historyItemsList.select(historyItemsList.footerItems.first { $0.title == "clear" })
        return .handled
      case .clearHistoryAll:
        historyItemsList.select(historyItemsList.footerItems.first { $0.title == "clear_all" })
        return .handled
      case .clearSearch:
        historyItemsList.searchQuery = ""
        return .handled
      case .deleteCurrentItem:
        historyItemsList.delete(historyItemsList.selection)
        return .handled
      case .deleteOneCharFromSearch:
        searchFocused = true
        if !historyItemsList.searchQuery.isEmpty {
          historyItemsList.searchQuery.removeLast()
        }
        return .handled
      case .deleteLastWordFromSearch:
        searchFocused = true
        historyItemsList.searchQuery = historyItemsList.searchQuery.split(separator: " ").dropLast()
          .joined(
            separator: " "
          )
        return .handled
      case .moveToNext:
        historyItemsList.moveToNext()
        return .handled
      case .moveToLast:
        historyItemsList.moveToLast()
        return .handled
      case .moveToPrevious:
        historyItemsList.moveToPrevious()
        return .handled
      case .moveToFirst:
        historyItemsList.moveToFirst()
        return .handled
      case .openPreferences:
        historyItemsList.openPreferences()
        return .handled
      case .pinOrUnpin:
        historyItemsList.pinOrUnpin(historyItemsList.selection)
        return .handled
      case .selectCurrentItem:
        // TODO: Handle alternate
        historyItemsList.select(historyItemsList.selection)
        return .handled
      default:
        ()
      }

      if let item = historyItemsList.itemByShortcut() {
        historyItemsList.selectionUUID = item.id
        Task {
          try! await Task.sleep(for: .milliseconds(50))
          historyItemsList.select(item)
        }
        return .handled
      }

      guard press.characters.count == 1 else {
        return .ignored
      }

      historyItemsList.searchQuery = historyItemsList.searchQuery.appending(press.characters)
      searchFocused = true
      return .handled
    }
  }
}

struct ShortcutHistoryItemView: View {
  @ObservedObject var historyItem: HistoryItemViewModel
  @ObservedObject var modifierFlags: ModifierFlags

  @Default(.pasteByDefault) private var pasteByDefault
  @Default(.removeFormattingByDefault) private var removeFormattingByDefault

  var historyItemsList: HistoryItemsViewModel

  private var shortcutText: String {
    if let key = historyItem.key,
      let character = Sauce.shared.character(for: Int(key.QWERTYKeyCode), cocoaModifiers: [])?
        .capitalized
    {
      if modifierFlags.modifierFlags.contains(.option) {
        if modifierFlags.modifierFlags.contains(.shift) && !pasteByDefault {
          return "⌥⇧\(character)"
        } else {
          return "⌥\(character)"
        }
      } else {
        if modifierFlags.modifierFlags.contains(.shift) && pasteByDefault {
          return "⇧⌘\(character)"
        } else {
          return "⌘\(character)"
        }
      }
    }

    return ""
  }

  @Default(.imageMaxHeight) private var imageMaxHeight

  var body: some View {
    HStack {
      if let image = historyItem.item.image {
        Image
          .thumbnailImage(image, maxHeight: imageMaxHeight)
      } else {
        Text(historyItem.title)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundColor(.primary)
      }
      Spacer()
      Text(shortcutText)
        .lineLimit(1)
        .foregroundColor(.secondary)
        .frame(width: 45, alignment: .trailing)
        .tracking(2.0)
        .opacity(shortcutText.isEmpty ? 0 : 1)
    }
    .id(historyItem.id)
    .frame(maxWidth: .infinity, alignment: .leading)
    .onTapGesture {
      historyItemsList.select(historyItem)
    }
    .onHover { hovering in
      if hovering {
        historyItemsList.selectionUUID = historyItem.id
      }
    }
    .popover(
      isPresented: $historyItem.showPreview,
      attachmentAnchor: .point(.leading),
      arrowEdge: .leading
    ) {
      PreviewView(historyItem: historyItem)
    }
  }
}

struct FooterItemView: View {
  var item: FooterItemViewModel
  @ObservedObject var modifierFlags: ModifierFlags

  var historyItemsList: HistoryItemsViewModel

  var isAlternate: Bool {
    if let alternateModifierFlags = item.alternateModifierFlags,
      !modifierFlags.modifierFlags.isEmpty,
      modifierFlags.modifierFlags.contains(alternateModifierFlags.subtracting(item.modifierFlags))
    {
      return true
    }

    return false
  }

  private var title: String {
    if let alternateTitle = item.alternateTitle, isAlternate {
      return alternateTitle
    } else {
      return item.title
    }
  }
  private var shortcutText: String {
    if let key = item.key,
      let character = Sauce.shared.character(for: Int(key.QWERTYKeyCode), cocoaModifiers: [])?
        .capitalized
    {
      if let alternateModifierFlags = item.alternateModifierFlags, isAlternate {
        return "\(alternateModifierFlags)\(character)"
      } else {
        return "\(item.modifierFlags)\(character)"
      }
    }

    return ""
  }

  @Default(.suppressClearAlert) private var suppressClearAlert
  @State var showConfirmation: Bool = false

  var body: some View {
    HStack {
      Text(LocalizedStringKey(title))
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundColor(.primary)

      Spacer()
      Text(shortcutText)
        .lineLimit(1)
        .foregroundColor(.secondary)
        .frame(width: 60, alignment: .trailing)
        .tracking(2.0)
        .opacity(shortcutText.isEmpty ? 0 : 1)
    }
    .id(item.id)
    .frame(maxWidth: .infinity, alignment: .leading)
    .onTapGesture {
      item.confirm(view: self, suppress: suppressClearAlert) {
        self.historyItemsList.select(item, alternate: isAlternate)
      }
    }
    .onHover { hovering in
      if hovering {
        historyItemsList.selectionUUID = item.id
      }
    }
    .help(LocalizedStringKey(isAlternate ? item.alternateHelp : item.help))
    .confirmationDialog("clear_alert_message", isPresented: $showConfirmation) {
      Text("clear_alert_comment")
      Button("clear_alert_confirm", role: .destructive) {
        // TODO: Support alernate
        historyItemsList.select(item, alternate: isAlternate)
      }
      Button("clear_alert_cancel", role: .cancel) {}
    }
    .dialogSuppressionToggle(isSuppressed: $suppressClearAlert)
  }
}

struct HistoryItemView: View {
  @ObservedObject var historyItem: HistoryItemViewModel

  var historyItemsList: HistoryItemsViewModel

  @Default(.imageMaxHeight) private var imageMaxHeight

  var body: some View {
    HStack {
      if let image = historyItem.item.image {
        Image
          .thumbnailImage(image, maxHeight: imageMaxHeight)
      } else {
        Text(historyItem.title)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundColor(.primary)
      }
      Spacer()
      Text("    ")
        .lineLimit(1)
        .foregroundColor(.secondary)
        .frame(width: 45, alignment: .trailing)
        .tracking(2.0)
        .opacity(0)
    }
    .id(historyItem.item.id.hashValue)
    .frame(maxWidth: .infinity, alignment: .leading)
    .onTapGesture {
      historyItemsList.select(historyItem)
    }
    .onHover { hovering in
      if hovering {
        historyItemsList.selectionUUID = historyItem.id
      }
    }
    .popover(
      isPresented: $historyItem.showPreview,
      attachmentAnchor: .point(.leading),
      arrowEdge: .leading
    ) {
      PreviewView(historyItem: historyItem)
    }
  }
}

struct PreviewView: View {
  @ObservedObject var historyItem: HistoryItemViewModel

  var body: some View {
    VStack(alignment: .leading) {
      if let image = historyItem.item.image {
        Image(nsImage: image)
        Divider()
      } else {
        Text(historyItem.text)
          .controlSize(.regular)
        Divider()
      }

      if let application = historyItem.application {
        HStack(spacing: 3) {
          Text("Application", tableName: "Preview")
          Text(application)
        }
      }

      HStack(spacing: 3) {
        Text("FirstCopyTime", tableName: "Preview")
        Text(historyItem.item.firstCopiedAt, style: .date)
        Text(historyItem.item.firstCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("LastCopyTime", tableName: "Preview")
        Text(historyItem.item.lastCopiedAt, style: .date)
        Text(historyItem.item.lastCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("NumberOfCopies", tableName: "Preview")
        Text(String(historyItem.item.numberOfCopies))
      }
      Divider()

      if let pinKey = KeyboardShortcuts.Shortcut(name: .pin) {
        Text(
          NSLocalizedString("PinKey", tableName: "Preview", comment: "")
            .replacingOccurrences(of: "{pinKey}", with: pinKey.description)
        )
      }

      if let deleteKey = KeyboardShortcuts.Shortcut(name: .delete) {
        Text(
          NSLocalizedString("DeleteKey", tableName: "Preview", comment: "")
            .replacingOccurrences(of: "{deleteKey}", with: deleteKey.description)
        )
      }
    }
    .controlSize(.small)
    .padding()
  }
}

extension Image {
  static func thumbnailImage(_ image: NSImage, maxHeight: Int, maxWidth: Int = 340) -> Image {
    let imageMaxWidth = CGFloat(maxWidth)
    if image.size.width > imageMaxWidth {
      image.size.height /= image.size.width / imageMaxWidth
      image.size.width = imageMaxWidth
    }

    let imageMaxHeight = CGFloat(maxHeight)
    if image.size.height > imageMaxHeight {
      image.size.width /= image.size.height / imageMaxHeight
      image.size.height = imageMaxHeight
    }
    return Image(nsImage: image)
  }
}

#Preview {
  let config = ModelConfiguration(
    url: URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")
  )
  let container = try! ModelContainer(for: HistoryItem.self, configurations: config)

  return ContentView1()
    .modelContainer(container)
}
