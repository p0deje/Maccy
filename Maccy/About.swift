import Cocoa

class About {
  private let defaultCreditsAttributes = [NSAttributedString.Key.foregroundColor: NSColor.labelColor]
  private let iconCreditsText = "Icon made by Google from www.flaticon.com.\n"
  private let familyCreditsText = "Special thank you to Tonia & Guy! ❤️"
  private let flatIconUrl = "http://www.flaticon.com"
  private let flatIconGoogleUrl = "http://www.flaticon.com/authors/google"

  @objc
  func openAbout(_ sender: NSMenuItem) {
    NSApp.activate(ignoringOtherApps: true)

    let iconCredits = NSMutableAttributedString(string: iconCreditsText, attributes: defaultCreditsAttributes)
    iconCredits.addAttribute(.link, value: flatIconGoogleUrl, range: NSRange(location: 13, length: 6))
    iconCredits.addAttribute(.link, value: flatIconUrl, range: NSRange(location: 25, length: 16))

    let credits = NSMutableAttributedString(attributedString: iconCredits)
    credits.append(NSAttributedString(string: familyCreditsText, attributes: defaultCreditsAttributes))

    NSApp.orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey.credits: credits])
  }
}
