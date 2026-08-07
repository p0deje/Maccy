import SwiftUI
import Defaults

struct IgnoreTextLengthSettingsView: View {
  @Default(.maxTextLengthToRemember) private var maxTextLengthToRemember

  @State private var enabled = false
  @State private var maxTextLength = 10_000

  private let maxTextLengthFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 1_000_000
    return formatter
  }()

  var body: some View {
    VStack(alignment: .leading) {
      Toggle(isOn: $enabled) {
        Text("IgnoreByTextLengthEnabled", tableName: "IgnoreSettings")
      }
      .onChange(of: enabled) { _, isEnabled in
        if isEnabled {
          let value = max(maxTextLengthToRemember ?? maxTextLength, 1)
          maxTextLength = value
          maxTextLengthToRemember = value
        } else {
          maxTextLengthToRemember = nil
        }
      }

      HStack {
        Text("IgnoreByTextLengthLimitLabel", tableName: "IgnoreSettings")

        TextField("", value: $maxTextLength, formatter: maxTextLengthFormatter)
          .frame(width: 120)

        Stepper("", value: $maxTextLength, in: 1...1_000_000)
          .labelsHidden()
      }
      .disabled(!enabled)
      .onChange(of: maxTextLength) { _, value in
        guard enabled else {
          return
        }

        let correctedValue = max(value, 1)
        if value != correctedValue {
          maxTextLength = correctedValue
        }
        maxTextLengthToRemember = correctedValue
      }

      Text("IgnoreByTextLengthDescription", tableName: "IgnoreSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
    }
    .onAppear {
      if let limit = maxTextLengthToRemember, limit > 0 {
        enabled = true
        maxTextLength = limit
      } else {
        enabled = false
      }
    }
    .padding()
  }
}

#Preview {
  IgnoreTextLengthSettingsView()
    .environment(\.locale, .init(identifier: "en"))
}
