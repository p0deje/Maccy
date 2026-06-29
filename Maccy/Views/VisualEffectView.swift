import SwiftUI

/// SwiftUI bridge to an AppKit `NSVisualEffectView` for a vibrancy material.
struct VisualEffectView: NSViewRepresentable {
  var material: NSVisualEffectView.Material = .popover
  var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

  func makeNSView(context: Context) -> NSVisualEffectView {
    return NSVisualEffectView()
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    view.material = material
    view.blendingMode = blendingMode
  }
}

/// SwiftUI bridge to an AppKit `NSGlassEffectView` (macOS 26+).
@available(macOS 26.0, *)
struct GlassEffectView: NSViewRepresentable {
  var style: NSGlassEffectView.Style = .regular

  func makeNSView(context: Context) -> NSGlassEffectView {
    return NSGlassEffectView()
  }

  func updateNSView(_ view: NSGlassEffectView, context: Context) {
    view.style = style
  }
}

#Preview {
  VisualEffectView(
    material: .popover,
    blendingMode: .behindWindow
  )
}
