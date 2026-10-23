import SwiftUI

struct IgnoreSettingsPane: View {
  @State private var selection = 0

  var body: some View {
    GeometryReader { geometry in
      content
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }

  private var content: some View {
    VStack(spacing: 16) {
      Picker("", selection: $selection) {
        Text("ApplicationsTab", tableName: "IgnoreSettings").tag(0)
        Text("PasteboardTypesTab", tableName: "IgnoreSettings").tag(1)
        Text("RegexpTab", tableName: "IgnoreSettings").tag(2)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityLabel(Text("Title", tableName: "IgnoreSettings"))

      Group {
        switch selection {
        case 1: IgnorePasteboardTypesSettingsView()
        case 2: IgnoreRegexpsSettingsView()
        default: IgnoreApplicationsSettingsView()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
    .toggleStyle(.switch)
    .padding(24)
  }
}

#Preview {
  IgnoreSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
