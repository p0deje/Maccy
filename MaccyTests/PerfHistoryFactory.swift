import Foundation
@testable import Maccy

/// Composes the six benchmark scenario histories into the shared in-memory
/// `History` (enable-testing forces an in-memory SwiftData store). Each method
/// clears the store first, populates it, and returns the populated `History`.
///
/// `HistoryBuilder`, `FixtureLoader`, and `ImageFixtureGenerator` are all in the
/// MaccyTests target; only `History` requires `@testable import Maccy`.
@MainActor
enum PerfHistoryFactory {
  /// `count` image items, each a JPEG of `bucket` bytes.
  static func makeImages(count: Int, bucket: ImageFixtureGenerator.Bucket,
                         cacheDir: URL) throws -> History {
    let history = History.shared
    history.clearAll()
    for variant in 0..<count {
      let data = try ImageFixtureGenerator.jpeg(bucket: bucket, variant: variant, cacheDir: cacheDir)
      history.add(
        HistoryBuilder()
          .withContent(type: "public.png", value: data)
          .withCopiedAt(Date(timeIntervalSince1970: Double(variant)))
          .build()
      )
    }
    return history
  }

  /// `count` text items. `long` uses `heavy_text.txt`; otherwise a short string.
  static func makeTexts(count: Int, long: Bool) throws -> History {
    let history = History.shared
    history.clearAll()
    let heavy = try Data(contentsOf: FixtureLoader.heavyTextURL)
    let value: Data? = long ? heavy : Data("short".utf8)
    for index in 0..<count {
      history.add(
        HistoryBuilder()
          .withContent(type: "public.utf8-plain-text", value: value)
          .withCopiedAt(Date(timeIntervalSince1970: Double(index)))
          .build()
      )
    }
    return history
  }

  /// `images` image items + `texts` long-text items (scenario 5/6).
  static func makeMixed(images: Int, texts: Int,
                        bucket: ImageFixtureGenerator.Bucket,
                        cacheDir: URL) throws -> History {
    let history = History.shared
    history.clearAll()
    let heavy = try Data(contentsOf: FixtureLoader.heavyTextURL)
    for variant in 0..<images {
      let data = try ImageFixtureGenerator.jpeg(bucket: bucket, variant: variant, cacheDir: cacheDir)
      history.add(
        HistoryBuilder()
          .withContent(type: "public.png", value: data)
          .withCopiedAt(Date(timeIntervalSince1970: Double(variant)))
          .build()
      )
    }
    for index in 0..<texts {
      history.add(
        HistoryBuilder()
          .withContent(type: "public.utf8-plain-text", value: heavy)
          .withCopiedAt(Date(timeIntervalSince1970: Double(images + index)))
          .build()
      )
    }
    return history
  }
}
