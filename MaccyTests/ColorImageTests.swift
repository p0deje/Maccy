import Testing
@testable import Maccy

@MainActor
struct ColorImageTests {
  @Test("Color image from hex", arguments: ["fff", "#ff8942"])
  func colorImageFromHex(hex: String) {
    #expect(ColorImage.from(hex) != nil)
  }

  @Test("Color image from non-hex string")
  func colorImageFromNonHexString() {
    #expect(ColorImage.from("foo") == nil)
  }
}
