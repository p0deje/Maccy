import AppKit
import Defaults
import Foundation
import Settings
import SwiftUI

@Observable
class AppState: Sendable {
  static let shared = AppState(history: History.shared, footer: Footer(), todos: Todos.shared)

  var multiSelectionEnabled: Bool { Defaults[.enablePasteStack] }

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var todos: Todos
  var footer: Footer
  var navigator: NavigationManager
  var preview: SlideoutController
  var activeTab: AppTab = .clipboard

  /// The floating panel that is actually showing the active tab (main popup or standalone todos window).
  var activeFloatingPanel: NSWindow? {
    appDelegate?.floatingPanel(for: activeTab)
  }

  var searchVisible: Bool {
    if !Defaults[.showSearch] { return false }
    switch Defaults[.searchVisibility] {
    case .always: return true
    case .duringSearch:
      switch activeTab {
      case .clipboard: return !history.searchQuery.isEmpty
      case .todos: return !todos.searchQuery.isEmpty
      }
    }
  }

  var menuIconText: String {
    var title = history.unpinnedItems.first?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  private let about = About()
  private var settingsWindowController: SettingsWindowController?

  init(history: History, footer: Footer, todos: Todos) {
    self.history = history
    self.todos = todos
    self.footer = footer
    popup = Popup()
    navigator = NavigationManager(history: history, footer: footer)
    preview = SlideoutController(
      onContentResize: { contentWidth in
        Defaults[.windowSize].width = contentWidth
      },
      onSlideoutResize: { previewWidth in
        Defaults[.previewWidth] = previewWidth
      })
    preview.contentWidth = Defaults[.windowSize].width
    preview.slideoutWidth = Defaults[.previewWidth]
  }

  @MainActor
  func setActiveTab(_ tab: AppTab) {
    guard activeTab != tab else { return }

    if preview.state.isOpen {
      preview.togglePreview(trigger: .autoOpen)
    }

    activeTab = tab

    switch tab {
    case .todos:
      prepareTodosTab()
    case .clipboard:
      preview.enableAutoOpen()
      if navigator.leadHistoryItem != nil || navigator.pasteStackSelected {
        preview.resetAutoOpenSuppression()
        preview.startAutoOpen()
      }
    }
  }

  @MainActor
  func prepareTodosTab() {
    preview.placement = .left
    preview.enableAutoOpen()
    todos.isKeyboardNavigating = false
    if !preview.state.isOpen, let window = activeFloatingPanel {
      if preview.contentResizeWidth > 0 {
        preview.contentWidth = preview.contentResizeWidth
      } else {
        preview.contentWidth = window.frame.width.rounded()
      }
    }
    if todos.selectedItem != nil {
      preview.resetAutoOpenSuppression()
      preview.startAutoOpen()
    }
  }

  @MainActor
  func select() {
    if !navigator.selection.isEmpty {
      if navigator.isMultiSelectInProgress {
        navigator.isManualMultiSelect = false
        history.startPasteStack(selection: &navigator.selection)
      } else {
        history.select(navigator.selection.first)
      }
    } else if let item = footer.selectedItem {
      // TODO: Use item.suppressConfirmation, but it's not updated!
      if item.confirmation != nil, Defaults[.suppressClearAlert] == false {
        item.showConfirmation = true
      } else {
        item.action()
      }
    } else {
      Clipboard.shared.copyInMaccy(history.searchQuery)
      history.searchQuery = ""
    }
  }

  @MainActor
  func togglePin() {
    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.togglePin(item)
      }
    }
  }

  @MainActor
  func removePasteStack() {
    history.interruptPasteStack()
    navigator.highlightFirst()
  }

  @MainActor
  func deleteSelection() {
    guard let leadItem = navigator.leadHistoryItem else { return }
    let nextUnselectedItem = history.visibleItems.nearest(to: leadItem) { !$0.isSelected }

    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.delete(item)
      }
      navigator.select(item: nextUnselectedItem)
    }
  }

  /// Creates a todo from a clipboard history item and switches to the Todos tab.
  @MainActor
  func addToTodos(from item: HistoryItemDecorator) {
    let sourceText = item.title.isEmpty ? item.text : item.title
    let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = trimmed.shortened(to: 200)

    let todo = todos.add(title: title)

    let fullText = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !fullText.isEmpty, fullText != title {
      todo.notes = fullText
      todos.update(todo)
    }

    setActiveTab(.todos)
  }

  @MainActor
  func addSelectionToTodos() {
    guard let item = navigator.leadHistoryItem ?? navigator.selection.first else { return }
    addToTodos(from: item)
  }

  func openAbout() {
    about.openAbout(nil)
  }

  @MainActor
  func openPreferences() { // swiftlint:disable:this function_body_length
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController(
        panes: [
          Settings.Pane(
            identifier: Settings.PaneIdentifier.general,
            title: NSLocalizedString("Title", tableName: "GeneralSettings", comment: ""),
            toolbarIcon: NSImage.gearshape
          ) {
            GeneralSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.quickPaste,
            title: NSLocalizedString("Title", tableName: "QuickPasteSettings", comment: ""),
            toolbarIcon: NSImage.quickPaste
          ) {
            QuickPasteSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.todos,
            title: NSLocalizedString("Title", tableName: "TodoSettings", comment: ""),
            toolbarIcon: NSImage.checklist
          ) {
            TodoSettingsPane()
              .modelContainer(Storage.shared.container)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.storage,
            title: NSLocalizedString("Title", tableName: "StorageSettings", comment: ""),
            toolbarIcon: NSImage.externaldrive
          ) {
            StorageSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.appearance,
            title: NSLocalizedString("Title", tableName: "AppearanceSettings", comment: ""),
            toolbarIcon: NSImage.paintpalette
          ) {
            AppearanceSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.pins,
            title: NSLocalizedString("Title", tableName: "PinsSettings", comment: ""),
            toolbarIcon: NSImage.pincircle
          ) {
            PinsSettingsPane()
              .environment(self)
              .modelContainer(Storage.shared.container)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.ignore,
            title: NSLocalizedString("Title", tableName: "IgnoreSettings", comment: ""),
            toolbarIcon: NSImage.nosign
          ) {
            IgnoreSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.advanced,
            title: NSLocalizedString("Title", tableName: "AdvancedSettings", comment: ""),
            toolbarIcon: NSImage.gearshape2
          ) {
            AdvancedSettingsPane()
          }
        ]
      )
      if let window = settingsWindowController?.window {
        ResizableSettingsWindowDelegate.shared.configure(window)
      }
    }
    settingsWindowController?.show()
    settingsWindowController?.window?.orderFrontRegardless()
  }

  func quit() {
    NSApp.terminate(self)
  }
}
