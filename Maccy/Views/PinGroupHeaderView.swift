import SwiftData
import SwiftUI

struct PinGroupHeaderView: View {
  let group: PinGroup
  let isExpanded: Bool
  let toggle: () -> Void

  @State private var isRenaming: Bool = false
  @State private var renameText: String = ""
  @FocusState private var renameFocused: Bool

  var body: some View {
    if isRenaming {
      // Inline rename
      HStack(spacing: 4) {
        Image(systemName: "folder")
          .font(.caption)
          .foregroundStyle(.secondary)

        TextField("", text: $renameText)
          .focused($renameFocused)
          .textFieldStyle(.plain)
          .font(.caption)
          .onSubmit { commitRename() }

        Button { commitRename() } label: {
          Image(systemName: "checkmark.circle.fill")
            .font(.caption)
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)

        Button { cancelRename() } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
      .onAppear {
        renameText = group.name
        renameFocused = true
      }
    } else {
      Button(action: toggle) {
        HStack(spacing: 4) {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption)
            .foregroundStyle(.secondary)

          Image(systemName: "folder")
            .font(.caption)
            .foregroundStyle(.secondary)

          Text(group.name)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)

          Spacer()

          Text("\(group.items.count)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
              Capsule()
                .fill(Color.primary.opacity(0.08))
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .contextMenu {
        Button {
          startRename()
        } label: {
          Label(
            NSLocalizedString("RenameGroup", tableName: "PinGroups", comment: ""),
            systemImage: "pencil"
          )
        }

        Divider()

        Button(role: .destructive) {
          PinGroupsManager.shared.deleteGroup(group)
        } label: {
          Label(
            NSLocalizedString("DeleteGroup", tableName: "PinGroups", comment: ""),
            systemImage: "trash"
          )
        }
      }
    }
  }

  private func startRename() {
    renameText = group.name
    isRenaming = true
    renameFocused = true
  }

  private func commitRename() {
    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty, trimmed != group.name {
      PinGroupsManager.shared.renameGroup(group, to: trimmed)
    }
    cancelRename()
  }

  private func cancelRename() {
    isRenaming = false
    renameText = ""
  }
}
