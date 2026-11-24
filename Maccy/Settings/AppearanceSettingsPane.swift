import AppKit
import SwiftUI
import Defaults

struct AppearanceSettingsPane: View {
  @Default(.popupPosition) private var popupAt
  @Default(.popupScreen) private var popupScreen
  @Default(.pinTo) private var pinTo
  @Default(.imageMaxHeight) private var imageHeight
  @Default(.openPreviewAutomatically) private var openPreviewAutomatically
  @Default(.previewDelay) private var previewDelay
  @Default(.highlightMatch) private var highlightMatch
  @Default(.menuIcon) private var menuIcon
  @Default(.showInStatusBar) private var showInStatusBar
  @Default(.showSearch) private var showSearch
  @Default(.searchVisibility) private var searchVisibility
  @Default(.showFooter) private var showFooter
  @Default(.compactFooter) private var compactFooter
  @Default(.windowPosition) private var windowPosition
  @Default(.showApplicationIcons) private var showApplicationIcons

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
    ModernSettings.Container {
      ModernSettings.Section(title: "") {
        SettingsAppearancePreview()
      }
      ModernSettings.Section(label: { Text("PopupAt", tableName: "AppearanceSettings") }) {
        HStack {
          Picker("", selection: $popupAt) {
            ForEach(PopupPosition.allCases) { position in
              if position == .center || position == .lastPosition, screens.count > 1 {
                screenPicker(for: position)
              } else {
                Text(position.description)
              }
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .fixedSize()
          .help(Text("PopupAtTooltip", tableName: "AppearanceSettings"))
          .accessibilityLabel(Text("PopupAt", tableName: "AppearanceSettings"))

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

      ModernSettings.Section(label: { Text("PinTo", tableName: "AppearanceSettings") }) {
        Picker("", selection: $pinTo) {
          ForEach(PinsPosition.allCases) { position in
            Text(position.description)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .help(Text("PinToTooltip", tableName: "AppearanceSettings"))
        .accessibilityLabel(Text("PinTo", tableName: "AppearanceSettings"))
      }

      ModernSettings.Section(label: { Text("ImageHeight", tableName: "AppearanceSettings") }) {
        HStack {
          TextField("", value: $imageHeight, formatter: imageHeightFormatter)
            .frame(width: 120)
            .help(Text("ImageHeightTooltip", tableName: "AppearanceSettings"))
            .accessibilityLabel(Text("ImageHeight", tableName: "AppearanceSettings"))
          Stepper("", value: $imageHeight, in: 1...200)
            .labelsHidden()
            .accessibilityLabel(Text("ImageHeight", tableName: "AppearanceSettings"))
        }
      }

      ModernSettings.Section(title: "") {
        Defaults.Toggle(key: .openPreviewAutomatically) {
          Text("OpenPreviewAutomatically", tableName: "AppearanceSettings")
        }
      }

      ModernSettings.Section(label: { Text("PreviewDelay", tableName: "AppearanceSettings") }) {
        HStack {
          TextField("", value: $previewDelay, formatter: previewDelayFormatter)
            .frame(width: 120)
            .help(Text("PreviewDelayTooltip", tableName: "AppearanceSettings"))
            .accessibilityLabel(Text("PreviewDelay", tableName: "AppearanceSettings"))
          Stepper("", value: $previewDelay, in: 200...100_000)
            .labelsHidden()
            .accessibilityLabel(Text("PreviewDelay", tableName: "AppearanceSettings"))
        }
        .disabled(!openPreviewAutomatically)
      }

      ModernSettings.Section(
        label: { Text("HighlightMatches", tableName: "AppearanceSettings") }
      ) {
        Picker("", selection: $highlightMatch) {
          ForEach(HighlightMatch.allCases) { match in
            Text(match.description)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .help(Text("HighlightMatchesTooltip", tableName: "AppearanceSettings"))
        .accessibilityLabel(Text("HighlightMatches", tableName: "AppearanceSettings"))
      }

      ModernSettings.Section(title: "") {
        Defaults.Toggle(key: .showSpecialSymbols) {
          Text("ShowSpecialSymbols", tableName: "AppearanceSettings")
        }
        .help(Text("ShowSpecialSymbolsTooltip", tableName: "AppearanceSettings"))

        HStack(spacing: 16) {
          Text("ShowMenuIcon", tableName: "AppearanceSettings")
          Spacer(minLength: 8)
          HStack(spacing: 8) {
            ForEach(MenuIcon.allCases) { icon in
              Button {
                menuIcon = icon
              } label: {
                Image(nsImage: icon.image)
                  .frame(width: 42, height: 36)
                  .background(.quaternary.opacity(menuIcon == icon ? 0.8 : 0.3),
                              in: RoundedRectangle(cornerRadius: 8))
                  .overlay {
                    RoundedRectangle(cornerRadius: 8)
                      .strokeBorder(menuIcon == icon ? Color.accentColor : Color.secondary.opacity(0.25),
                                    lineWidth: menuIcon == icon ? 2 : 1)
                  }
                  .contentShape(RoundedRectangle(cornerRadius: 8))
              }
              .buttonStyle(.plain)
              .accessibilityLabel(Text(icon.description))
              .accessibilityAddTraits(menuIcon == icon ? .isSelected : [])
              .help(Text(icon.description))
            }
          }
          .disabled(!showInStatusBar)
          .opacity(showInStatusBar ? 1 : 0.5)
          .accessibilityElement(children: .contain)
          .accessibilityLabel(Text("MenuIcon", tableName: "AppearanceSettings"))
          .accessibilityIdentifier("menu-icon-picker")

          Toggle(isOn: $showInStatusBar) {
            Text("ShowMenuIcon", tableName: "AppearanceSettings")
          }
          .labelsHidden()
          .fixedSize()
        }

        Defaults.Toggle(key: .showRecentCopyInMenuBar) {
          Text("ShowRecentCopyInMenuBar", tableName: "AppearanceSettings")
        }
        HStack(spacing: 16) {
          Text("ShowSearchField", tableName: "AppearanceSettings")
          Spacer(minLength: 8)

          Picker("", selection: $searchVisibility) {
            ForEach(SearchVisibility.allCases) { type in
              Text(type.description)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .fixedSize()
          .disabled(!showSearch)
          .controlSize(.small)
          .accessibilityLabel(Text("ShowSearchField", tableName: "AppearanceSettings"))

          Toggle(isOn: $showSearch) {
            Text("ShowSearchField", tableName: "AppearanceSettings")
          }
          .labelsHidden()
          .fixedSize()
        }
        Defaults.Toggle(key: .showTitle) {
          Text("ShowTitleBeforeSearchField", tableName: "AppearanceSettings")
        }
        Defaults.Toggle(key: .showApplicationIcons) {
          Text("ShowApplicationIcons", tableName: "AppearanceSettings")
        }
        Defaults.Toggle(key: .showHexColorSwatch) {
          Text("ShowHexColorSwatch", tableName: "AppearanceSettings")
        }
        .help(Text("ShowHexColorSwatchTooltip", tableName: "AppearanceSettings"))

        Defaults.Toggle(key: .showFooter) {
          Text("ShowFooter", tableName: "AppearanceSettings")
        }
        Picker(selection: $compactFooter) {
          Text("FooterStyleOriginal", tableName: "AppearanceSettings").tag(false)
          Text("FooterStyleModern", tableName: "AppearanceSettings").tag(true)
        } label: {
          Text("FooterStyle", tableName: "AppearanceSettings")
        }
        .accessibilityIdentifier("footer-style")
        .disabled(!showFooter)
        if !showFooter {
          Text("OpenPreferencesWarning", tableName: "AppearanceSettings")
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
      screens = NSScreen.screens
    }
  }

  @ViewBuilder
  private func screenPicker(for position: PopupPosition) -> some View {
    let screenBinding: Binding<Int> = Binding {
      return popupScreen
    } set: {
      popupScreen = $0
      popupAt = position
    }

    Picker(selection: screenBinding) {
      Text(labelForScreen(index: 0))
        .tag(0)

      ForEach(screens.indices, id: \.self) { index in
        Text(labelForScreen(index: index + 1))
          .tag(index + 1)
      }
    } label: {
      if popupAt == position {
        Text("\(position.description) (\(labelForScreen(index: popupScreen)))")
      } else {
        Text(position.description)
      }
    }
  }

  private func labelForScreen(index screenIndex: Int) -> String {
    switch screenIndex {
    case 0:
      return String(localized: "ActiveScreen", table: "AppearanceSettings")
    case _:
      return screens[screenIndex - 1].localizedName
    }
  }
}

#Preview {
  AppearanceSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
