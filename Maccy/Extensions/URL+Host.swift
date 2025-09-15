import Foundation

extension URL {

  var plainHost: String? {
    guard let host = host else { return nil }
    if host.hasPrefix("www.") {
      return String(host.dropFirst(4))
    }
    return host
  }
}
