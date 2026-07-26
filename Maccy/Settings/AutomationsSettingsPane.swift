import SwiftUI
import Defaults
import Observation

// Observes the Application Scripts directory while the pane is visible so newly added or
// removed scripts appear in the picker in real time.
@MainActor
@Observable
final class ScriptsDirectoryModel {
  var scripts: [String] = []

  @ObservationIgnored
  private var watcher: DirectoryWatcher?

  func start() {
    reload()
    guard let directory = ScriptRunner.shared.scriptsDirectory else { return }
    watcher = DirectoryWatcher(url: directory) { [weak self] in
      self?.reload()
    }
    watcher?.start()
  }

  func stop() {
    watcher?.stop()
    watcher = nil
  }

  func reload() {
    scripts = ScriptRunner.shared.availableScripts()
  }
}

struct AutomationsSettingsPane: View {
  @Default(.automations) private var automations

  @State private var selection: UUID?
  @State private var scriptsModel = ScriptsDirectoryModel()

  var body: some View {
    VStack(alignment: .leading) {
      List(selection: $selection) {
        ForEach($automations) { $automation in
          HStack {
            Toggle("", isOn: $automation.isEnabled)
              .labelsHidden()
            Text(automation.name.isEmpty
              ? String(localized: "Untitled", table: "AutomationsSettings")
              : automation.name)
          }
          .tag(automation.id)
        }
        .onMove { indexes, destination in
          automations.move(fromOffsets: indexes, toOffset: destination)
        }
      }
      .frame(minHeight: 140)
      .scrollContentBackground(.hidden)
      .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))

      ControlGroup {
        Button("", systemImage: "plus") {
          add()
        }
        Button("", systemImage: "minus") {
          removeSelected()
        }
      }
      .frame(width: 50)

      if let selection, automations.contains(where: { $0.id == selection }) {
        Divider()
        editor(automationBinding(selection))
      } else {
        Text("SelectOrAddHint", tableName: "AutomationsSettings")
          .frame(maxWidth: .infinity, alignment: .center)
          .foregroundStyle(.gray)
          .controlSize(.small)
          .padding(.vertical)
      }
    }
    .frame(minWidth: 400, maxWidth: 480, minHeight: 460)
    .padding()
    .onAppear { scriptsModel.start() }
    .onDisappear { scriptsModel.stop() }
  }

  @ViewBuilder
  private func editor(_ automation: Binding<Automation>) -> some View {
    Form {
      TextField(text: automation.name, prompt: Text("NamePrompt", tableName: "AutomationsSettings")) {
        Text("Name", tableName: "AutomationsSettings")
      }

      TextField(text: automation.regexp, prompt: Text("RegexpPrompt", tableName: "AutomationsSettings")) {
        Text("Regexp", tableName: "AutomationsSettings")
      }
      .font(.body.monospaced())

      Picker(selection: .constant(0)) {
        Text("RunScript", tableName: "AutomationsSettings").tag(0)
      } label: {
        Text("Action", tableName: "AutomationsSettings")
      }

      HStack {
        Picker(selection: automation.scriptName) {
          Text("NoScript", tableName: "AutomationsSettings").tag("")
          ForEach(scriptOptions(selected: automation.wrappedValue.scriptName), id: \.self) { name in
            Text(name).tag(name)
          }
        } label: {
          Text("Script", tableName: "AutomationsSettings")
        }

        Button {
          ScriptRunner.shared.reveal()
          scriptsModel.reload()
        } label: {
          Text("RevealFolder", tableName: "AutomationsSettings")
        }
      }

      Toggle(isOn: automation.parseResultAsHTML) {
        Text("ParseAsHTML", tableName: "AutomationsSettings")
      }
    }

    Text("ScriptsHint", tableName: "AutomationsSettings")
      .fixedSize(horizontal: false, vertical: true)
      .foregroundStyle(.gray)
      .controlSize(.small)
      .padding(.top, 4)
  }

  private func scriptOptions(selected: String) -> [String] {
    var options = scriptsModel.scripts
    if !selected.isEmpty, !options.contains(selected) {
      options.insert(selected, at: 0)
    }
    return options
  }

  private func automationBinding(_ id: UUID) -> Binding<Automation> {
    Binding(
      get: { automations.first(where: { $0.id == id }) ?? Automation() },
      set: { newValue in
        if let index = automations.firstIndex(where: { $0.id == id }) {
          automations[index] = newValue
        }
      }
    )
  }

  private func add() {
    let automation = Automation()
    automations.append(automation)
    selection = automation.id
    scriptsModel.reload()
  }

  private func removeSelected() {
    guard let selection else { return }
    automations.removeAll { $0.id == selection }
    self.selection = nil
  }
}

#Preview {
  AutomationsSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
