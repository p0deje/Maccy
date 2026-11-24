import AppKit
import Defaults
import SwiftUI

// The settings window owns its view hierarchy so reopening it preserves the selected page.
@MainActor
final class MaccySettingsWindowController: NSWindowController {
  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 730),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Maccy"
    window.minSize = NSSize(width: 740, height: 540)
    window.isReleasedWhenClosed = false
    let hostingView = NSHostingView(rootView: MaccySettingsView())
    // Lists must fill the window rather than resize it to their ideal size.
    hostingView.sizingOptions = []
    window.contentView = hostingView
    super.init(window: window)
    window.setContentSize(NSSize(width: 900, height: 730))
    window.center()
    window.setFrameAutosaveName("MaccyModernSettings")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func show() {
    NSApp.activate()
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
  case general, storage, appearance, ignore, advanced, about

  var id: Self { self }

  var title: String {
    let table: String = switch self {
    case .general: "GeneralSettings"
    case .storage: "StorageSettings"
    case .appearance: "AppearanceSettings"
    case .ignore: "IgnoreSettings"
    case .advanced: "AdvancedSettings"
    case .about: "Localizable"
    }
    return NSLocalizedString(self == .about ? "AboutSettingsTitle" : "Title", tableName: table, comment: "")
  }

  var symbol: String {
    switch self {
    case .general: "gearshape"
    case .storage: "archivebox"
    case .appearance: "paintbrush"
    case .ignore: "hand.raised"
    case .advanced: "slider.horizontal.3"
    case .about: "info.circle"
    }
  }

  var color: Color {
    switch self {
    case .general, .advanced, .about: .gray
    case .storage: .orange
    case .appearance: .blue
    case .ignore: .purple
    }
  }
}

private struct MaccySettingsView: View {
  @State private var selection: SettingsPage? = .general
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  var body: some View {
    GeometryReader { geometry in
      settingsContent
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }

  private var settingsContent: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List(selection: $selection) {
        SwiftUI.Section {
          ForEach(SettingsPage.allCases.filter { $0 != .about }) { page in
            navigationRow(page)
          }
        }
        SwiftUI.Section {
          navigationRow(.about)
        }
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      Group {
        switch selection ?? .general {
        case .general: GeneralSettingsPane()
        case .storage: StorageSettingsPane()
        case .appearance: AppearanceSettingsPane()
        case .ignore: IgnoreSettingsPane()
        case .advanced: AdvancedSettingsPane()
        case .about: AboutSettingsPane()
        }
      }
      .id(selection ?? .general)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationSplitViewStyle(.balanced)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button {
          withAnimation {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
          }
        } label: {
          Label {
            Text("ToggleSidebar", tableName: "AppearanceSettings")
          } icon: {
            Image(systemName: "sidebar.left")
          }
        }
        .help(Text("ToggleSidebar", tableName: "AppearanceSettings"))
        .accessibilityIdentifier("settings-toggle-sidebar")
      }
    }
  }

  private func navigationRow(_ page: SettingsPage) -> some View {
    NavigationLink(value: page) {
      Label {
        Text(page.title)
          .frame(maxWidth: .infinity, alignment: .leading)
      } icon: {
        Image(systemName: page.symbol)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.white)
          .frame(width: 25, height: 25)
          .background(page.color, in: RoundedRectangle(cornerRadius: 6))
      }
      .padding(.vertical, 4)
      .contentShape(Rectangle())
    }
    .accessibilityIdentifier("settings-\(page.rawValue)")
  }
}

private struct AboutSettingsPane: View {
  private var credits: AttributedString {
    let original = About().acknowledgements
    var result = AttributedString()
    original.enumerateAttributes(in: NSRange(location: 0, length: original.length)) { attributes, range, _ in
      var run = AttributedString((original.string as NSString).substring(with: range))
      if let url = attributes[.link] as? URL {
        run.link = url
      } else if let address = attributes[.link] as? String {
        run.link = URL(string: address)
      }
      if run.link != nil {
        run.foregroundColor = Color(nsColor: .linkColor)
      }
      result.append(run)
    }
    return result
  }

  private var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? "—"
    guard let build = info["CFBundleVersion"] as? String else { return version }
    return "\(version) (\(build))"
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        VStack(spacing: 10) {
          Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .scaledToFit()
            .frame(width: 80, height: 80)
            .accessibilityHidden(true)
            .padding(.bottom, 8)
          Text("Maccy")
            .font(.title2.weight(.semibold))
          Text(String(format: NSLocalizedString("AboutVersion", comment: ""), version))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("settings-about-version")
          if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String {
            Text(copyright)
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 24)

        VStack(spacing: 0) {
          linkRow("AboutWebsite", subtitle: "maccy.app", symbol: "globe", destination: "https://maccy.app")
          Divider().padding(.leading, 52)
          linkRow("GitHub", subtitle: "p0deje/Maccy", symbol: "chevron.left.forwardslash.chevron.right",
                  destination: "https://github.com/p0deje/Maccy")
          Divider().padding(.leading, 52)
          linkRow("AboutSupport", subtitle: "support@maccy.app", symbol: "envelope",
                  destination: "mailto:support@maccy.app")
        }
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

        VStack(spacing: 0) {
          linkRow("AboutReportIssue", symbol: "bubble.left.and.bubble.right",
                  destination: "https://github.com/p0deje/Maccy/issues")
          Divider().padding(.leading, 52)
          linkRow("AboutLicense", symbol: "doc.text",
                  destination: "https://github.com/p0deje/Maccy/blob/master/LICENSE")
        }
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

        VStack(spacing: 10) {
          Text("AboutCredits")
            .font(.callout.weight(.semibold))
          Text(credits)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      }
      .frame(maxWidth: 560)
      .frame(maxWidth: .infinity)
      .padding(24)
    }
    .accessibilityIdentifier("settings-about-content")
  }

  private func linkRow(
    _ title: LocalizedStringKey,
    subtitle: String? = nil,
    symbol: String,
    destination: String
  ) -> some View {
    Link(destination: URL(string: destination)!) {
      HStack(spacing: 14) {
        Image(systemName: symbol)
          .font(.system(size: 20))
          .foregroundStyle(Color(nsColor: .linkColor))
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
          if let subtitle {
            Text(verbatim: subtitle)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(16)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}

// Keep the existing pane content and bindings while replacing the old fixed-width grid.
enum ModernSettings {
  @resultBuilder
  enum SectionBuilder {
    static func buildBlock(_ sections: Section...) -> [Section] { sections }
  }

  struct Container: View {
    let sections: [Section]

    init(@SectionBuilder content: () -> [Section]) {
      sections = content()
    }

    var body: some View {
      Form {
        ForEach(sections.indices, id: \.self) { index in
          sections[index]
        }
      }
      .formStyle(.grouped)
      .toggleStyle(.switch)
    }
  }

  struct Section: View {
    private let label: AnyView?
    private let content: AnyView

    init(
      label: () -> some View,
      @ViewBuilder content: () -> some View
    ) {
      self.label = AnyView(label())
      self.content = AnyView(content())
    }

    init(title: String, @ViewBuilder content: () -> some View) {
      label = title.isEmpty ? nil : AnyView(Text(title))
      self.content = AnyView(content())
    }

    var body: some View {
      SwiftUI.Section {
        if let label {
          HStack(alignment: .firstTextBaseline, spacing: 20) {
            label
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 12) {
              content
            }
          }
        } else {
          content
        }
      }
    }
  }
}

struct SettingsAppearancePreview: View {
  @Default(.compactFooter) private var compactFooter
  @Default(.showFooter) private var showFooter
  @Default(.showSearch) private var showSearch
  @Default(.showTitle) private var showTitle
  @Default(.showApplicationIcons) private var showIcons

  private let examples = ["PreviewExampleNote", "PreviewExampleURL", "PreviewExampleText"]

  var body: some View {
    VStack(spacing: 12) {
      Text("Preview", tableName: "AppearanceSettings")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      VStack(spacing: 4) {
        if showSearch {
          HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
            if showTitle { Text("Maccy") }
            Text("PreviewSearch", tableName: "AppearanceSettings")
            Spacer(minLength: 0)
          }
          .foregroundStyle(.secondary)
          .padding(7)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }
        ForEach(examples.indices, id: \.self) { index in
          HStack {
            if showIcons { Image(systemName: index == 1 ? "link" : "doc.text") }
            Text(LocalizedStringKey(examples[index]), tableName: "AppearanceSettings")
            Spacer(minLength: 0)
            Text("⌘\(index + 1)").foregroundStyle(.secondary)
          }
          .padding(6)
        }
        if showFooter {
          Divider()
          if compactFooter {
            HStack(spacing: 20) {
              Image(systemName: "trash")
              Image(systemName: "gearshape")
              Image(systemName: "info.circle")
              Image(systemName: "power").foregroundStyle(.red)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 7)
            .background(.quaternary, in: Capsule())
          } else {
            ForEach(["clear", "preferences", "about", "quit"], id: \.self) { key in
              Text(LocalizedStringKey(key))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
            }
          }
        }
      }
      .font(.system(size: 12))
      .padding(8)
      .frame(maxWidth: 320)
      .background(.background, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
      .frame(maxWidth: .infinity)
      Text("PreviewSampleContent", tableName: "AppearanceSettings")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }
}
