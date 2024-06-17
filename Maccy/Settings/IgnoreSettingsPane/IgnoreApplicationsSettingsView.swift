import SwiftUI
import Defaults

struct IgnoreApplicationsSettingsView: View {
  @Default(.ignoredApps) private var ignoredApps

  @State private var isAdding = false
  @State private var selection = ""

  var body: some View {
    VStack(alignment: .leading) {
      List(selection: $selection) {
        ForEach($ignoredApps) { $app in
          if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
            Label(
              title: {
                Text(NSWorkspace.shared.applicationName(url: url))
                  .padding(.horizontal, 5)
              },
              icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
              }
            ).frame(height: 32).padding(.horizontal, 5)
          } else {
            Label(
              title: { Text(app).padding(.horizontal, 5) },
              icon: { Image(systemName: "questionmark.circle").imageScale(.large) }
            ).frame(height: 32).padding(.horizontal, 5)
          }
        }
      }.onDeleteCommand {
        remove(selection)
      }

      HStack {
        ControlGroup {
          Button("", systemImage: "plus") {
            isAdding = true
          }

          Button("", systemImage: "minus") {
            remove(selection)
          }
        }
        .frame(width: 50)
        .fileDialogDefaultDirectory(URL(string: "/Applications"))
        .fileImporter(
          isPresented: $isAdding,
          allowedContentTypes: [.application]
        ) { result in
          switch result {
          case .success(let appUrl):
            if let bundle = Bundle(path: appUrl.path),
               let bundleIdentifier = bundle.bundleIdentifier,
               !ignoredApps.contains(bundleIdentifier) {
              ignoredApps.append(bundleIdentifier)
            }
          case .failure(let error):
            print("Failed to select application: \(error)")
          }
        }

        Defaults.Toggle(key: .ignoreAllAppsExceptListed) {
          Text("IgnoredAllAppsExceptListed", tableName: "IgnoreSettings")
        }
      }

      Text("IgnoredAppsDescription", tableName: "IgnoreSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
    }.padding()
  }

  private func remove(_ app: String?) {
    guard let app else { return }

    ignoredApps.removeAll(where: { $0 == app })
  }
}

#Preview {
  IgnoreApplicationsSettingsView()
    .environment(\.locale, .init(identifier: "en"))
}
