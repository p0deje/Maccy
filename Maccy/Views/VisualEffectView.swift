import SwiftUI

struct VisualEffectView: NSViewRepresentable {
  var material: NSVisualEffectView.Material
  var blendingMode: NSVisualEffectView.BlendingMode

  func makeNSView(context: Context) -> NSVisualEffectView {
    context.coordinator.visualEffectView
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    context.coordinator.update(
      material: material,
      blendingMode: blendingMode
    )
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator {
    let visualEffectView = NSVisualEffectView()

    init() {
      visualEffectView.blendingMode = .withinWindow
    }

    func update(
      material: NSVisualEffectView.Material,
      blendingMode: NSVisualEffectView.BlendingMode
    ) {
      visualEffectView.material = material
      visualEffectView.blendingMode = blendingMode
    }
  }
}
#Preview {
  VisualEffectView(
    material: .popover,
    blendingMode: .behindWindow
  )
}
