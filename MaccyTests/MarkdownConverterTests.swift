import XCTest
@testable import Maccy

class MarkdownConverterTests: XCTestCase {
  private func html(_ value: String) -> [HistoryItemContent] {
    [HistoryItemContent(type: NSPasteboard.PasteboardType.html.rawValue, value: value.data(using: .utf8))]
  }

  private func string(_ value: String) -> [HistoryItemContent] {
    [HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: value.data(using: .utf8))]
  }

  func testBoldText() {
    let contents = html("<p>Sdfsfsd <b>sfsf</b> sd d</p>")
    XCTAssertEqual(MarkdownConverter.convert(contents), "Sdfsfsd **sfsf** sd d")
  }

  func testItalicText() {
    let contents = html("<p>foo <i>bar</i> baz</p>")
    XCTAssertEqual(MarkdownConverter.convert(contents), "foo *bar* baz")
  }

  func testLink() {
    let contents = html("<a href=\"https://maccy.app\">Maccy</a>")
    XCTAssertEqual(MarkdownConverter.convert(contents), "[Maccy](https://maccy.app)")
  }

  func testUnorderedList() {
    let contents = html("<ul><li>foo</li><li>bar</li></ul>")
    XCTAssertEqual(MarkdownConverter.convert(contents), "- foo\n- bar")
  }

  func testWordWrappedTextHasNoStrayLineBreak() {
    // Word's clipboard HTML is hard-wrapped with \r\n, which used to leak into the output.
    let contents = html("<p>Sdfsfsd\r\n<b>sfsf</b> sd d</p>")
    XCTAssertEqual(MarkdownConverter.convert(contents), "Sdfsfsd **sfsf** sd d")
  }

  func testExcelTable() {
    // Excel's clipboard HTML includes non-self-closed <col> tags before the rows,
    // and no <th>, so the first row's <td> cells must be promoted to <th>.
    let contents = html("""
    <table>
     <col width=647>
     <col width=233>
     <tr><td>Name</td><td>Contact</td></tr>
     <tr><td>No</td><td>Kevin Pakieser</td></tr>
     <tr><td>No</td><td>John Gagnon</td></tr>
    </table>
    """)
    XCTAssertEqual(
      MarkdownConverter.convert(contents),
      "| Name | Contact |\n|---|---|\n| No | Kevin Pakieser |\n| No | John Gagnon |"
    )
  }

  func testExcelTableWithoutHeaderRowStillGetsFirstRowPromoted() {
    // If the copied range has no distinct header row, the first row still
    // becomes the Markdown header, since there is no way to tell them apart.
    let contents = html("""
    <table>
     <tr><td>No</td><td>Kevin Pakieser</td></tr>
     <tr><td>No</td><td>John Gagnon</td></tr>
    </table>
    """)
    XCTAssertEqual(
      MarkdownConverter.convert(contents),
      "| No | Kevin Pakieser |\n|---|---|\n| No | John Gagnon |"
    )
  }

  func testFallsBackToRTF() {
    let attributedString = NSAttributedString(
      string: "bar",
      attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]
    )
    let rtfData = attributedString.rtf(
      from: NSRange(location: 0, length: attributedString.length),
      documentAttributes: [:]
    )
    let contents = [HistoryItemContent(type: NSPasteboard.PasteboardType.rtf.rawValue, value: rtfData)]
    XCTAssertEqual(MarkdownConverter.convert(contents), "**bar**")
  }

  func testFallsBackToPlainString() {
    let contents = string("foo bar")
    XCTAssertEqual(MarkdownConverter.convert(contents), "foo bar")
  }

  func testReturnsNilWithoutSupportedContent() {
    let contents = [HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue, value: Data())]
    XCTAssertNil(MarkdownConverter.convert(contents))
  }
}
