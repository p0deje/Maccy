import SwiftUI

extension View {
  /// Hides a view visually and from accessibility while preserving its layout space.
  func invisible(_ hidden: Bool) -> some View {
    self
      .opacity(hidden ? 0 : 1)
      .accessibilityHidden(hidden)
  }
}
