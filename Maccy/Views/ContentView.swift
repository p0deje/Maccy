import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var appState = AppState.shared
  @State private var modifierFlags = ModifierFlags()
  @State private var scenePhase: ScenePhase = .background

  @FocusState private var searchFocused: Bool
  @State private var selectedTab: Int = 0

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      KeyHandlingView(searchQuery: $appState.history.searchQuery, searchFocused: $searchFocused) {
        VStack(spacing: 0) {
          SlideoutView(controller: appState.preview) {
            HeaderView(
              controller: appState.preview,
              searchFocused: $searchFocused
            )

            Picker("", selection: $selectedTab) {
              Text("Clipboard").tag(0)
              Text("Pinned Comments").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Popup.horizontalPadding)
            .padding(.top, 4)
            .onChange(of: selectedTab) {
              appState.popup.needsResize = true
            }

            VStack(alignment: .leading, spacing: 0) {
              if selectedTab == 0 {
                HistoryListView(
                  searchQuery: $appState.history.searchQuery,
                  searchFocused: $searchFocused
                )
              } else {
                PinnedCommentsView()
              }

              FooterView(footer: appState.footer)
            }
            .animation(.default, value: selectedTab)
            .animation(.default.speed(3), value: appState.history.items)
            .animation(
              .default.speed(3),
              value: appState.history.pasteStack?.id
            )
            .padding(.horizontal, Popup.horizontalPadding)
            .onAppear {
              searchFocused = true
            }
            .onMouseMove {
              appState.navigator.isKeyboardNavigating = false
            }
          } slideout: {
            SlideoutContentView()
          }
          .frame(minHeight: 0)
          .layoutPriority(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .task {
        try? await appState.history.load()
      }
    }
    .animation(.easeInOut(duration: 0.2), value: appState.searchVisible)
    .environment(appState)
    .environment(modifierFlags)
    .environment(\.scenePhase, scenePhase)
    // FloatingPanel is not a scene, so let's implement custom scenePhase..
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
      if let window = $0.object as? NSWindow,
         let bundleIdentifier = Bundle.main.bundleIdentifier,
         window.identifier == NSUserInterfaceItemIdentifier(bundleIdentifier) {
        scenePhase = .active
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
      if let window = $0.object as? NSWindow,
         let bundleIdentifier = Bundle.main.bundleIdentifier,
         window.identifier == NSUserInterfaceItemIdentifier(bundleIdentifier) {
        scenePhase = .background
      }
    }
  }
}

#Preview {
  ContentView()
    .environment(\.locale, .init(identifier: "en"))
    .modelContainer(Storage.shared.container)
}


struct PinnedCommentsView: View {
  @Environment(AppState.self) private var appState
  @AppStorage("customTopics") private var customTopicsData: Data = Data()
  @AppStorage("expandedTopics") private var expandedTopicsData: Data = Data()

  private var customTopics: [String] {
    get {
      if let decoded = try? JSONDecoder().decode([String].self, from: customTopicsData) { return decoded }
      return []
    }
    nonmutating set {
      if let encoded = try? JSONEncoder().encode(newValue) { customTopicsData = encoded }
    }
  }

  private var expandedTopics: Set<String> {
    get {
      if let decoded = try? JSONDecoder().decode(Set<String>.self, from: expandedTopicsData) { return decoded }
      return Set(["Uncategorized"])
    }
    nonmutating set {
      if let encoded = try? JSONEncoder().encode(newValue) { expandedTopicsData = encoded }
    }
  }

  private func promptForNewTopic() {
    let alert = NSAlert()
    alert.messageText = "New Topic"
    alert.informativeText = "Enter a name for the new topic."
    alert.addButton(withTitle: "Add")
    alert.addButton(withTitle: "Cancel")
    
    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    alert.accessoryView = textField
    alert.window.initialFirstResponder = textField
    
    NSApp.activate(ignoringOtherApps: true)
    
    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      let trimmed = textField.stringValue.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty && !customTopics.contains(trimmed) {
        var updated = customTopics
        updated.append(trimmed)
        customTopics = updated
      }
    }
  }

  var body: some View {
    let pinnedItems = appState.history.pinnedItems
    let itemTopics = Set(pinnedItems.compactMap { $0.topic })
    let topics = itemTopics.union(customTopics).union(["Uncategorized"]).sorted()
    let grouped = Dictionary(grouping: pinnedItems, by: { $0.topic ?? "Uncategorized" })

    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Button("Import...") {
          importMemories()
        }
        .buttonStyle(.plain)

        Button("Export...") {
          exportMemories()
        }
        .buttonStyle(.plain)

        Spacer()
        Button(action: promptForNewTopic) {
          Text("Add Topic...")
            .font(.subheadline)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
      }
      .padding(.horizontal, 15)

      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(topics, id: \.self) { topic in
            let isExpanded = expandedTopics.contains(topic)
            VStack(alignment: .leading, spacing: 0) {
              HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                  .frame(width: 16)
                  .foregroundColor(.secondary)
                Text(topic)
                  .font(.headline)
                Spacer()
                if topic != "Uncategorized" {
                  Button(action: {
                    customTopics.removeAll { $0 == topic }
                    for item in grouped[topic] ?? [] {
                      item.topic = nil
                    }
                  }) {
                    Image(systemName: "trash")
                      .foregroundColor(.red)
                  }
                  .buttonStyle(.plain)
                  .help("Delete Topic")
                }
              }
              .padding(.top, 10)
              .padding(.horizontal, 10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
              .onTapGesture {
                var expanded = expandedTopics
                if expanded.contains(topic) {
                  expanded.remove(topic)
                } else {
                  expanded.insert(topic)
                }
                expandedTopics = expanded
                appState.popup.needsResize = true
              }

              if isExpanded {
                VStack(spacing: 0) {
                  ForEach(grouped[topic] ?? []) { item in
                    HistoryItemView(item: item, previous: nil, next: nil, index: -1)
                      .draggable(item.id.uuidString)
                  }
                }
                .padding(.top, 5)
              }
            }
            .dropDestination(for: String.self) { items, _ in
              for idString in items {
                if let id = UUID(uuidString: idString) {
                  DispatchQueue.main.async {
                    if let movedItem = appState.history.pinnedItems.first(where: { $0.id == id }) {
                      movedItem.topic = (topic == "Uncategorized") ? nil : topic
                    }
                  }
                }
              }
              return true
            }
          }
        }
        .padding(.vertical, 5)
        .background {
          GeometryReader { geo in
            Color.clear
              .task(id: appState.popup.needsResize) {
                try? await Task.sleep(for: .milliseconds(10))
                guard !Task.isCancelled else { return }

                if appState.popup.needsResize {
                  appState.popup.resize(height: geo.size.height)
                }
              }
          }
        }
      }
    }
  }

  private func exportMemories() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Maccy Memories.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      try appState.history.exportMemories(to: url)
    } catch {
      showArchiveError("Could not export memories", error: error)
    }
  }

  private func importMemories() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      try appState.history.importMemories(from: url)
      appState.popup.needsResize = true
    } catch {
      showArchiveError("Could not import memories", error: error)
    }
  }

  private func showArchiveError(_ message: String, error: Error) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = message
    alert.informativeText = error.localizedDescription
    alert.runModal()
  }
}
