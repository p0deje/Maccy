import Defaults
import KeyboardShortcuts
import Settings
import SwiftUI

struct QuickPasteSettingsPane: View {
  @Default(.enableQuickPaste) private var enableQuickPaste

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(title: "", bottomDivider: true) {
        Defaults.Toggle(key: .enableQuickPaste) {
          Text("EnableQuickPaste", tableName: "QuickPasteSettings")
        }
        .fixedSize()

        Text("EnableQuickPasteHelp", tableName: "QuickPasteSettings")
          .foregroundStyle(.secondary)
          .controlSize(.small)
          .fixedSize(horizontal: false, vertical: true)
      }

      Settings.Section(label: { Text("ModifierKeys", tableName: "QuickPasteSettings") }) {
        KeyboardShortcuts.Recorder(for: .quickPasteBase, onChange: QuickPasteSettings.applyModifiers)
          .help(Text("ModifierKeysTooltip", tableName: "QuickPasteSettings"))

        Text("ModifierKeysHelp", tableName: "QuickPasteSettings")
          .foregroundStyle(.secondary)
          .controlSize(.small)
          .fixedSize(horizontal: false, vertical: true)
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("ItemShortcuts", tableName: "QuickPasteSettings") }
      ) {
        ForEach(Array(KeyboardShortcuts.Name.quickPastes.enumerated()), id: \.offset) { index, name in
          HStack(alignment: .firstTextBaseline) {
            Text(itemLabel(for: index))
              .frame(width: 140, alignment: .leading)
            Spacer(minLength: 8)
            KeyboardShortcuts.Recorder(for: name)
          }
        }

        Text("ItemShortcutsHelp", tableName: "QuickPasteSettings")
          .foregroundStyle(.secondary)
          .controlSize(.small)
          .fixedSize(horizontal: false, vertical: true)
      }

      Settings.Section(title: "") {
        Button {
          QuickPasteSettings.resetToDefaults()
        } label: {
          Text("ResetToDefaults", tableName: "QuickPasteSettings")
        }
      }
    }
  }

  private func itemLabel(for index: Int) -> String {
    String(
      format: NSLocalizedString("ItemFormat", tableName: "QuickPasteSettings", comment: ""),
      index + 1
    )
  }
}

#Preview {
  QuickPasteSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
