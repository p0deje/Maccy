import Defaults
import SwiftData
import SwiftUI

struct TagSettingsPane: View {
  @Environment(\.modelContext) private var modelContext

  @State private var tagEntries: [TagEntry] = []
  @State private var selection: String?

  var body: some View {
    VStack(alignment: .leading) {
      Table(tagEntries, selection: $selection) {
        TableColumn(Text("TagName", tableName: "TagSettings")) { entry in
          TextField("", text: Binding(
            get: { entry.name },
            set: { newName in renameTag(from: entry.name, to: newName) }
          ))
        }

        TableColumn(Text("Color", tableName: "TagSettings")) { entry in
          Picker("", selection: Binding(
            get: { entry.color },
            set: { newColor in
              Defaults[.tagColors][entry.name] = newColor
              loadTags()
            }
          )) {
            ForEach(TagColor.allCases) { tagColor in
              HStack(spacing: 4) {
                Circle()
                  .fill(tagColor.color)
                  .frame(width: 10, height: 10)
                Text(tagColor.displayName)
              }
              .tag(tagColor)
            }
          }
          .labelsHidden()
          .controlSize(.small)
        }
        .width(min: 100, max: 150)
      }

      HStack {
        Button(action: deleteSelectedTag) {
          Image(systemName: "minus")
        }
        .disabled(selection == nil)

        Spacer()

        Text("TagSettingsDescription", tableName: "TagSettings")
          .foregroundStyle(.gray)
          .controlSize(.small)
      }
    }
    .frame(minWidth: 400, minHeight: 300)
    .padding()
    .onAppear { loadTags() }
  }

  private func loadTags() {
    tagEntries = Defaults[.tagColors]
      .sorted(by: { $0.key < $1.key })
      .map { TagEntry(name: $0.key, color: $0.value) }
  }

  private func renameTag(from oldName: String, to newName: String) {
    let trimmed = newName.lowercased().trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, trimmed != oldName else { return }

    // Update Defaults
    let color = Defaults[.tagColors][oldName] ?? .gray
    Defaults[.tagColors].removeValue(forKey: oldName)
    Defaults[.tagColors][trimmed] = color

    // Cascade to all HistoryItems
    let descriptor = FetchDescriptor<HistoryItem>()
    if let items = try? modelContext.fetch(descriptor) {
      for item in items where item.tags.contains(oldName) {
        item.tags.removeAll { $0 == oldName }
        if !item.tags.contains(trimmed) {
          item.tags.append(trimmed)
          item.tags.sort()
        }
      }
      try? modelContext.save()
    }

    loadTags()
  }

  private func deleteSelectedTag() {
    guard let selected = selection else { return }

    // Remove from Defaults
    Defaults[.tagColors].removeValue(forKey: selected)

    // Cascade to all HistoryItems
    let descriptor = FetchDescriptor<HistoryItem>()
    if let items = try? modelContext.fetch(descriptor) {
      for item in items where item.tags.contains(selected) {
        item.tags.removeAll { $0 == selected }
      }
      try? modelContext.save()
    }

    selection = nil
    loadTags()
  }
}

struct TagEntry: Identifiable, Hashable {
  var id: String { name }
  var name: String
  var color: TagColor
}

#Preview {
  TagSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
    .modelContainer(Storage.shared.container)
}
