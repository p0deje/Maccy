import AppKit

protocol ImageProcessing: Sendable {
  func thumbnail(for data: Data, max: CGSize) async -> NSImage?
  func preview(for data: Data, max: CGSize) async -> NSImage?
}

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
