import SwiftUI

extension View {
  /// Marks this view as a button that responds to both a mouse tap and VoiceOver activation
  /// (VO-Space) with the same action, so the two input methods never diverge from each other.
  func buttonAction(_ action: @escaping () -> Void) -> some View {
    self
      .accessibilityAddTraits(.isButton)
      .accessibilityAction(.default, action)
      .onTapGesture(perform: action)
  }
}
