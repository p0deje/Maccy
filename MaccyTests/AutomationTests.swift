import XCTest
import Defaults
@testable import Maccy

class AutomationTests: XCTestCase {
  func testMatches() {
    let automation = Automation(regexp: "^https://github\\.com/.+/pull/\\d+")
    XCTAssertTrue(automation.matches("https://github.com/p0deje/Maccy/pull/123"))
    XCTAssertFalse(automation.matches("https://example.com"))
  }

  func testEmptyRegexpNeverMatches() {
    let automation = Automation(regexp: "")
    XCTAssertFalse(automation.matches("anything"))
  }

  func testInvalidRegexpNeverMatches() {
    let automation = Automation(regexp: "[")
    XCTAssertFalse(automation.matches("anything"))
  }

  func testActionAccessors() {
    var automation = Automation(action: .runScript(RunScriptConfig()))
    automation.scriptName = "foo.sh"
    automation.parseResultAsHTML = true

    XCTAssertEqual(automation.scriptName, "foo.sh")
    XCTAssertTrue(automation.parseResultAsHTML)
    XCTAssertEqual(automation.action, .runScript(RunScriptConfig(scriptName: "foo.sh", parseResultAsHTML: true)))
  }

  func testDefaultsRoundTrip() {
    let automation = Automation(
      name: "GitHub",
      regexp: "foo",
      action: .runScript(RunScriptConfig(scriptName: "s.sh", parseResultAsHTML: true))
    )

    Defaults[.automations] = [automation]
    XCTAssertEqual(Defaults[.automations], [automation])

    Defaults.reset(.automations)
  }
}
