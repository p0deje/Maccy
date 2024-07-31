import SwiftUI
import Defaults
import Settings

class StorageSettingsViewModel: ObservableObject {
  @Published
  var saveFiles = false {
    didSet {
      Defaults.withoutPropagation {
        if saveFiles {
          Defaults[.enabledPasteboardTypes].insert(.fileURL)
        } else {
          Defaults[.enabledPasteboardTypes].remove(.fileURL)
        }
      }
    }
  }

  @Published
  var saveImages = false {
    didSet {
      Defaults.withoutPropagation {
        if saveImages {
          Defaults[.enabledPasteboardTypes].formUnion([.tiff, .png])
        } else {
          Defaults[.enabledPasteboardTypes].subtract([.tiff, .png])
        }
      }
    }
  }

  @Published
  var saveText = false {
    didSet {
      Defaults.withoutPropagation {
        if saveText {
          Defaults[.enabledPasteboardTypes].formUnion([.html, .rtf, .string])
        } else {
          Defaults[.enabledPasteboardTypes].subtract([.html, .rtf, .string])
        }
      }
    }
  }

  private var observer: Defaults.Observation?

  init() {
    observer = Defaults.observe(.enabledPasteboardTypes) { change in
      self.saveFiles = change.newValue.contains(.fileURL)
      self.saveImages = change.newValue.isSuperset(of: [.tiff, .png])
      self.saveText = change.newValue.isSuperset(of: [.html, .rtf, .string])
    }
  }

  deinit {
    observer?.invalidate()
  }
}

struct StorageSettingsPane: View {
  @Default(.size) private var size
  @Default(.sortBy) private var sortBy

  @StateObject private var storageSettingsViewModel = StorageSettingsViewModel()

  private let sizeFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 9999
    return formatter
  }()

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(
        bottomDivider: true,
        label: { Text("Save", tableName: "StorageSettings") }
      ) {
        Toggle(
          isOn: $storageSettingsViewModel.saveFiles,
          label: { Text("Files", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: $storageSettingsViewModel.saveImages,
          label: { Text("Images", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: $storageSettingsViewModel.saveText,
          label: { Text("Text", tableName: "StorageSettings") }
        )
        Text("SaveDescription", tableName: "StorageSettings")
          .controlSize(.small).foregroundStyle(.gray)
      }

      Settings.Section(label: { Text("Size", tableName: "StorageSettings") }) {
        HStack {
          TextField("", value: $size, formatter: sizeFormatter)
            .frame(width: 80)
            .help(Text("SizeTooltip", tableName: "StorageSettings"))
          Stepper("", value: $size, in: 1...9999)
            .labelsHidden()
        }
      }

      Settings.Section(label: { Text("SortBy", tableName: "StorageSettings") }) {
        Picker("", selection: $sortBy) {
          ForEach(Sorter.By.allCases) { mode in
            Text(mode.description)
          }
        }.labelsHidden().frame(width: 160)
          .help(Text("SortByTooltip", tableName: "StorageSettings"))
      }
    }
  }
}

#Preview {
  StorageSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
