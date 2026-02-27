import SwiftUI

struct IgnoreSettingsPane: View {
  var body: some View {
    TabView {
      IgnoreApplicationsSettingsView()
        .tabItem {
          Text("ApplicationsTab", tableName: "IgnoreSettings")
        }
      IgnorePasteboardTypesSettingsView()
        .tabItem {
          Text("PasteboardTypesTab", tableName: "IgnoreSettings")
        }
      IgnoreRegexpsSettingsView()
        .tabItem {
          Text("RegexpTab", tableName: "IgnoreSettings")
        }
      IgnoreTextLengthSettingsView()
        .tabItem {
          Text("TextLengthTab", tableName: "IgnoreSettings")
        }
    }
    .frame(minWidth: 560, maxWidth: 700, minHeight: 400)
    .padding()
  }
}

#Preview {
  IgnoreSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
