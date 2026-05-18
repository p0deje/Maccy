import AppKit
import Defaults
import Foundation
import KeyboardShortcuts

final class QuickPaste {
  static let shared = QuickPaste()

  private init() {}

  func register() {
    QuickPasteSettings.bootstrap()

    for (index, name) in KeyboardShortcuts.Name.quickPastes.enumerated() {
      KeyboardShortcuts.onKeyDown(for: name) {
        let destination = Clipboard.shared.pasteDestination()
        Task { @MainActor in
          QuickPaste.shared.paste(at: index + 1, into: destination)
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.enableQuickPaste) {
        updateEnabledState()
      }
    }

    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name,
            KeyboardShortcuts.Name.quickPastes.contains(name) else {
        return
      }

      self?.updateEnabledState()
    }

    updateEnabledState()
  }

  @MainActor
  private func paste(at index: Int, into destination: NSRunningApplication?) {
    guard Defaults[.enableQuickPaste] else { return }
    guard !Defaults[.ignoreEvents] else { return }

    History.shared.quickPaste(at: index, into: destination)
  }

  private func updateEnabledState() {
    if Defaults[.enableQuickPaste] {
      KeyboardShortcuts.enable(KeyboardShortcuts.Name.quickPastes)
    } else {
      KeyboardShortcuts.disable(KeyboardShortcuts.Name.quickPastes)
    }
  }
}
