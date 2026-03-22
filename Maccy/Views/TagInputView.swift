import SwiftUI

struct TagInputView: View {
  @Environment(AppState.self) private var appState
  @FocusState private var isFocused: Bool
  @State private var autocompleteIndex: Int? = nil

  private var suggestions: [String] {
    let query = appState.taggingQuery.lowercased()
    guard !query.isEmpty else { return appState.history.allTags }
    return appState.history.allTags.filter { $0.hasPrefix(query) }
  }

  var body: some View {
    if appState.isTagging {
      let suggestions = self.suggestions
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 4) {
          Image(systemName: "tag")
            .foregroundStyle(.secondary)
            .frame(width: 12, height: 12)
          TextField(
            "",
            text: Bindable(appState).taggingQuery,
            prompt: Text("TagInputPlaceholder", tableName: "TagSettings")
          )
          .textFieldStyle(.plain)
          .focused($isFocused)
          .onSubmit {
            if let current = autocompleteIndex,
               !suggestions.isEmpty,
               !appState.taggingQuery.isEmpty {
              let index = min(max(current, 0), suggestions.count - 1)
              appState.taggingQuery = suggestions[index]
            }
            appState.commitTag()
          }
          .onExitCommand {
            appState.cancelTagging()
          }
          .onKeyPress(.downArrow) {
            if !suggestions.isEmpty {
              if let current = autocompleteIndex {
                autocompleteIndex = min(current + 1, suggestions.count - 1)
              } else {
                autocompleteIndex = 0
              }
            }
            return .handled
          }
          .onKeyPress(.upArrow) {
            if !suggestions.isEmpty {
              if let current = autocompleteIndex {
                autocompleteIndex = max(current - 1, 0)
              } else {
                autocompleteIndex = suggestions.count - 1
              }
            }
            return .handled
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)

        if !suggestions.isEmpty {
          Divider()
          ScrollView {
            let clamped = autocompleteIndex.map { min(max($0, 0), suggestions.count - 1) } ?? -1
            VStack(alignment: .leading, spacing: 0) {
              ForEach(Array(suggestions.enumerated()), id: \.element) { index, tag in
                let isSelected = index == clamped
                TagChipView(tag: tag)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 3)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .background(isSelected ? Color.accentColor.opacity(0.3) : .clear)
                  .cornerRadius(4)
                  .onTapGesture {
                    appState.taggingQuery = tag
                    appState.commitTag()
                  }
                  .onHover { hovering in
                    if hovering {
                      autocompleteIndex = index
                    }
                  }
              }
            }
          }
          .frame(maxHeight: 120)
          .padding(.vertical, 2)
        } else if !appState.taggingQuery.isEmpty {
          Divider()
          Text("No matching tags")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
      }
      .background(.regularMaterial)
      .cornerRadius(6)
      .shadow(radius: 4)
      .frame(width: 200)
      .onAppear {
        autocompleteIndex = nil
        Task {
          try? await Task.sleep(for: .milliseconds(150))
          isFocused = true
        }
      }
      .onChange(of: appState.taggingQuery) {
        autocompleteIndex = nil
      }
    } else {
      EmptyView()
    }
  }
}
