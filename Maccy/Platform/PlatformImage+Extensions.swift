import SwiftUI

#if os(macOS)
import AppKit

extension NSImage {
  var cgImageForProcessing: CGImage? {
    cgImage(forProposedRect: nil, context: nil, hints: nil)
  }
}
#else
import UIKit

extension UIImage {
  var cgImageForProcessing: CGImage? { cgImage }

  func resized(to targetSize: CGSize) -> UIImage {
    let widthRatio = targetSize.width / size.width
    let heightRatio = targetSize.height / size.height
    let ratio = min(widthRatio, heightRatio)

    let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

    let renderer = UIGraphicsImageRenderer(size: newSize)
    return renderer.image { _ in
      draw(in: CGRect(origin: .zero, size: newSize))
    }
  }

  func recache() {
    // No-op on iOS - NSImage has recache, UIImage doesn't need it
  }
}
#endif
