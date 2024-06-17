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
    }
    .frame(maxWidth: 500, minHeight: 400)
    .padding()
  }
}

#Preview {
  IgnoreSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
