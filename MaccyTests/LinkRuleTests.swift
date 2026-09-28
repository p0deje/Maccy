import XCTest
@testable import Maccy

class LinkRuleTests: XCTestCase {
  func testJiraTicketMatches() {
    XCTAssertEqual(
      LinkOpener.url(for: "ABC-123", rules: [.jira])?.absoluteString,
      "https://strategyagile.atlassian.net/browse/ABC-123"
    )
    XCTAssertEqual(
      LinkOpener.url(for: "  DE2-7\n", rules: [.jira])?.absoluteString,
      "https://strategyagile.atlassian.net/browse/DE2-7"
    )
  }

  func testJiraRejectsNonTickets() {
    for text in ["abc-123", "ABC-", "ABC123", "see ABC-123", "A-1", ""] {
      XCTAssertNil(LinkOpener.url(for: text, rules: [.jira]), text)
    }
  }

  func testCaptureGroupsAndEncoding() {
    let rule = LinkRule(
      name: "gh",
      pattern: "^(\\w+)/(\\w+)#(\\d+)$",
      urlTemplate: "https://github.com/{1}/{2}/issues/{3}"
    )
    XCTAssertEqual(
      LinkOpener.url(for: "p0deje/Maccy#42", rules: [rule])?.absoluteString,
      "https://github.com/p0deje/Maccy/issues/42"
    )

    let search = LinkRule(name: "s", pattern: "^.+$", urlTemplate: "https://example.com/{match}")
    XCTAssertEqual(LinkOpener.url(for: "a b", rules: [search])?.absoluteString, "https://example.com/a%20b")
  }

  func testDisabledAndInvalidRulesAreSkipped() {
    var disabled = LinkRule.jira
    disabled.enabled = false
    let invalid = LinkRule(name: "bad", pattern: "(", urlTemplate: "https://x/{0}")
    XCTAssertNil(LinkOpener.url(for: "ABC-1", rules: [disabled, invalid]))
  }

  func testFirstMatchWins() {
    let other = LinkRule(name: "o", pattern: "^.+$", urlTemplate: "https://other/{0}")
    XCTAssertEqual(LinkOpener.url(for: "ABC-1", rules: [.jira, other])?.host, "strategyagile.atlassian.net")
  }
}
