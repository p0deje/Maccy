import SwiftUI

extension View {
  /// Hides this view both visually (opacity, so it keeps its layout space) and from
  /// accessibility - without the latter, VoiceOver still finds an invisible element,
  /// which for overlapping controls (see FooterView) risks activating the wrong one.
  func invisible(_ hidden: Bool) -> some View {
    self
      .opacity(hidden ? 0 : 1)
      .accessibilityHidden(hidden)
  }
}
