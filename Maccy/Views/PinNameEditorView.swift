import SwiftUI

// Asks for the name of a pin, either while pinning an item or when renaming one.
// An empty name falls back to "Unnamed N".
struct PinNameEditorView: View {
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss

  let request: PinNamingRequest

  @State private var name: String
  @FocusState private var nameFocused: Bool

  init(request: PinNamingRequest) {
    self.request = request
    self._name = State(initialValue: request.mode == .rename ? (request.item.item.pinName ?? "") : "")
  }

  private var heading: String {
    switch request.mode {
    case .pin:
      return NSLocalizedString("pin_name_heading", value: "Name pinned item", comment: "")
    case .rename:
      return NSLocalizedString("pin_rename_heading", value: "Rename pinned item", comment: "")
    }
  }

  private var confirmTitle: String {
    switch request.mode {
    case .pin:
      return NSLocalizedString("pin_name_confirm", value: "Pin", comment: "")
    case .rename:
      return NSLocalizedString("pin_rename_confirm", value: "Save", comment: "")
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(heading)
        .font(.headline)

      Text(verbatim: request.item.title)
        .lineLimit(2)
        .truncationMode(.tail)
        .foregroundStyle(.secondary)

      TextField(
        appState.history.nextUnnamedPinName(excluding: request.item),
        text: $name
      )
      .textFieldStyle(.roundedBorder)
      .focused($nameFocused)
      .onSubmit(save)
      .accessibilityIdentifier("pin-name-field")

      HStack {
        Spacer()
        Button(NSLocalizedString("pin_name_cancel", value: "Cancel", comment: ""), role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button(confirmTitle, action: save)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("pin-name-save")
      }
    }
    .padding(16)
    .frame(width: 340)
    .onAppear { nameFocused = true }
    .onExitCommand { dismiss() }
  }

  private func save() {
    switch request.mode {
    case .pin:
      appState.history.pin(request.item, named: name)
    case .rename:
      appState.history.renamePin(request.item, to: name)
    }
    dismiss()
  }
}
