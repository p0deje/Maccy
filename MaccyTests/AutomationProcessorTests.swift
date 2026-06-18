import XCTest
import Defaults
@testable import Maccy

private final class StubScriptRunner: ScriptRunning {
  var transform: (_ scriptName: String, _ input: String) throws -> String
  private(set) var calls: [(script: String, input: String)] = []

  init(transform: @escaping (_ scriptName: String, _ input: String) throws -> String = { _, input in input }) {
    self.transform = transform
  }

  func run(scriptName: String, input: String) async throws -> String {
    calls.append((scriptName, input))
    return try transform(scriptName, input)
  }
}

@MainActor
class AutomationProcessorTests: XCTestCase {
  private var processor: AutomationProcessor!
  private var stub: StubScriptRunner!

  override func setUp() {
    super.setUp()
    processor = AutomationProcessor()
    stub = StubScriptRunner()
    processor.scriptRunner = stub
  }

  override func tearDown() {
    Defaults.reset(.automations)
    super.tearDown()
  }

  func testNoMatchReturnsNil() async {
    Defaults[.automations] = [automation(regexp: "nomatch", script: "s.sh")]
    let result = await processor.buildResult(forText: "hello", source: nil)
    XCTAssertNil(result)
    XCTAssertTrue(stub.calls.isEmpty)
  }

  func testPlainResult() async {
    stub.transform = { _, input in input.uppercased() }
    Defaults[.automations] = [automation(regexp: ".*", script: "up.sh")]

    let result = await processor.buildResult(forText: "foo", source: "com.example")
    XCTAssertEqual(result?.text, "FOO")
    XCTAssertNil(result?.html)
    XCTAssertEqual(result?.application, "com.example")
  }

  func testHTMLResultParsesRichTextWithPlainFallback() async {
    stub.transform = { _, _ in "<a href=\"#\">foo</a>" }
    Defaults[.automations] = [automation(regexp: ".*", script: "link.sh", parseAsHTML: true)]

    let result = await processor.buildResult(forText: "foo", source: nil)
    XCTAssertNotNil(result?.html)
    XCTAssertEqual(result?.html?.string, "foo")
    XCTAssertEqual(result?.text, "foo") // plain-text fallback
  }

  func testChainingProducesSingleItemInOrder() async {
    stub.transform = { script, input in
      switch script {
      case "up.sh": return input.uppercased()
      case "wrap.sh": return "[\(input)]"
      default: return input
      }
    }
    Defaults[.automations] = [
      automation(regexp: ".*", script: "up.sh"),
      automation(regexp: ".*", script: "wrap.sh")
    ]

    let result = await processor.buildResult(forText: "foo", source: nil)
    XCTAssertEqual(result?.text, "[FOO]")
    XCTAssertEqual(stub.calls.map(\.script), ["up.sh", "wrap.sh"])
    XCTAssertEqual(stub.calls.map(\.input), ["foo", "FOO"])
  }

  func testTrailingNewlinesAreTrimmed() async {
    stub.transform = { _, input in "\(input.uppercased())\n\n" }
    Defaults[.automations] = [automation(regexp: ".*", script: "up.sh")]

    let result = await processor.buildResult(forText: "foo", source: nil)
    XCTAssertEqual(result?.text, "FOO")
  }

  func testUnchangedOutputReturnsNil() async {
    stub.transform = { _, input in input }
    Defaults[.automations] = [automation(regexp: ".*", script: "noop.sh")]

    let result = await processor.buildResult(forText: "foo", source: nil)
    XCTAssertNil(result)
  }

  func testScriptFailureReturnsNil() async {
    stub.transform = { _, _ in throw ScriptRunnerError.notFound("up.sh") }
    Defaults[.automations] = [automation(regexp: ".*", script: "up.sh")]

    let result = await processor.buildResult(forText: "foo", source: nil)
    XCTAssertNil(result)
  }

  func testDisabledAutomationsAreSkipped() async {
    stub.transform = { _, input in input.uppercased() }
    Defaults[.automations] = [automation(regexp: ".*", script: "up.sh", enabled: false)]

    let result = await processor.buildResult(forText: "foo", source: nil)
    XCTAssertNil(result)
    XCTAssertTrue(stub.calls.isEmpty)
  }

  func testShouldProcessSkipsFromMaccyAndEmptyText() {
    let fromMaccy = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data("foo".utf8)),
      HistoryItemContent(type: NSPasteboard.PasteboardType.fromMaccy.rawValue, value: Data())
    ])
    XCTAssertFalse(processor.shouldProcess(fromMaccy))

    let imageOnly = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue, value: Data([0x1]))
    ])
    XCTAssertFalse(processor.shouldProcess(imageOnly))

    let text = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data("foo".utf8))
    ])
    XCTAssertTrue(processor.shouldProcess(text))
  }

  private func automation(
    regexp: String,
    script: String,
    parseAsHTML: Bool = false,
    enabled: Bool = true
  ) -> Automation {
    Automation(
      name: script,
      regexp: regexp,
      isEnabled: enabled,
      action: .runScript(RunScriptConfig(scriptName: script, parseResultAsHTML: parseAsHTML))
    )
  }
}
