#if DEBUG
import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// In-process fixture population for the `method=B` UI benchmarks, invoked via
/// the `MaccyPerfBulkLoad` distributed notification. Generating items in-process
/// (instead of via the 1.5s-per-copy pasteboard poll) makes B's populate phase
/// instant and reliable — the pasteboard path was both slow (~45s for 30 copies)
/// and didn't reliably produce renderable image items on the headless runner.
///
/// Items are batch-inserted into the context + saved once, then a single
/// `History.load()` materializes decorators (the popup-open path). This is NOT
/// `History.add` per item — that legacy path is O(n²) on main (full sort +
/// decorate + findSimilarItem + invalidation PER add) and froze the app ~115s
/// for 30 mixed items. `#if DEBUG` + only wired under `MaccyPerfRecord`, so no
/// ship impact. Image bytes are generated via CoreGraphics (no binaries
/// committed, no images in logs — only `PERF|` text).
@MainActor
enum PerfFixtures {
  /// Populates `History.shared` with `count` items of `category`
  /// ("image" / "text" / "mixed"), clearing first. Each item has a distinct
  /// value (seed-dependent) so dedup keeps them all.
  ///
  /// IMPORTANT: inserts ALL items into the context in one batch + a single save,
  /// then ONE `History.load()` — NOT `History.add` per item. The per-item
  /// `History.add` path is the legacy O(n²) main-thread path (full-table sort +
  /// decorate + findSimilarItem + `@Observable` invalidation PER add); for 30
  /// mixed items that froze main ~115s (measured). Batch-insert + single load
  /// is one fetch+sort+decorate, fast — and matches how the popup actually
  /// populates on open.
  static func populate(count: Int, category: String) {
    let history = History.shared
    history.clearAll()
    history.searchQuery = ""

    let context = Storage.shared.context
    for index in 0..<count {
      let item: HistoryItem
      switch category {
      case "text":
        item = makeTextItem(index: index)
      case "mixed":
        item = (index % 2 == 0) ? makeImageItem(seed: index) : makeTextItem(index: index)
      default:
        item = makeImageItem(seed: index)
      }
      context.insert(item)
    }
    try? context.save()

    // One load to materialize decorators (the popup-open path).
    Task { @MainActor in
      _ = try? await history.load()
    }
  }

  // MARK: - Private

  private static func makeImageItem(seed: Int) -> HistoryItem {
    let item = HistoryItem(contents: [
      HistoryItemContent(type: "public.png", value: makeImageJPEG(seed: seed))
    ])
    item.firstCopiedAt = Date(timeIntervalSince1970: Double(seed))
    item.lastCopiedAt = item.firstCopiedAt
    item.title = ""
    return item
  }

  /// The corpus dir (shared Release asset when `MACCY_PERF_FIXTURES` is set).
  private static var corpusDir: URL? {
    ProcessInfo.processInfo.environment["MACCY_PERF_FIXTURES"]
      .map { URL(fileURLWithPath: $0) }
  }

  private static func makeTextItem(index: Int) -> HistoryItem {
    let paragraph = "The quick brown fox jumps over the lazy dog. " +
      "Maccy is a lightweight clipboard manager for macOS. "
    let value = Data(String(repeating: paragraph, count: 40).utf8) + Data("\n#\(index)\n".utf8)
    let item = HistoryItem(contents: [
      HistoryItemContent(type: "public.utf8-plain-text", value: value)
    ])
    item.firstCopiedAt = Date(timeIntervalSince1970: Double(index))
    item.lastCopiedAt = item.firstCopiedAt
    item.title = "text #\(index)"
    return item
  }

  /// Returns real-photo JPEG bytes from the shared corpus (`MACCY_PERF_FIXTURES`)
  /// if available — the same 1–10MB high-detail photos the A tests use, so B's
  /// decode cost reflects real photos (not trivial CG images that decode in
  /// microseconds). Falls back to the in-process CG generator when no corpus is
  /// present (local runs). The corpus files are named `<bucket>_v<variant>.jpg`
  /// (see `ImageFixtureGenerator.jpeg`); we cycle buckets across seeds for a
  /// size mix.
  private static func makeImageJPEG(seed: Int) -> Data {
    if let dir = corpusDir {
      // Use `.oneMB` (200 real-photo variants in the corpus) so B's 30-item
      // traversal all hits cached real photos — no per-run generation when the
      // corpus is present. 1MB images still exercise the ImageIO decode path.
      let variant = seed % 200
      let fileURL = dir.appendingPathComponent("oneMB_v\(variant).jpg")
      if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
        return data
      }
    }
    return generateCGImageJPEG(seed: seed)
  }

  /// A seed-dependent photo-like JPEG (base fill + varied rects) with
  /// high-frequency detail so it isn't trivially compressible — stresses the
  /// ImageIO decode path. Distinct per seed (distinct fingerprint → no dedup).
  /// Used only when no shared corpus is present.
  private static func generateCGImageJPEG(seed: Int) -> Data {
    let width = 1000
    let height = 750
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
      let cgImage = context.makeImageAfterDrawing(seed: seed, width: width, height: height)
    else {
      return Data()
    }
    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      mutableData, "public.jpeg" as CFString, 1, nil
    ) else {
      return Data()
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      return Data()
    }
    return mutableData as Data
  }
}

private extension CGContext {
  /// Draws the seed-dependent content into this context and returns the image.
  func makeImageAfterDrawing(seed: Int, width: Int, height: Int) -> CGImage? {
    let red = CGFloat((seed &* 37) % 256) / 255
    let green = CGFloat((seed &* 53) % 256) / 255
    let blue = CGFloat((seed &* 71) % 256) / 255
    setFillColor(red: red, green: green, blue: blue, alpha: 1)
    fill(CGRect(x: 0, y: 0, width: width, height: height))
    var state = UInt64(seed * seed + 7)
    for _ in 0..<500 {
      state = state &* 6364136223846793005 &+ 1442695040888963407
      let xPos = CGFloat((state >> 33) % UInt64(width))
      let yPos = CGFloat((state >> 11) % UInt64(height))
      let dimension = CGFloat((state >> 50) % 80) + 5
      let channel = CGFloat((state >> 20) % 256) / 255
      setFillColor(red: channel, green: 1 - channel, blue: 0.5, alpha: 0.6)
      fill(CGRect(x: xPos, y: yPos, width: dimension, height: dimension))
    }
    return makeImage()
  }
}
#endif
