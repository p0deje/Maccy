import Foundation
import Testing

struct LocalizationTests {
  @Test(arguments: ["eo", "id"], [
    "AdvancedSettings", "AppearanceSettings", "GeneralSettings", "IgnoreSettings",
    "Localizable", "PinsSettings", "PreviewItemView", "StorageSettings"
  ])
  func bundlesStringTable(locale: String, table: String) throws {
    let resources = try #require(Bundle.main.resourceURL)
    let path = resources.appendingPathComponent("\(locale).lproj").appendingPathComponent("\(table).strings").path
    #expect(FileManager.default.fileExists(atPath: path))
  }
}
