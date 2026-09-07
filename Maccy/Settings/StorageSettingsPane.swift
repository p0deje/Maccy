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
  @Default(.extendedHistory) private var extendedHistory
  @Default(.sortBy) private var sortBy

  @State private var viewModel = ViewModel()
  @State private var storageSize = Storage.shared.size
  @State private var sizeInput = String(Defaults[.size])
  @State private var confirmReduction = false

  private var proposedSize: Int? {
    guard let value = Int(sizeInput) else { return nil }
    if extendedHistory { return value == -1 || value > 0 ? value : nil }
    return (1...History.cacheLimit).contains(value) ? value : nil
  }

  private func applySize() {
    guard let value = proposedSize else { return }
    if value > 0 && (size <= 0 || value < size) {
      confirmReduction = true
    } else {
      size = value
    }
  }

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
        HStack {
          TextField("", text: $sizeInput)
            .frame(width: 90)
            .accessibilityLabel(Text("Size", tableName: "StorageSettings"))
            .onSubmit { applySize() }
          Button { applySize() } label: { Text("ApplySize", tableName: "StorageSettings") }
            .disabled(proposedSize == nil || proposedSize == size)
          Text(storageSize)
            .controlSize(.small)
            .foregroundStyle(.secondary)
            .onAppear { storageSize = Storage.shared.size }
        }
        Toggle(isOn: $extendedHistory) {
          Text("ExtendedHistory", tableName: "StorageSettings")
        }
        .accessibilityIdentifier("extendedHistory")
        Text(extendedHistory ? "ExtendedHistoryDescription" : "StandardHistoryDescription",
             tableName: "StorageSettings")
          .font(.caption)
          .foregroundStyle(.secondary)
        if !extendedHistory && (size > History.cacheLimit || size == -1) {
          Text("ExistingExtendedLimit", tableName: "StorageSettings")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if proposedSize == nil && sizeInput != String(size) {
          Text(extendedHistory ? "InvalidExtendedSize" : "InvalidStandardSize", tableName: "StorageSettings")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

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
        .accessibilityLabel(Text("SortBy", tableName: "StorageSettings"))
      }
    }
    .onChange(of: size) { _, newValue in sizeInput = String(newValue) }
    .alert(Text("ReduceHistoryTitle", tableName: "StorageSettings"), isPresented: $confirmReduction) {
      Button(role: .cancel) {} label: { Text("CancelSizeChange", tableName: "StorageSettings") }
      Button(role: .destructive) {
        if let value = proposedSize { size = value }
      } label: { Text("ApplySize", tableName: "StorageSettings") }
    } message: {
      Text("ReduceHistoryDescription", tableName: "StorageSettings")
    }
  }
}

#Preview {
  StorageSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
