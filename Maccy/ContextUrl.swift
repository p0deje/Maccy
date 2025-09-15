import Foundation

struct ContextUrlSniffer {
  private static let safariIdentifier = "com.apple.Safari"
  private static let firefoxIdentifier = "org.mozilla.firefox"
  private static let chromeIdentifier = "com.google.Chrome"
  private static let webkitCustomPasteboardDataType =
    "com.apple.WebKit.custom-pasteboard-data"
  private static let chromiumSourceDataType = "org.chromium.source-url"

  private func dataToUrlString(_ data: Data) -> String? {
    if let htmlData = "http".data(using: .utf8),
      let range = data.range(of: htmlData)
    {
      var utf8Decoder = UTF8()
      let subrange = data.suffix(from: range.lowerBound)
      var iterator = subrange.makeIterator()
      var decodedString = ""

      Decode: while true {
        switch utf8Decoder.decode(&iterator) {
        case .scalarValue(let scalar):
          if !CharacterSet.urlQueryAllowed.contains(scalar) {
            break Decode
          }
          decodedString.append(Character(scalar))
        case .emptyInput:
          break Decode
        case .error:
          break Decode
        }
      }

      return decodedString
    }
    return nil
  }

  private func extractWebkitUrl(from historyItem: HistoryItem) -> URL? {
    if let data = historyItem.contents.first(where: {
      $0.type == Self.webkitCustomPasteboardDataType
    })?.value {
      if let originUrlString = dataToUrlString(data),
        let url = URL(string: originUrlString)
      {
        return url
      }
    }
    return nil
  }

  func extractChromiumUrl(from historyItem: HistoryItem) -> URL? {
    if let data = historyItem.contents.first(where: {
      $0.type == Self.chromiumSourceDataType
    })?.value {
      if let originUrlString = String(data: data, encoding: .utf8),
        let url = URL(string: originUrlString)
      {
        return url
      }
    }
    return nil
  }

  func sniffContextUrl(item: HistoryItem) -> URL? {
    switch item.application {
    case Self.safariIdentifier:
      return extractWebkitUrl(from: item)
    case Self.chromeIdentifier:
      return extractChromiumUrl(from: item)
    default:
      return nil
    }
  }

}
