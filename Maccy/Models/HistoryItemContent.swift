import Foundation
import SwiftData

@Model
class HistoryItemContent {
  var type: String = ""
  var value: Data?

  @Relationship
  var item: HistoryItem?

  init(type: String, value: Data? = nil) {
    self.type = type
    self.value = value
  }
}
