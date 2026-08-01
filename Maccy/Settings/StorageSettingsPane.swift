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
  @Default(.sortBy) private var sortBy
  @Default(.pinSortBy) private var pinSortBy

  @State private var viewModel = ViewModel()
  @State private var storageSize = Storage.shared.size
  @State private var pendingPinSortBy: Sorter.PinBy?

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
        HStack {
          TextField("", value: $size, formatter: sizeFormatter)
            .frame(width: 80)
            .help(Text("SizeTooltip", tableName: "StorageSettings"))
          Stepper("", value: $size, in: 1...999)
            .labelsHidden()
          Text(storageSize)
            .controlSize(.small)
            .foregroundStyle(.gray)
            .help(Text("CurrentSizeTooltip", tableName: "StorageSettings"))
            .onAppear {
              storageSize = Storage.shared.size
            }
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
      }

      Settings.Section(label: { Text("SortPinsBy", tableName: "StorageSettings") }) {
        Picker("", selection: pinSortBySelection) {
          ForEach(Sorter.PinBy.allCases) { mode in
            Text(mode.description)
          }
        }
        .labelsHidden()
        .frame(width: 160, alignment: .leading)

        Text("SortPinsByDescription", tableName: "StorageSettings")
          .fixedSize(horizontal: false, vertical: true)
          .controlSize(.small)
          .foregroundStyle(.gray)
      }
    }
    .alert(
      Text("PinSortWarningTitle", tableName: "StorageSettings"),
      isPresented: isShowingPinSortWarning,
      presenting: pendingPinSortBy
    ) { pendingPinSortBy in
      Button(role: .destructive) {
        applyPinSorting(pendingPinSortBy)
      } label: {
        Text("PinSortWarningConfirm", tableName: "StorageSettings")
      }
      Button(role: .cancel) {
      } label: {
        Text("PinSortWarningCancel", tableName: "StorageSettings")
      }
    } message: { _ in
      Text("PinSortWarningMessage", tableName: "StorageSettings")
    }
  }

  private var pinSortBySelection: Binding<Sorter.PinBy> {
    Binding(
      get: { pinSortBy },
      set: { newValue in
        if pinSortBy == .custom,
           newValue != .custom,
           History.shared.pinSortingWouldChangeCurrentOrder(newValue) {
          pendingPinSortBy = newValue
        } else {
          applyPinSorting(newValue)
        }
      }
    )
  }

  private var isShowingPinSortWarning: Binding<Bool> {
    Binding(
      get: { pendingPinSortBy != nil },
      set: { isPresented in
        if !isPresented {
          pendingPinSortBy = nil
        }
      }
    )
  }

  private func applyPinSorting(_ pinSortBy: Sorter.PinBy) {
    History.shared.setPinSorting(pinSortBy)
    pendingPinSortBy = nil
  }
}

#Preview {
  StorageSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
