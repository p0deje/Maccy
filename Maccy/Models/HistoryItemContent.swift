import Foundation
import Defaults
import SwiftData

@Model
class HistoryItemContent {
  static var maxValueSize: Int {
    max(1, Defaults[.maxClipboardContentSize]) * 1_024 * 1_024
  }

  var type: String = ""
  var value: Data?

  @Relationship
  var item: HistoryItem?

  init(type: String, value: Data? = nil) {
    self.type = type
    self.value = value
  }
}
