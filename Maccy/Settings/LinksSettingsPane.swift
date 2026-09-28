import SwiftUI
import Defaults
import KeyboardShortcuts
import Settings

struct LinksSettingsPane: View {
  @Default(.linkRules) private var rules

  @State private var selection: LinkRule.ID?
  @State private var sample = "ABC-123"

  var body: some View {
    Settings.Container(contentWidth: 500) {
      Settings.Section(label: { Text("Shortcut", tableName: "LinksSettings") }) {
        KeyboardShortcuts.Recorder(for: .openLink)
          .help(Text("ShortcutTooltip", tableName: "LinksSettings"))
          .accessibilityLabel(Text("Shortcut", tableName: "LinksSettings"))
      }

      Settings.Section(title: "") {
        VStack(alignment: .leading) {
          List(selection: $selection) {
            ForEach($rules) { $rule in
              LinkRuleRow(rule: $rule).tag(rule.id)
            }
            .onMove { rules.move(fromOffsets: $0, toOffset: $1) }
          }
          .frame(minHeight: 200)
          .onDeleteCommand(perform: removeSelected)

          ControlGroup {
            Button("", systemImage: "plus") {
              let rule = LinkRule(name: "", pattern: "^(.+)$", urlTemplate: "https://example.com/{1}")
              rules.append(rule)
              selection = rule.id
            }
            Button("", systemImage: "minus", action: removeSelected)
              .disabled(selection == nil)
          }.frame(width: 50)

          Text("RulesDescription", tableName: "LinksSettings")
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.gray)
            .controlSize(.small)
        }
      }

      Settings.Section(label: { Text("Test", tableName: "LinksSettings") }) {
        VStack(alignment: .leading) {
          TextField("", text: $sample)
            .frame(width: 300)
          Group {
            if let url = LinkOpener.url(for: sample, rules: rules) {
              Link(url.absoluteString, destination: url)
            } else {
              Text("NoMatch", tableName: "LinksSettings").foregroundStyle(.gray)
            }
          }
          .controlSize(.small)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(width: 300, alignment: .leading)
        }
      }
    }
  }

  private func removeSelected() {
    guard let selection else { return }
    rules.removeAll { $0.id == selection }
    self.selection = nil
  }
}

private struct LinkRuleRow: View {
  @Binding var rule: LinkRule

  var body: some View {
    HStack(alignment: .top) {
      Toggle("", isOn: $rule.enabled)
        .labelsHidden()
      VStack(alignment: .leading, spacing: 4) {
        TextField(
          String(localized: "Name", table: "LinksSettings"),
          text: $rule.name
        )
        .font(.headline)
        TextField(
          String(localized: "Pattern", table: "LinksSettings"),
          text: $rule.pattern
        )
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(rule.regex == nil ? .red : .primary)
        TextField(
          String(localized: "URL", table: "LinksSettings"),
          text: $rule.urlTemplate
        )
        .font(.system(.body, design: .monospaced))
      }
      .textFieldStyle(.roundedBorder)
    }
    .padding(.vertical, 4)
  }
}

#Preview {
  LinksSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
