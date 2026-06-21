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
  /// Number of distinct images pre-generated for the main `.oneMB` bucket in
  /// the shared corpus (see `CorpusGeneratorTests`). Tests request
  /// `variant % corpusVariantCount` so every request hits a cached corpus file
  /// when `MACCY_PERF_FIXTURES` is populated — no per-run image generation.
  /// (Other buckets have fewer variants; the N=200 scenarios only use `.oneMB`.)
  static let corpusVariantCount = 200

  /// `count` image items, each a JPEG of `bucket` bytes. Cycles the corpus
  /// variants so a populated corpus serves every request from cache.
  static func makeImages(count: Int, bucket: ImageFixtureGenerator.Bucket,
                         cacheDir: URL) throws -> History {
    let history = History.shared
    history.clearAll()
    for variant in 0..<count {
      let corpusVariant = variant % corpusVariantCount
      let data = try ImageFixtureGenerator.jpeg(bucket: bucket, variant: corpusVariant, cacheDir: cacheDir)
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
  /// Each item's value is suffixed with its index so the dedup signature differs
  /// — otherwise identical copies collapse to one via `findSimilarItem` (and a
  /// real history holds distinct items anyway).
  static func makeTexts(count: Int, long: Bool) throws -> History {
    let history = History.shared
    history.clearAll()
    let heavy = try Data(contentsOf: FixtureLoader.heavyTextURL)
    for index in 0..<count {
      let value: Data
      if long {
        value = heavy + Data("\n#\(index)\n".utf8)
      } else {
        value = Data("short #\(index)".utf8)
      }
      history.add(
        HistoryBuilder()
          .withContent(type: "public.utf8-plain-text", value: value)
          .withCopiedAt(Date(timeIntervalSince1970: Double(index)))
          .build()
      )
    }
    return history
  }

  /// `images` image items + `texts` long-text items (scenario 5/6), added
  /// interleaved (image, text, image, text, …) with sequential `copiedAt` so
  /// that — sorted most-recent-first — the first N visible items contain BOTH
  /// types (a true mix), not all-one-type.
  static func makeMixed(images: Int, texts: Int,
                        bucket: ImageFixtureGenerator.Bucket,
                        cacheDir: URL) throws -> History {
    let history = History.shared
    history.clearAll()
    let heavy = try Data(contentsOf: FixtureLoader.heavyTextURL)
    let pairCount = min(images, texts)
    var timestamp = 0.0
    for index in 0..<pairCount {
      let imageData = try ImageFixtureGenerator.jpeg(bucket: bucket, variant: index % corpusVariantCount, cacheDir: cacheDir)
      history.add(
        HistoryBuilder()
          .withContent(type: "public.png", value: imageData)
          .withCopiedAt(Date(timeIntervalSince1970: timestamp))
          .build()
      )
      timestamp += 1
      let textValue = heavy + Data("\n#mix-\(index)\n".utf8)
      history.add(
        HistoryBuilder()
          .withContent(type: "public.utf8-plain-text", value: textValue)
          .withCopiedAt(Date(timeIntervalSince1970: timestamp))
          .build()
      )
      timestamp += 1
    }
    for index in pairCount..<images {
      let imageData = try ImageFixtureGenerator.jpeg(bucket: bucket, variant: index % corpusVariantCount, cacheDir: cacheDir)
      history.add(
        HistoryBuilder()
          .withContent(type: "public.png", value: imageData)
          .withCopiedAt(Date(timeIntervalSince1970: timestamp))
          .build()
      )
      timestamp += 1
    }
    for index in pairCount..<texts {
      let textValue = heavy + Data("\n#mix-\(index)\n".utf8)
      history.add(
        HistoryBuilder()
          .withContent(type: "public.utf8-plain-text", value: textValue)
          .withCopiedAt(Date(timeIntervalSince1970: timestamp))
          .build()
      )
      timestamp += 1
    }
    return history
  }
}
