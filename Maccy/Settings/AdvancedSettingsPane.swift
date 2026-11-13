import SwiftUI
import Defaults

struct AdvancedSettingsPane: View {
  private var bundleIdentifier: String {
    Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy"
  }

  private func shellScript(_ key: String) -> String {
    NSLocalizedString(key, tableName: "AdvancedSettings", comment: "")
      .replacingOccurrences(of: "org.p0deje.Maccy", with: bundleIdentifier)
  }

  private var clearHistoryOnQuitTooltip: String {
    NSLocalizedString(
      "ClearHistoryOnQuitTooltipProtected",
      tableName: "AdvancedSettings",
      value: "Automatically remove all unpinned, unprotected items before quitting the application.",
      comment: ""
    )
  }

  var body: some View {
    VStack(alignment: .leading) {
      Defaults.Toggle(key: .ignoreEvents) {
        Text("TurnOff", tableName: "AdvancedSettings")
      }
      Text("TurnOffDescription", tableName: "AdvancedSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
      Text(verbatim: shellScript("TurnOffShellScript"))
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .font(.system(size: 11, design: .monospaced))
        .controlSize(.small)
        .padding(.vertical, 2)
      Text("TurnOffViaMenuIconDescription", tableName: "AdvancedSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
      Text(verbatim: shellScript("TurnOffNextShellScript"))
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .font(.system(size: 11, design: .monospaced))
        .controlSize(.small)
        .padding(.vertical, 2)

      Divider()

      Defaults.Toggle(key: .clearOnQuit) {
        Text("ClearHistoryOnQuit", tableName: "AdvancedSettings")
      }.help(Text(verbatim: clearHistoryOnQuitTooltip))

      Defaults.Toggle(key: .clearSystemClipboard) {
        Text("ClearSystemClipboard", tableName: "AdvancedSettings")
      }.help(Text("ClearSystemClipboardTooltip", tableName: "AdvancedSettings"))
    }
    .frame(minWidth: 350, maxWidth: 450)
    .padding()
  }
}

#Preview {
  AdvancedSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
