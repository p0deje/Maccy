import AppKit.NSEvent
import Defaults

enum HistoryItemAction {
  case unknown
  case copy
  case paste
  case pasteWithoutFormatting

  init(_ modifierFlags: NSEvent.ModifierFlags) {
    switch modifierFlags {
    case .command where !Defaults[.pasteByDefault]:
      self = .copy
    case .command where Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault]:
      self = .paste
    case .command where Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault]:
      self = .pasteWithoutFormatting
    case .option where !Defaults[.pasteByDefault]:
      self = .paste
    case .option where Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault]:
      self = .copy
    case [.option, .shift] where !Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault]:
      self = .pasteWithoutFormatting
    case [.option, .shift] where !Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault]:
      self = .paste
    case [.command, .shift] where Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault]:
      self = .pasteWithoutFormatting
    case [.command, .shift] where Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault]:
      self = .paste
    default:
      self = .unknown
    }
  }
}
