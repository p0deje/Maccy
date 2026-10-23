import Cocoa

class About {
  private let familyCredits = NSAttributedString(
    string: "Special thank you to Tonia, Anna & Guy! ❤️",
    attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor]
  )

  private var kossCredits: NSMutableAttributedString {
    let string = NSMutableAttributedString(string: "Kudos to Sasha Koss for help! 🏂",
                                           attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    string.addAttribute(.link, value: "https://koss.nocorp.me", range: NSRange(location: 9, length: 10))
    return string
  }

  private var links: NSMutableAttributedString {
    let string = NSMutableAttributedString(string: "Website│GitHub│Support",
                                           attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    string.addAttribute(.link, value: "https://maccy.app", range: NSRange(location: 0, length: 7))
    string.addAttribute(.link, value: "https://github.com/p0deje/Maccy", range: NSRange(location: 8, length: 6))
    string.addAttribute(.link, value: "mailto:support@maccy.app", range: NSRange(location: 15, length: 7))
    return string
  }

  var credits: NSMutableAttributedString {
    let credits = NSMutableAttributedString(string: "",
                                            attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    credits.append(links)
    credits.append(NSAttributedString(string: "\n\n"))
    credits.append(acknowledgements)
    credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
    return credits
  }

  var acknowledgements: NSAttributedString {
    let text = NSMutableAttributedString(attributedString: kossCredits)
    text.append(NSAttributedString(string: "\n"))
    text.append(familyCredits)
    return text
  }

  @objc
  func openAbout(_ sender: NSMenuItem?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey.credits: credits])
  }
}
