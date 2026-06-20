import SwiftData
import SwiftUI

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

// MARK: - Group Management

struct PinGroupRowView: View {
  let group: PinGroup
  let itemCount: Int
  let onRename: (String) -> Void
  let onDelete: () -> Void

  @State private var isEditing: Bool = false
  @State private var editedName: String = ""
  @FocusState private var nameFocused: Bool

  var body: some View {
    HStack {
      if isEditing {
        TextField("", text: $editedName)
          .focused($nameFocused)
          .textFieldStyle(.roundedBorder)
          .controlSize(.small)
          .frame(width: 120)
          .onSubmit {
            let trimmed = editedName.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
              onRename(trimmed)
            }
            isEditing = false
          }
          .onAppear {
            editedName = group.name
            nameFocused = true
          }

        Button {
          let trimmed = editedName.trimmingCharacters(in: .whitespaces)
          if !trimmed.isEmpty {
            onRename(trimmed)
          }
          isEditing = false
        } label: {
          Image(systemName: "checkmark.circle.fill")
        }
        .buttonStyle(.plain)

        Button {
          isEditing = false
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
      } else {
        Image(systemName: "folder")
          .foregroundColor(.secondary)
        Text(group.name)
          .lineLimit(1)
        Text("(\(itemCount))")
          .foregroundStyle(.secondary)
          .font(.caption)

        Button {
          editedName = group.name
          isEditing = true
          nameFocused = true
        } label: {
          Image(systemName: "pencil")
            .font(.caption)
        }
        .buttonStyle(.plain)
        .help(Text("RenameGroup", tableName: "PinsSettings"))

        if itemCount == 0 {
          Button(action: onDelete) {
            Image(systemName: "trash")
              .font(.caption)
              .foregroundColor(.red)
          }
          .buttonStyle(.plain)
          .help(Text("DeleteGroup", tableName: "PinsSettings"))
        }
      }
    }
    .padding(.vertical, 2)
    .padding(.horizontal, 8)
    .background(
      RoundedRectangle(cornerRadius: 4)
        .fill(Color.primary.opacity(0.05))
    )
  }
}

struct PinGroupPickerForSettingsView: View {
  @Bindable var item: HistoryItem
  let groups: [PinGroup]

  var body: some View {
    Picker("", selection: $item.pinGroup) {
      Text("NoGroup", tableName: "PinsSettings")
        .tag(nil as PinGroup?)
      ForEach(groups, id: \.persistentModelID) { group in
        Text(group.name)
          .tag(group as PinGroup?)
      }
    }
    .controlSize(.small)
    .labelsHidden()
  }
}

struct PinsSettingsPane: View {
  @Environment(AppState.self) private var appState
  @Environment(\.modelContext) private var modelContext

  @Query(filter: #Predicate<HistoryItem> { $0.pin != nil }, sort: \.firstCopiedAt)
  private var items: [HistoryItem]

  @State private var availablePins: [String] = []
  @State private var selection: PersistentIdentifier?
  @State private var groups: [PinGroup] = []
  @State private var newGroupName: String = ""
  @State private var isAddingGroup: Bool = false
  @FocusState private var newGroupFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Group management section
      VStack(alignment: .leading, spacing: 8) {
        Text("PinGroupsHeader", tableName: "PinsSettings")
          .font(.headline)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(groups, id: \.persistentModelID) { group in
              PinGroupRowView(
                group: group,
                itemCount: group.items.count,
                onRename: { newName in
                  PinGroupsManager.shared.renameGroup(group, to: newName)
                  refreshGroups()
                },
                onDelete: {
                  PinGroupsManager.shared.deleteGroup(group)
                  refreshGroups()
                }
              )
            }

            if isAddingGroup {
              HStack {
                TextField(
                  NSLocalizedString("NewGroupPlaceholder", tableName: "PinGroups", comment: ""),
                  text: $newGroupName
                )
                .focused($newGroupFieldFocused)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 120)
                .onSubmit {
                  addGroup()
                }

                Button(action: addGroup) {
                  Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.plain)

                Button {
                  isAddingGroup = false
                  newGroupName = ""
                } label: {
                  Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
              }
              .padding(.vertical, 2)
              .padding(.horizontal, 8)
              .background(
                RoundedRectangle(cornerRadius: 4)
                  .fill(Color.primary.opacity(0.05))
              )
            } else {
              Button {
                isAddingGroup = true
                newGroupName = ""
                newGroupFieldFocused = true
              } label: {
                HStack {
                  Image(systemName: "plus.circle")
                  Text("NewPinGroup", tableName: "PinGroups")
                }
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, 2)
        }
      }
      .padding(.bottom, 12)

      Divider()
        .padding(.bottom, 12)

      // Pinned items table
      Table(items, selection: $selection) {
        TableColumn(Text("Key", tableName: "PinsSettings")) { item in
          PinPickerView(item: item, availablePins: availablePins)
            .onChange(of: item.pin) {
              availablePins = HistoryItem.availablePins
            }
        }
        .width(60)

        TableColumn(Text("Group", tableName: "PinsSettings")) { item in
          PinGroupPickerForSettingsView(item: item, groups: groups)
        }
        .width(100)

        TableColumn(Text("Alias", tableName: "PinsSettings")) { item in
          PinTitleView(item: item)
        }

        TableColumn(Text("Content", tableName: "PinsSettings")) { item in
          PinValueView(item: item)
        }
      }
      .onAppear {
        availablePins = HistoryItem.availablePins
        refreshGroups()
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
        .padding(.top, 8)
    }
    .frame(minWidth: 550, minHeight: 450)
    .padding()
  }

  private func addGroup() {
    let name = newGroupName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    _ = PinGroupsManager.shared.createGroup(name: name)
    isAddingGroup = false
    newGroupName = ""
    refreshGroups()
  }

  private func refreshGroups() {
    groups = PinGroupsManager.shared.groups
  }
}

#Preview {
  return PinsSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
    .modelContainer(Storage.shared.container)
}
