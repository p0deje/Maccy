import AppKit.NSImage
import SwiftUI

extension Image {
  static func thumbnailImage(_ image: NSImage, maxHeight: Int, maxWidth: Int = 340) -> Image {
    let imageMaxWidth = CGFloat(maxWidth)
    if image.size.width > imageMaxWidth {
      image.size.height /= image.size.width / imageMaxWidth
      image.size.width = imageMaxWidth
    }

    let imageMaxHeight = CGFloat(maxHeight)
    if image.size.height > imageMaxHeight {
      image.size.width /= image.size.height / imageMaxHeight
      image.size.height = imageMaxHeight
    }
    return Image(nsImage: image)
  }
}
