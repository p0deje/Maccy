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
/// Items are inserted via `History.shared.add` (the in-process path that creates
/// decorators, so thumbnails/previews render — the same path `PerfHistoryFactory`
/// uses for the A tests, which render fine). `#if DEBUG` + only wired under
/// `MaccyPerfRecord`, so no ship impact. Image bytes are generated via
/// CoreGraphics (no binaries committed, no images in logs — only `PERF|` text).
@MainActor
enum PerfFixtures {
  /// Populates `History.shared` with `count` items of `category`
  /// ("image" / "text" / "mixed"), clearing first. Each item has a distinct
  /// value (seed-dependent) so dedup keeps them all.
  static func populate(count: Int, category: String) {
    let history = History.shared
    history.clearAll()
    history.searchQuery = ""

    switch category {
    case "text":
      for index in 0..<count {
        addText(index: index)
      }
    case "mixed":
      for index in 0..<count {
        if index % 2 == 0 {
          addImage(seed: index)
        } else {
          addText(index: index)
        }
      }
    default: // "image"
      for index in 0..<count {
        addImage(seed: index)
      }
    }
  }

  // MARK: - Private

  private static func addImage(seed: Int) {
    let item = HistoryItem(contents: [
      HistoryItemContent(type: "public.png", value: makeImageJPEG(seed: seed))
    ])
    item.firstCopiedAt = Date(timeIntervalSince1970: Double(seed))
    item.lastCopiedAt = item.firstCopiedAt
    item.title = ""
    History.shared.add(item)
  }

  private static func addText(index: Int) {
    let paragraph = "The quick brown fox jumps over the lazy dog. " +
      "Maccy is a lightweight clipboard manager for macOS. "
    let value = Data(String(repeating: paragraph, count: 40).utf8) + Data("\n#\(index)\n".utf8)
    let item = HistoryItem(contents: [
      HistoryItemContent(type: "public.utf8-plain-text", value: value)
    ])
    item.firstCopiedAt = Date(timeIntervalSince1970: Double(index))
    item.lastCopiedAt = item.firstCopiedAt
    item.title = "text #\(index)"
    History.shared.add(item)
  }

  /// A seed-dependent photo-like JPEG (base fill + varied rects) with
  /// high-frequency detail so it isn't trivially compressible — stresses the
  /// ImageIO decode path. Distinct per seed (distinct fingerprint → no dedup).
  private static func makeImageJPEG(seed: Int) -> Data {
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
