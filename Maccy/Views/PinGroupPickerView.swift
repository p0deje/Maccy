import SwiftData
import SwiftUI

struct PinGroupPickerView: View {
  @Environment(AppState.self) private var appState

  @State private var newGroupName: String = ""
  @State private var isCreatingNewGroup: Bool = false
  @FocusState private var newGroupFieldFocused: Bool

  // Per-group editing state
  @State private var editingGroupID: PersistentIdentifier?
  @State private var editingGroupName: String = ""
  @FocusState private var editFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("PinToGroupTitle", tableName: "PinGroups")
          .font(.headline)
        Spacer()
        Button {
          appState.cancelPinGroupPicker()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(Text("Close", tableName: "PinGroups"))
      }
      .padding(.bottom, 4)

      ForEach(PinGroupsManager.shared.groups, id: \.persistentModelID) { group in
        let isEditing = editingGroupID == group.persistentModelID

        if isEditing {
          // Inline rename mode
          HStack(spacing: 4) {
            TextField("", text: $editingGroupName)
              .focused($editFieldFocused)
              .textFieldStyle(.roundedBorder)
              .controlSize(.small)
              .onSubmit {
                commitRename(group)
              }

            Button {
              commitRename(group)
            } label: {
              Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            Button {
              cancelRename()
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .onAppear {
            editingGroupName = group.name
            editFieldFocused = true
          }
        } else {
          // Normal group row — clicking selects the group
          Button {
            appState.pinToGroup(group)
          } label: {
            HStack {
              Image(systemName: "folder")
                .frame(width: 16)
              Text(group.name)
                .lineLimit(1)
              Spacer()
              Text("\(group.items.count)")
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.primary.opacity(0.05))
          )
          .contextMenu {
            Button {
              startRename(group)
            } label: {
              Label(
                NSLocalizedString("RenameGroup", tableName: "PinGroups", comment: ""),
                systemImage: "pencil"
              )
            }

            Divider()

            Button(role: .destructive) {
              deleteGroup(group)
            } label: {
              Label(
                NSLocalizedString("DeleteGroup", tableName: "PinGroups", comment: ""),
                systemImage: "trash"
              )
            }
            .disabled(group.items.isEmpty == false && group.persistentModelID == PinGroupsManager.shared.groups.first?.persistentModelID)
          }
        }
      }

      Divider()
        .padding(.vertical, 4)

      if isCreatingNewGroup {
        HStack {
          TextField(
            NSLocalizedString("NewGroupPlaceholder", tableName: "PinGroups", comment: ""),
            text: $newGroupName
          )
          .focused($newGroupFieldFocused)
          .textFieldStyle(.roundedBorder)
          .controlSize(.small)
          .onSubmit {
            createGroup()
          }

          Button {
            createGroup()
          } label: {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.accentColor)
          }
          .buttonStyle(.plain)
          .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)

          Button {
            isCreatingNewGroup = false
            newGroupName = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.secondary)
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
      } else {
        Button {
          isCreatingNewGroup = true
          newGroupName = ""
          newGroupFieldFocused = true
        } label: {
          HStack {
            Image(systemName: "plus.circle")
            Text("NewPinGroup", tableName: "PinGroups")
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .frame(width: 240)
  }

  // MARK: - Group rename

  private func startRename(_ group: PinGroup) {
    editingGroupID = group.persistentModelID
    editingGroupName = group.name
    editFieldFocused = true
  }

  private func commitRename(_ group: PinGroup) {
    let trimmed = editingGroupName.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty, trimmed != group.name {
      PinGroupsManager.shared.renameGroup(group, to: trimmed)
    }
    cancelRename()
  }

  private func cancelRename() {
    editingGroupID = nil
    editingGroupName = ""
  }

  // MARK: - Group delete

  private func deleteGroup(_ group: PinGroup) {
    PinGroupsManager.shared.deleteGroup(group)
  }

  // MARK: - Create group

  private func createGroup() {
    let name = newGroupName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    let group = PinGroupsManager.shared.createGroup(name: name)
    isCreatingNewGroup = false
    newGroupName = ""
    appState.pinToGroup(group)
  }
}
