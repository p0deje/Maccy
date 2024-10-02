import AppKit
import SwiftUI
import Defaults
import Settings

struct AppearanceSettingsPane: View {
  @Default(.popupPosition) private var popupAt
  @Default(.popupScreen) private var popupScreen
  @Default(.pinTo) private var pinTo
  @Default(.imageMaxHeight) private var imageHeight
  @Default(.previewDelay) private var previewDelay
  @Default(.highlightMatch) private var highlightMatch
  @Default(.menuIcon) private var menuIcon
  @Default(.showInStatusBar) private var showInStatusBar
  @Default(.showSearch) private var showSearch
  @Default(.searchVisibility) private var searchVisibility
  @Default(.showFooter) private var showFooter
  @Default(.windowPosition) private var windowPosition

  @State private var screens = NSScreen.screens

  private let imageHeightFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 200
    return formatter
  }()

  private let numberOfItemsFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 0
    formatter.maximum = 100
    return formatter
  }()

  private let titleLengthFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 30
    formatter.maximum = 200
    return formatter
  }()

  private let previewDelayFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 200
    formatter.maximum = 100_000
    return formatter
  }()

  var body: some View {
    Settings.Container(contentWidth: 650) {
      Settings.Section(label: { Text("PopupAt", tableName: "AppearanceSettings") }) {
        HStack {
          Picker("", selection: $popupAt) {
            ForEach(PopupPosition.allCases) { position in
              if position == .center || position == .lastPosition {
                if screens.count > 1 {
                  Picker(position.description, selection: $popupScreen) {
                    Text("ActiveScreen", tableName: "AppearanceSettings")
                      .tag(0)

                    ForEach(Array(screens.enumerated()), id: \.element) { index, screen in
                      Text(screen.localizedName)
                        .tag(index + 1)
                    }
                  }
                  .onChange(of: popupScreen) {
                    popupAt = position
                  }
                } else {
                  Text(position.description)
                }
              } else {
                Text(position.description)
              }
            }
          }
          .labelsHidden()
          .frame(width: 141)
          .help(Text("PopupAtTooltip", tableName: "AppearanceSettings"))

          if popupAt == .lastPosition {
            Button {
              _windowPosition.reset()
            } label: {
              Image(systemName: "arrow.uturn.backward.circle.fill")
                .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .help(Text("PopupAtLastLocationReset", tableName: "AppearanceSettings"))
            .disabled(windowPosition == _windowPosition.defaultValue)
          }
        }
      }

      Settings.Section(label: { Text("PinTo", tableName: "AppearanceSettings") }) {
        Picker("", selection: $pinTo) {
          ForEach(PinsPosition.allCases) { position in
            Text(position.description)
          }
        }
        .labelsHidden()
        .frame(width: 141)
        .help(Text("PinToTooltip", tableName: "AppearanceSettings"))
      }

      Settings.Section(label: { Text("ImageHeight", tableName: "AppearanceSettings") }) {
        HStack {
          TextField("", value: $imageHeight, formatter: imageHeightFormatter)
            .frame(width: 120)
            .help(Text("ImageHeightTooltip", tableName: "AppearanceSettings"))
          Stepper("", value: $imageHeight, in: 1...200)
            .labelsHidden()
        }
      }

      Settings.Section(label: { Text("PreviewDelay", tableName: "AppearanceSettings") }) {
        HStack {
          TextField("", value: $previewDelay, formatter: previewDelayFormatter)
            .frame(width: 120)
            .help(Text("PreviewDelayTooltip", tableName: "AppearanceSettings"))
          Stepper("", value: $previewDelay, in: 200...100_000)
            .labelsHidden()
        }
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("HighlightMatches", tableName: "AppearanceSettings") }
      ) {
        Picker("", selection: $highlightMatch) {
          ForEach(HighlightMatch.allCases) { match in
            Text(match.description)
          }
        }
        .labelsHidden()
        .frame(width: 141)
        .help(Text("HighlightMatchesTooltip", tableName: "AppearanceSettings"))
      }

      Settings.Section(title: "") {
        Defaults.Toggle(key: .showSpecialSymbols) {
          Text("ShowSpecialSymbols", tableName: "AppearanceSettings")
        }
        .help(Text("ShowSpecialSymbolsTooltip", tableName: "AppearanceSettings"))

        HStack {
          Defaults.Toggle(key: .showInStatusBar) {
            Text("ShowMenuIcon", tableName: "AppearanceSettings")
          }

          Picker("", selection: $menuIcon) {
            ForEach(MenuIcon.allCases) { icon in
              Image(nsImage: icon.image)
            }
          }
          .labelsHidden()
          .scaledToFit()
          .disabled(!showInStatusBar)
          .controlSize(.small)
        }

        Defaults.Toggle(key: .showRecentCopyInMenuBar) {
          Text("ShowRecentCopyInMenuBar", tableName: "AppearanceSettings")
        }
        HStack {
          Defaults.Toggle(key: .showSearch) {
            Text("ShowSearchField", tableName: "AppearanceSettings")
          }

          Picker("", selection: $searchVisibility) {
            ForEach(SearchVisibility.allCases) { type in
              Text(type.description)
            }
          }
          .labelsHidden()
          .scaledToFit()
          .disabled(!showSearch)
          .controlSize(.small)
        }
        Defaults.Toggle(key: .showTitle) {
          Text("ShowTitleBeforeSearchField", tableName: "AppearanceSettings")
        }

        Defaults.Toggle(key: .showFooter) {
          Text("ShowFooter", tableName: "AppearanceSettings")
        }
        Text("OpenPreferencesWarning", tableName: "AppearanceSettings")
          .opacity(showFooter ? 0 : 1)
          .controlSize(.small)
          .foregroundStyle(.gray)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
      screens = NSScreen.screens
    }
  }
}

#Preview {
  AppearanceSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
