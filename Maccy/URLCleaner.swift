import Foundation

struct URLCleaner {
  static let trackingParameters: Set<String> = {
    guard let url = Bundle.main.url(forResource: "TrackingParameters", withExtension: "plist"),
          let data = try? Data(contentsOf: url),
          let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String]
    else { return [] }
    return Set(list.map { $0.lowercased() })
  }()

  static func clean(_ urlString: String) -> String {
    guard var components = URLComponents(string: urlString),
          let queryItems = components.queryItems,
          !queryItems.isEmpty else {
      return urlString
    }
    let cleaned = queryItems.filter { !trackingParameters.contains($0.name.lowercased()) }
    components.queryItems = cleaned.isEmpty ? nil : cleaned
    return components.string ?? urlString
  }

  static func isURL(_ string: String) -> Bool {
    guard let url = URL(string: string) else { return false }
    return url.scheme == "http" || url.scheme == "https"
  }
}
