import SwiftData
import SwiftUI
import Defaults

struct PinPickerView: View {
  @Bindable var item: HistoryItem
  var availablePins: [String]

  var body: some View {
    if let pin = item.pin {
      // Ensure unique pins for ForEach
      let uniquePins = Array(Set(availablePins + [pin])).sorted()
      Picker("", selection: $item.pin) {
        ForEach(uniquePins, id: \.self) { pin in
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
  @State private var isRichText: Bool
  @FocusState private var isEditing: Bool
  @State private var showWarningPopover: Bool = false

  init(item: HistoryItem) {
    self.item = item
    self._editableValue = State(initialValue: item.previewableText)

    // Check if this item has editable text content
    let hasPlainText = item.text != nil
    let hasImage = item.image != nil
    let hasFileURLs = !item.fileURLs.isEmpty
    let hasRichText = item.rtf != nil || item.html != nil

    // Consider it text content only if it has plain text and doesn't have images or file URLs
    self._isTextContent = State(initialValue: hasPlainText && !hasImage && !hasFileURLs)
    self._isRichText = State(initialValue: hasRichText && !hasImage && !hasFileURLs)
  }

  var body: some View {
    Group {
      if isTextContent || isRichText {
        ZStack(alignment: .trailing) {
          TextField("", text: $editableValue)
            .focused($isEditing)
            .onSubmit {
              updateItemContent()
            }
            .onChange(of: editableValue) { _, _ in
              updateItemContent()
            }
            .padding(.trailing, isRichText ? 40 : 0) // increased space for icon

          if isRichText && isEditing {
            HStack(spacing: 0) {
              Spacer(minLength: 0)
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .help(Text("RichTextEditWarning", tableName: "PinsSettings"))
              Spacer().frame(width: 4)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.trailing, 4)
          }
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
    // Only update if we're dealing with text or rich text content
    guard isTextContent || isRichText else { return }

    // Remove all non-plain-text content
    let stringType = NSPasteboard.PasteboardType.string.rawValue
    item.contents.removeAll { $0.type != stringType }

    // Update or add the plain text content
    if let index = item.contents.firstIndex(where: { $0.type == stringType }) {
      if let data = editableValue.data(using: .utf8) {
        item.contents[index].value = data
      }
    } else {
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

  @Query(filter: #Predicate<HistoryItem> { $0.pin != nil })
  private var allItems: [HistoryItem]

  @State private var availablePins: [String] = []
  @State private var selection: PersistentIdentifier?
  @Default(.pinSortBy) private var pinSortBy: Sorter.By
  @Default(.pinSortAscending) private var pinSortAscending: Bool

  private var sortedItems: [HistoryItem] {
    allItems.sorted {
      switch pinSortBy {
      case .firstCopiedAt:
        return pinSortAscending ? ($0.firstCopiedAt < $1.firstCopiedAt) : ($0.firstCopiedAt > $1.firstCopiedAt)
      case .lastCopiedAt:
        return pinSortAscending ? ($0.lastCopiedAt < $1.lastCopiedAt) : ($0.lastCopiedAt > $1.lastCopiedAt)
      case .numberOfCopies:
        return pinSortAscending ? ($0.numberOfCopies < $1.numberOfCopies) : ($0.numberOfCopies > $1.numberOfCopies)
      case .pinKey:
        // Ascending: A-Z, Descending: Z-A
        return pinSortAscending ? (($0.pin ?? "") < ($1.pin ?? "")) : (($0.pin ?? "") > ($1.pin ?? ""))
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading) {
      Section {
        HStack {
          Picker("", selection: $pinSortBy) {
            ForEach(Sorter.By.allCases) { mode in
              Text(mode.description)
            }
          }
          .labelsHidden()
          .frame(width: 160)
          .help(Text("SortByTooltip", tableName: "PinsSettings"))

          HStack(spacing: 8) {
            Text("Descending")
            Toggle(isOn: $pinSortAscending) {
              EmptyView()
            }
            .toggleStyle(.switch)
            .frame(width: 40)
            Text("Ascending")
          }
          .help(Text("SortOrderTooltip", tableName: "PinsSettings"))
        }
      }

      Table(sortedItems, selection: $selection) {
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
