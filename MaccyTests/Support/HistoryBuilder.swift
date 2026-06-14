import Foundation
@testable import Maccy

@MainActor
struct HistoryBuilder {
  private var contents: [HistoryItemContent] = []
  private var application: String?
  private var firstCopiedAt = Date(timeIntervalSince1970: 1_717_171_717)
  private var lastCopiedAt = Date(timeIntervalSince1970: 1_717_171_717)
  private var numberOfCopies = 1
  private var pin: String?
  private var title: String?

  func withContent(type: String, value: Data?) -> Self {
    var builder = self
    builder.contents.append(HistoryItemContent(type: type, value: value))
    return builder
  }

  func withApplication(_ application: String?) -> Self {
    var builder = self
    builder.application = application
    return builder
  }

  func withCopiedAt(_ date: Date) -> Self {
    var builder = self
    builder.firstCopiedAt = date
    builder.lastCopiedAt = date
    return builder
  }

  func withNumberOfCopies(_ count: Int) -> Self {
    var builder = self
    builder.numberOfCopies = count
    return builder
  }

  func withPin(_ pin: String?) -> Self {
    var builder = self
    builder.pin = pin
    return builder
  }

  func withTitle(_ title: String?) -> Self {
    var builder = self
    builder.title = title
    return builder
  }

  func build() -> HistoryItem {
    let item = HistoryItem(contents: contents)
    item.application = application
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = numberOfCopies
    item.pin = pin
    item.title = title ?? item.generateTitle()
    return item
  }
}
