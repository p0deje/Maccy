import Foundation

protocol ClipboardIngestor: Sendable {
  func ingest(_ request: IngestRequest) async -> IngestResult
}

final class MainActorIngestorAdapter: ClipboardIngestor {
  func ingest(_ request: IngestRequest) async -> IngestResult {
    await MainActor.run {
      let item = Self.historyItem(from: request)
      History.shared.add(item)
      return IngestResult(event: nil, metrics: .zero)
    }
  }

  @MainActor
  static func historyItem(from request: IngestRequest) -> HistoryItem {
    let item = HistoryItem(
      contents: request.contents.map {
        HistoryItemContent(type: $0.type, value: $0.value)
      }
    )
    item.application = request.application
    item.firstCopiedAt = request.now
    item.lastCopiedAt = request.now
    item.title = item.generateTitle()
    return item
  }
}
