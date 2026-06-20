import AppKit
import Foundation

/// Runner-side generator for the performance-test image corpus. Downloads real
/// CC0 photos (synthetic CoreGraphics fallback if offline), then crops/scales
/// them into a target byte-size distribution via a JPEG-quality binary search.
/// Seeded for determinism; cached per run so a shard doesn't regenerate. Nothing
/// binary is committed to git — only this source file.
///
/// `@MainActor` because crop/encode use AppKit (`NSImage.lockFocus`), which is
/// main-thread-affined. Perf tests call it from their `@MainActor` setUp.
@MainActor
enum ImageFixtureGenerator {
  enum Bucket: String, Sendable, CaseIterable {
    case tenMB
    case fiveMB
    case twoMB
    case oneMB
    case halfMB

    var targetBytes: Int {
      switch self {
      case .tenMB: return 10 * 1024 * 1024
      case .fiveMB: return 5 * 1024 * 1024
      case .twoMB: return 2 * 1024 * 1024
      case .oneMB: return 1 * 1024 * 1024
      case .halfMB: return 500 * 1024
      }
    }

    /// Approx pixel long-edge to render before quality-searching, so JPEG
    /// quality stays in a sane range across buckets.
    var canvasLongEdge: Int {
      switch self {
      case .tenMB: return 6000
      case .fiveMB: return 4500
      case .twoMB: return 3000
      case .oneMB: return 2200
      case .halfMB: return 1400
      }
    }
  }

  /// Seedable xorshift64* — `SystemRandomNumberGenerator` cannot be seeded, and
  /// reproducible crop rects require a fixed seed.
  struct SeededRNG: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
      self.state = seed == 0 ? 0xDEADBEEFDEADBEEF : seed
    }

    mutating func next() -> UInt64 {
      state &+= 0x9E3779B97F4A7C15
      var mixed = state
      mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
      mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
      return mixed ^ (mixed >> 31)
    }
  }

  private static var sourceImages: [NSImage] = []
  private static var sourcesLoaded = false

  /// Returns JPEG data ≈ `bucket.targetBytes` for the given variant, cached.
  static func jpeg(bucket: Bucket, variant: Int, cacheDir: URL) throws -> Data {
    let cacheURL = cacheDir.appending(path: "\(bucket.rawValue)_v\(variant).jpg")
    if let cached = try? Data(contentsOf: cacheURL) {
      return cached
    }
    if !sourcesLoaded {
      sourcesLoaded = true
      let downloaded = downloadSources()
      sourceImages = downloaded.isEmpty ? [synthesizeSource()] : downloaded
    }
    guard !sourceImages.isEmpty else { return Data() }
    let source = sourceImages[variant % sourceImages.count]
    let rendered = renderCropped(source, bucket: bucket, variant: variant)
    let data = encodeJPEG(targeting: bucket.targetBytes, image: rendered)
    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    try? data.write(to: cacheURL)
    return data
  }

  /// Stable CC0 photo URLs. Any failure (network/parsing) → that URL skipped.
  private static func downloadSources() -> [NSImage] {
    let urls = [
      "https://picsum.photos/seed/maccy-perf-a/3000/2000",
      "https://picsum.photos/seed/maccy-perf-b/2500/2500",
      "https://picsum.photos/seed/maccy-perf-c/4000/1500"
    ]
    return urls.compactMap { urlString -> NSImage? in
      guard let url = URL(string: urlString),
            let data = try? Data(contentsOf: url),
            let image = NSImage(data: data) else { return nil }
      return image
    }
  }

  /// High-frequency-ish synthetic content so JPEG doesn't collapse to a few KB
  /// (a flat image would not stress the decode path the way a real photo does).
  private static func synthesizeSource() -> NSImage {
    let size = NSSize(width: 3000, height: 2000)
    let image = NSImage(size: size)
    image.lockFocus()
    for yPos in stride(from: 0, to: Int(size.height), by: 40) {
      for xPos in stride(from: 0, to: Int(size.width), by: 40) {
        let hue = CGFloat((xPos + yPos) % 360) / 360.0
        NSColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1.0).setFill()
        NSRect(x: CGFloat(xPos), y: CGFloat(yPos), width: 40, height: 40).fill()
      }
    }
    image.unlockFocus()
    return image
  }

  /// Deterministic crop + scale of `source` to the bucket's canvas long edge.
  private static func renderCropped(_ source: NSImage, bucket: Bucket, variant: Int) -> NSImage {
    var rng = SeededRNG(seed: UInt64(variant) &* 2_000_003 &+ 1)
    let srcWidth = source.size.width
    let srcHeight = source.size.height
    let cropFractionWidth = Double(rng.random(in: 0.5...0.95))
    let cropFractionHeight = Double(rng.random(in: 0.5...0.95))
    let cropWidth = srcWidth * cropFractionWidth
    let cropHeight = srcHeight * cropFractionHeight
    let originX = srcWidth * Double(rng.random(in: 0..<max(0.001, 1 - cropFractionWidth)))
    let originY = srcHeight * Double(rng.random(in: 0..<max(0.001, 1 - cropFractionHeight)))
    let cropRect = NSRect(x: originX, y: originY, width: cropWidth, height: cropHeight)

    let longEdge = CGFloat(bucket.canvasLongEdge)
    let scale = longEdge / max(cropWidth, cropHeight)
    let destSize = NSSize(width: cropWidth * scale, height: cropHeight * scale)
    let composite = NSImage(size: destSize)
    composite.lockFocus()
    source.draw(
      in: NSRect(origin: .zero, size: destSize),
      from: cropRect,
      operation: .copy,
      fraction: 1.0
    )
    composite.unlockFocus()
    return composite
  }

  /// Binary-search JPEG quality so the encoded bytes hit `targetBytes` ±5%.
  private static func encodeJPEG(targeting targetBytes: Int, image: NSImage) -> Data {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
      return Data()
    }
    var low = 0.05
    var high = 0.95
    var best = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) ?? Data()
    for _ in 0..<20 {
      let mid = (low + high) / 2
      guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: mid]) else { break }
      best = data
      if abs(Double(data.count) - Double(targetBytes)) < Double(targetBytes) * 0.05 { break }
      if data.count < targetBytes {
        low = mid
      } else {
        high = mid
      }
    }
    return best
  }
}
