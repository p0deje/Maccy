import AppKit

/// Abstraction over off-main image decode + downsampling for thumbnails and previews.
///
/// Conformances must be `Sendable` so they can run on a background actor.
protocol ImageProcessing: Sendable {
  /// Builds (or fetches) a thumbnail for `data`, sized so the longest side is ≤ `max`.
  func thumbnail(for data: Data, max: CGSize) async -> NSImage?

  /// Builds a transient preview for `data`, sized so the longest side is ≤ `max`.
  func preview(for data: Data, max: CGSize) async -> NSImage?
}

/// `ImageProcessing` conformance that mirrors the legacy on-main decode path.
///
/// Used by tests and any path that does not need caching. Decodes via
/// `NSImage(data:)` and resizes with `NSImage.resized(to:)`.
struct PassthroughImageProcessor: ImageProcessing {
  func thumbnail(for data: Data, max: CGSize) async -> NSImage? {
    image(for: data, max: max)
  }

  func preview(for data: Data, max: CGSize) async -> NSImage? {
    image(for: data, max: max)
  }

  private func image(for data: Data, max: CGSize) -> NSImage? {
    NSImage(data: data)?.resized(to: NSSize(width: max.width, height: max.height))
  }
}
