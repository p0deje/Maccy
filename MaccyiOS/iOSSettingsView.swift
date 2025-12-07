import SwiftUI
import Defaults

struct iOSSettingsView: View {
  @Environment(\.dismiss) private var dismiss

  @Default(.searchMode) private var searchMode
  @Default(.sortBy) private var sortBy
  @Default(.imageMaxHeight) private var imageMaxHeight
  @Default(.pinTo) private var pinTo
  @Default(.showSearch) private var showSearch
  @Default(.iCloudSync) private var iCloudSync

  @State private var showingClearConfirmation = false
  @State private var showingClearAllConfirmation = false

  var body: some View {
    Form {
      Section("iCloud") {
        Toggle("Sync with iCloud", isOn: $iCloudSync)
        Text("Sync clipboard history between your Mac and iOS devices")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Search") {
        Picker("Search Mode", selection: $searchMode) {
          ForEach(Search.Mode.allCases) { mode in
            Text(mode.description).tag(mode)
          }
        }

        Toggle("Show Search Bar", isOn: $showSearch)
      }

      Section("Display") {
        Picker("Sort By", selection: $sortBy) {
          ForEach(Sorter.By.allCases) { sort in
            Text(sort.description).tag(sort)
          }
        }

        Picker("Pin Position", selection: $pinTo) {
          Text("Top").tag(PinsPosition.top)
          Text("Bottom").tag(PinsPosition.bottom)
        }

        Stepper("Max Image Height: \(imageMaxHeight)", value: $imageMaxHeight, in: 20...200, step: 10)
      }

      Section("Storage") {
        HStack {
          Text("Database Size")
          Spacer()
          Text(Storage.shared.size)
            .foregroundStyle(.secondary)
        }

        Button("Clear History (Keep Pins)") {
          showingClearConfirmation = true
        }
        .foregroundStyle(.red)

        Button("Clear All History") {
          showingClearAllConfirmation = true
        }
        .foregroundStyle(.red)
      }

      Section("About") {
        Link("GitHub Repository", destination: URL(string: "https://github.com/p0deje/Maccy")!)

        HStack {
          Text("Version")
          Spacer()
          Text(Bundle.main.appVersion)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Done") {
          dismiss()
        }
      }
    }
    .confirmationDialog(
      "Clear History",
      isPresented: $showingClearConfirmation,
      titleVisibility: .visible
    ) {
      Button("Clear (Keep Pins)", role: .destructive) {
        Task { @MainActor in
          AppState.shared.history.clear()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will remove all unpinned clipboard history. Pinned items will be kept.")
    }
    .confirmationDialog(
      "Clear All History",
      isPresented: $showingClearAllConfirmation,
      titleVisibility: .visible
    ) {
      Button("Clear All", role: .destructive) {
        Task { @MainActor in
          AppState.shared.history.clearAll()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will remove ALL clipboard history including pinned items. This action cannot be undone.")
    }
  }
}

extension Bundle {
  var appVersion: String {
    infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
  }
}

#Preview {
  NavigationStack {
    iOSSettingsView()
  }
}
