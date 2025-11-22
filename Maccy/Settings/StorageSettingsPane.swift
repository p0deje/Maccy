import SwiftUI
import Defaults
import Settings

struct StorageSettingsPane: View {
  @Observable
  class ViewModel {
    var saveFiles = false {
      didSet {
        Defaults.withoutPropagation {
          if saveFiles {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.files.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.files.types)
          }
        }
      }
    }

    var saveImages = false {
      didSet {
        Defaults.withoutPropagation {
          if saveImages {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.images.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.images.types)
          }
        }
      }
    }

    var saveText = false {
      didSet {
        Defaults.withoutPropagation {
          if saveText {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.text.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.text.types)
          }
        }
      }
    }

    private var observer: Defaults.Observation?

    init() {
      observer = Defaults.observe(.enabledPasteboardTypes) { change in
        self.saveFiles = change.newValue.isSuperset(of: StorageType.files.types)
        self.saveImages = change.newValue.isSuperset(of: StorageType.images.types)
        self.saveText = change.newValue.isSuperset(of: StorageType.text.types)
      }
    }

    deinit {
      observer?.invalidate()
    }
  }

  @Default(.size) private var size
  @Default(.isUnlimitedHistory) private var isUnlimitedHistory
  @Default(.sortBy) private var sortBy

  @State private var viewModel = ViewModel()
  @State private var storageSize = Storage.shared.size
  @State private var showWarning = false

  private let sizeFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 999
    return formatter
  }()

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(
        bottomDivider: true,
        label: { Text("Save", tableName: "StorageSettings") }
      ) {
        Toggle(
          isOn: $viewModel.saveFiles,
          label: { Text("Files", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: $viewModel.saveImages,
          label: { Text("Images", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: $viewModel.saveText,
          label: { Text("Text", tableName: "StorageSettings") }
        )
        Text("SaveDescription", tableName: "StorageSettings")
          .controlSize(.small)
          .foregroundStyle(.gray)
      }

      Settings.Section(label: { Text("Size", tableName: "StorageSettings") }) {
        Toggle(
          isOn: Binding(
            get: { isUnlimitedHistory },
            set: { newValue in
              if newValue && size > 5000 {
                showWarning = true
              }
              isUnlimitedHistory = newValue
            }
          ),
          label: { Text("Unlimited History", tableName: "StorageSettings") }
        )
        .help(Text("Store unlimited clipboard items. Large histories may impact performance.", tableName: "StorageSettings"))

        if isUnlimitedHistory {
          Text("⚠️ Items are loaded on-demand for better performance.", tableName: "StorageSettings")
            .controlSize(.small)
            .foregroundStyle(.orange)
            .padding(.leading, 20)
        }

        HStack {
          TextField("", value: $size, formatter: sizeFormatter)
            .frame(width: 80)
            .help(Text("SizeTooltip", tableName: "StorageSettings"))
            .disabled(isUnlimitedHistory)
          Stepper("", value: $size, in: 1...999)
            .labelsHidden()
            .disabled(isUnlimitedHistory)
          Text(storageSize)
            .controlSize(.small)
            .foregroundStyle(.gray)
            .help(Text("CurrentSizeTooltip", tableName: "StorageSettings"))
            .onAppear {
              storageSize = Storage.shared.size
            }
        }
        .opacity(isUnlimitedHistory ? 0.5 : 1.0)
      }

      Settings.Section(label: { Text("SortBy", tableName: "StorageSettings") }) {
        Picker("", selection: $sortBy) {
          ForEach(Sorter.By.allCases) { mode in
            Text(mode.description)
          }
        }
        .labelsHidden()
        .frame(width: 160, alignment: .leading)
        .help(Text("SortByTooltip", tableName: "StorageSettings"))
      }
    }
    .alert("Enable Unlimited History?", isPresented: $showWarning) {
      Button("Cancel", role: .cancel) {
        isUnlimitedHistory = false
      }
      Button("Enable") {
        // User confirmed, unlimited is already set
      }
    } message: {
      Text("You currently have a large history (\(size) items). Enabling unlimited history may impact performance. Items will be loaded on-demand to maintain responsiveness.")
    }
  }
}

#Preview {
  StorageSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
