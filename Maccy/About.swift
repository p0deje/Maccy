import Cocoa

class About {
  private let defaultCreditsAttributes = [NSAttributedString.Key.foregroundColor: NSColor.labelColor]
  private let familyCreditsText = "Special thank you to Tonia & Guy! ❤️"

  @objc
  func openAbout(_ sender: NSMenuItem) {
    NSApp.activate(ignoringOtherApps: true)

    let credits = NSMutableAttributedString()
    credits.append(NSAttributedString(string: familyCreditsText, attributes: defaultCreditsAttributes))

    NSApp.orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey.credits: credits])
  }
}
