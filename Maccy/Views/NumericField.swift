import SwiftUI

// A numeric text field that commits its value when editing ends — both on
// Return and on focus loss (blur). `TextField(value:formatter:)` only wrote
// the value back on Return, so clicking or tabbing away silently reverted the
// input to its previous value. See https://github.com/p0deje/Maccy/issues/1516.
struct NumericField: View {
  @Binding var value: Int
  let range: ClosedRange<Int>

  @State private var text: String = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    TextField("", text: $text)
      .focused($isFocused)
      .onAppear { text = String(value) }
      .onChange(of: value) { _, newValue in
        // Keep in sync with external changes (e.g. the paired Stepper) while
        // the user isn't mid-edit.
        if !isFocused {
          text = String(newValue)
        }
      }
      .onChange(of: isFocused) { _, focused in
        if !focused {
          commit()
        }
      }
      .onSubmit {
        commit()
      }
  }

  private func commit() {
    value = Self.committedValue(text: text, current: value, range: range)
    // Reflect the committed value, reverting invalid or out-of-range input.
    text = String(value)
  }

  static func committedValue(text: String, current: Int, range: ClosedRange<Int>) -> Int {
    guard let entered = Int(text), range.contains(entered) else {
      return current
    }
    return entered
  }
}
