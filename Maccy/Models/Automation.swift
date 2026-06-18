import Defaults
import Foundation

// A user-configured rule that runs an action when copied text matches a regular expression.
//
// Persisted as configuration via the `Defaults` library (like `ignoreRegexp`), not SwiftData.
// `Defaults.Serializable` is free for `Codable` types, and arrays of serializable values are
// themselves serializable, so `Defaults.Key<[Automation]>` works out of the box.
struct Automation: Identifiable, Codable, Hashable, Defaults.Serializable {
  var id = UUID()
  var name = ""
  var regexp = ""
  var isEnabled = true
  var action: AutomationAction = .runScript(RunScriptConfig())

  // Returns true when `text` matches `regexp`. An empty or invalid pattern never matches.
  func matches(_ text: String) -> Bool {
    guard !regexp.isEmpty, let regex = try? NSRegularExpression(pattern: regexp) else {
      return false
    }

    let range = NSRange(text.startIndex..., in: text)
    return regex.numberOfMatches(in: text, range: range) > 0
  }
}

// The action performed when an automation matches. New actions are added as new cases.
enum AutomationAction: Codable, Hashable {
  case runScript(RunScriptConfig)
}

struct RunScriptConfig: Codable, Hashable {
  var scriptName = ""          // filename within the Application Scripts directory
  var parseResultAsHTML = false
}

// Convenience accessors so SwiftUI can bind directly to action fields. They no-op for
// automations whose action is not `.runScript`, which keeps the editor bindings simple while
// the action set is small.
extension Automation {
  var scriptName: String {
    get {
      guard case let .runScript(config) = action else { return "" }
      return config.scriptName
    }
    set {
      guard case var .runScript(config) = action else { return }
      config.scriptName = newValue
      action = .runScript(config)
    }
  }

  var parseResultAsHTML: Bool {
    get {
      guard case let .runScript(config) = action else { return false }
      return config.parseResultAsHTML
    }
    set {
      guard case var .runScript(config) = action else { return }
      config.parseResultAsHTML = newValue
      action = .runScript(config)
    }
  }
}
