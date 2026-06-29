import AppKit.NSEvent
import Defaults

/// The action taken on a history item when the user activates it, derived from
/// the pressed modifiers and the paste/remove-formatting defaults.
enum HistoryItemAction {
  case unknown
  case copy
  case paste
  case pasteWithoutFormatting

  /// Resolves the action for the given modifier flags.
  init(_ modifierFlags: NSEvent.ModifierFlags) {  // swiftlint:disable:this cyclomatic_complexity
    switch modifierFlags {
    case .command where !Defaults[.pasteByDefault]:
      self = .copy
    case .command where Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault]:
      self = .paste
    case .command where Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault]:
      self = .pasteWithoutFormatting
    case .option where !Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault]:
      self = .paste
    case .option where !Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault]:
      self = .pasteWithoutFormatting
    case .option where Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault]:
      self = .copy
    case .option where Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault]:
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

  /// The modifier flags that map back to this action under the current
  /// defaults, or empty when no mapping applies.
  var modifierFlags: NSEvent.ModifierFlags {
    switch self {
    case .copy where !Defaults[.pasteByDefault]:
      return .command
    case .paste where Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault]:
      return .command
    case .pasteWithoutFormatting where Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault]:
      return .command
    case .paste where !Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault]:
      return .option
    case .pasteWithoutFormatting where !Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault]:
      return .option
    case .copy where Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault]:
      return .option
    case .copy where Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault]:
      return .option
    case .pasteWithoutFormatting where !Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault]:
      return [.option, .shift]
    case .paste where !Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault]:
      return [.option, .shift]
    case .pasteWithoutFormatting where Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault]:
      return [.command, .shift]
    case .paste where Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault]:
      return [.command, .shift]
    default:
      return []
    }
  }
}
