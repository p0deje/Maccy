import SwiftData
import SwiftUI

struct PinPickerView: View {
  @Bindable var item: HistoryItem
  var availablePins: [String]

  var body: some View {
    if let pin = item.pin {
      Picker("", selection: $item.pin) {
        ForEach((availablePins + [pin]).sorted()) { pin in
          Text(pin)
            .tag(pin as String?)
        }
      }
      .controlSize(.small)
      .labelsHidden()
    }
  }
}

struct PinTitleView: View {
  @Bindable var item: HistoryItem

  var body: some View {
    TextField("", text: $item.title)
  }
}

struct PinValueView: View {
  @Bindable var item: HistoryItem
  @State private var editableValue: String
  @State private var isTextContent: Bool

  init(item: HistoryItem) {
    self.item = item
    self._editableValue = State(initialValue: item.previewableText)

    // Check if this item has editable text content
    let hasPlainText = item.text != nil
    let hasImage = item.image != nil
    let hasFileURLs = !item.fileURLs.isEmpty

    // Consider it text content only if it has plain text and doesn't have images or file URLs
    self._isTextContent = State(initialValue: hasPlainText && !hasImage && !hasFileURLs)
  }

  var body: some View {
    Group {
      if isTextContent {
        TextField("", text: $editableValue)
          .onSubmit {
            updateItemContent()
          }
          .onChange(of: editableValue) { _, _ in
            updateItemContent()
          }
      } else {
        // Non-editable display for non-text content
        Text("ContentIsNotText", tableName: "PinsSettings")
          .foregroundStyle(.secondary)
          .italic()
      }
    }
  }

  private func updateItemContent() {
    // Only update if we're dealing with text content
    guard isTextContent else { return }

    // Find string content if it exists
    let stringType = NSPasteboard.PasteboardType.string.rawValue
    if let index = item.contents.firstIndex(where: { $0.type == stringType }) {
      if let data = editableValue.data(using: .utf8) {
        item.contents[index].value = data
      }
    } else {
      // Create new string content if it doesn't exist
      if let data = editableValue.data(using: .utf8) {
        let newContent = HistoryItemContent(type: stringType, value: data)
        item.contents.append(newContent)
      }
    }

    // We don't automatically update title here since we want to preserve
    // OCR-extracted titles for images and other non-text content
  }
}

struct PinsSettingsPane: View {
  @Environment(AppState.self) private var appState
  @Environment(\.modelContext) private var modelContext

  @Query(filter: #Predicate<HistoryItem> { $0.pin != nil }, sort: \.firstCopiedAt)
  private var items: [HistoryItem]

  @State private var availablePins: [String] = []
  @State private var selection: PersistentIdentifier?

  var body: some View {
    VStack(alignment: .leading) {
      Table(items, selection: $selection) {
        TableColumn(Text("Key", tableName: "PinsSettings")) { item in
          PinPickerView(item: item, availablePins: availablePins)
            .onChange(of: item.pin) {
              availablePins = HistoryItem.availablePins
            }
        }
        .width(60)

        TableColumn(Text("Alias", tableName: "PinsSettings")) { item in
          PinTitleView(item: item)
        }

        TableColumn(Text("Content", tableName: "PinsSettings")) { item in
          PinValueView(item: item)
        }
      }
      .onAppear {
        availablePins = HistoryItem.availablePins
      }
      .onDeleteCommand {
        guard let selection,
              let item = appState.history.items.first(where: { $0.item.id == selection }) else {
          return
        }

        appState.history.delete(item)
      }

      Text("PinCustomizationDescription", tableName: "PinsSettings")
        .foregroundStyle(.gray)
        .controlSize(.small)
    }
    .frame(minWidth: 500, minHeight: 400)
    .padding()
  }
}

#Preview {
  return PinsSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
    .modelContainer(Storage.shared.container)
}
