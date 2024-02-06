import Cocoa
import Settings

// swiftlint:disable type_body_length
class AppearanceSettingsViewController: NSViewController, SettingsPane {
  let paneIdentifier = Settings.PaneIdentifier.appearance
  let paneTitle = NSLocalizedString("preferences_appearance", comment: "")
  let toolbarItemIcon = NSImage(named: .paintpalette)!

  override var nibName: NSNib.Name? { "AppearanceSettingsViewController" }

  @IBOutlet weak var popupAtButton: NSPopUpButton!
  @IBOutlet weak var popupAtMenuIconMenuItem: NSMenuItem!
  @IBOutlet weak var popupAtScreenCenterMenuItem: NSMenuItem!
  @IBOutlet weak var pinToButton: NSPopUpButton!
  @IBOutlet weak var imageHeightField: NSTextField!
  @IBOutlet weak var imageHeightStepper: NSStepper!
  @IBOutlet weak var numberOfItemsField: NSTextField!
  @IBOutlet weak var numberOfItemsStepper: NSStepper!
  @IBOutlet weak var titleLengthField: NSTextField!
  @IBOutlet weak var titleLengthStepper: NSStepper!
  @IBOutlet weak var previewDelayField: NSTextField!
  @IBOutlet weak var previewDelayStepper: NSStepper!
  @IBOutlet weak var showSpecialSymbolsButton: NSButton!
  @IBOutlet weak var showMenuIconButton: NSButton!
  @IBOutlet weak var changeMenuIcon: NSPopUpButton!
  @IBOutlet weak var showRecentCopyButton: NSButton!
  @IBOutlet weak var showSearchFieldButton: NSButton!
  @IBOutlet weak var showTitleButton: NSButton!
  @IBOutlet weak var showFooterButton: NSButton!
  @IBOutlet weak var highlightMatchesButton: NSPopUpButton!
  @IBOutlet weak var openPreferencesLabel: NSTextField!

  private let imageHeightMin = 1
  private let imageHeightMax = 200
  private var imageHeightFormatter: NumberFormatter!

  private let numberOfItemsMin = 0
  private let numberOfItemsMax = 100
  private var numberOfItemsFormatter: NumberFormatter!

  private let titleLengthMin = 30
  private let titleLengthMax = 200
  private var titleLengthFormatter: NumberFormatter!

  private let previewDelayMin = 200
  private let previewDelayMax = 100_000
  private var previewDelayFormatter: NumberFormatter!

  override func viewDidLoad() {
    super.viewDidLoad()
    setMinAndMaxImageHeight()
    setMinAndMaxNumberOfItems()
    setMinAndMaxTitleLength()
    setMinAndMaxPreviewDelay()
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    populateScreens()
    populatePopupPosition()
    populatePinTo()
    populateImageHeight()
    populateNumberOfItems()
    populateTitleLength()
    populatePreviewDelay()
    populateShowSpecialSymbols()
    populateShowMenuIcon()
    populateChangeMenuIcon()
    populateShowRecentCopy()
    populateShowSearchField()
    populateShowTitle()
    populateShowFooter()
    populateHighlightMatch()
  }

  @IBAction func popupAtCursorSelected(_ sender: NSMenuItem) {
    UserDefaults.standard.popupPosition = "cursor"
    showMenuIconButton.isEnabled = true
  }

  @IBAction func popupAtMenuIconSelected(_ sender: NSMenuItem) {
    UserDefaults.standard.popupPosition = "statusItem"
    showMenuIconButton.isEnabled = false
  }

  @IBAction func popupAtScreenCenterSelected(_ sender: NSMenuItem) {
    UserDefaults.standard.popupPosition = "center"
    UserDefaults.standard.popupScreen = 0
    showMenuIconButton.isEnabled = true
  }

  @IBAction func popupAtWindowSelected(_ sender: NSMenuItem) {
    UserDefaults.standard.popupPosition = "window"
    showMenuIconButton.isEnabled = true
  }

  @IBAction func selectScreen(_ sender: NSMenuItem) {
    UserDefaults.standard.popupPosition = "center"
    UserDefaults.standard.popupScreen = sender.tag

    populatePopupPosition()
  }

  private func updateScreensSelection() {
    guard let menu = popupAtScreenCenterMenuItem.submenu else {
      return
    }

    menu.items.forEach { $0.state = .off }
    menu.item(withTag: UserDefaults.standard.popupScreen)?.state = .on
  }

  @IBAction func pinToChanged(_ sender: NSPopUpButton) {
    switch sender.selectedTag() {
    case 1:
      UserDefaults.standard.pinTo = "bottom"
    default:
      UserDefaults.standard.pinTo = "top"
    }
  }

  @IBAction func imageHeightFieldChanged(_ sender: NSTextField) {
    UserDefaults.standard.imageMaxHeight = sender.integerValue
    imageHeightStepper.integerValue = sender.integerValue
  }

  @IBAction func imageHeightStepperChanged(_ sender: NSStepper) {
    UserDefaults.standard.imageMaxHeight = sender.integerValue
    imageHeightField.integerValue = sender.integerValue
  }

  @IBAction func numberOfItemsFieldChanged(_ sender: NSTextField) {
    UserDefaults.standard.maxMenuItems = sender.integerValue
    numberOfItemsStepper.integerValue = sender.integerValue
  }

  @IBAction func numberOfItemsStepperChanged(_ sender: NSStepper) {
    UserDefaults.standard.maxMenuItems = sender.integerValue
    numberOfItemsField.integerValue = sender.integerValue
  }

  @IBAction func titleLengthFieldChanged(_ sender: NSTextField) {
    UserDefaults.standard.maxMenuItemLength = sender.integerValue
    titleLengthStepper.integerValue = sender.integerValue
  }

  @IBAction func titleLengthStepperChanged(_ sender: NSStepper) {
    UserDefaults.standard.maxMenuItemLength = sender.integerValue
    titleLengthField.integerValue = sender.integerValue
  }

  @IBAction func previewDelayFieldChanged(_ sender: NSTextField) {
    UserDefaults.standard.previewDelay = sender.integerValue
    previewDelayStepper.integerValue = sender.integerValue
  }

  @IBAction func previewDelayStepperChanged(_ sender: NSStepper) {
    UserDefaults.standard.previewDelay = sender.integerValue
    previewDelayField.integerValue = sender.integerValue
  }

  @IBAction func showSpecialSymbolsChanged(_ sender: NSButton) {
    UserDefaults.standard.showSpecialSymbols = (sender.state == .on)
  }

  @IBAction func showMenuIconChanged(_ sender: NSButton) {
    UserDefaults.standard.showInStatusBar = (sender.state == .on)
    popupAtMenuIconMenuItem.isEnabled = (sender.state == .on)
    changeMenuIcon.isEnabled = (sender.state == .on)
  }

  @IBAction func showMenuIconChangedToDefault(_ sender: NSMenuItem) {
    UserDefaults.standard.menuIcon = "maccy"
  }

  @IBAction func showMenuIconChangedToClipboard(_ sender: NSMenuItem) {
    UserDefaults.standard.menuIcon = "clipboard"
  }

  @IBAction func showMenuIconChangedToScissors(_ sender: NSMenuItem) {
    UserDefaults.standard.menuIcon = "scissors"
  }

  @IBAction func showMenuIconChangedToPaperclip(_ sender: NSMenuItem) {
      UserDefaults.standard.menuIcon = "paperclip"
    }
  @IBAction func showRecentCopyChanged(_ sender: NSButton) {
    UserDefaults.standard.showRecentCopyInMenuBar = (sender.state == .on)
  }

  @IBAction func showSearchFieldChanged(_ sender: NSButton) {
    UserDefaults.standard.hideSearch = (sender.state == .off)
  }

  @IBAction func showTitleChanged(_ sender: NSButton) {
    UserDefaults.standard.hideTitle = (sender.state == .off)
  }

  @IBAction func showFooterChanged(_ sender: NSButton) {
    UserDefaults.standard.hideFooter = (sender.state == .off)
    openPreferencesLabel.isHidden = (sender.state == .on)
  }

  @IBAction func highlightMatchesChanged(_ sender: NSPopUpButton) {
    switch sender.selectedTag() {
    case 1:
      UserDefaults.standard.highlightMatches = "italic"
    case 2:
      UserDefaults.standard.highlightMatches = "underline"
    default:
      UserDefaults.standard.highlightMatches = "bold"
    }
  }

  private func populateScreens() {
    guard NSScreen.screens.count > 1 else {
      popupAtScreenCenterMenuItem.submenu = nil
      popupAtScreenCenterMenuItem.action = #selector(popupAtScreenCenterSelected)
      return
    }

    let screensMenu = NSMenu(title: "Screens")
    popupAtScreenCenterMenuItem.submenu = screensMenu
    popupAtScreenCenterMenuItem.action = nil

    let activeScreenMenuItem = NSMenuItem(
      title: NSLocalizedString("active_screen", comment: ""),
      action: #selector(selectScreen),
      keyEquivalent: ""
    )
    activeScreenMenuItem.tag = 0
    screensMenu.addItem(activeScreenMenuItem)

    for (index, screen) in NSScreen.screens.enumerated() {
      var name = "\(NSLocalizedString("screen", comment: "")) \(index + 1)"
      if #available(macOS 10.15, *) {
        name += " (\(screen.localizedName))"
      }

      let item = NSMenuItem(title: name, action: #selector(selectScreen), keyEquivalent: "")
      item.tag = index + 1
      screensMenu.addItem(item)
    }
  }

  private func populatePopupPosition() {
    switch UserDefaults.standard.popupPosition {
    case "window":
      popupAtButton.selectItem(withTag: 3)
    case "center":
      popupAtButton.selectItem(withTag: 2)
      updateScreensSelection()
    case "statusItem":
      popupAtButton.selectItem(withTag: 1)
      showMenuIconButton.isEnabled = false
    default:
      popupAtButton.selectItem(withTag: 0)
    }
  }

  private func populatePinTo() {
    switch UserDefaults.standard.pinTo {
    case "bottom":
      pinToButton.selectItem(withTag: 1)
    default:
      pinToButton.selectItem(withTag: 0)
    }
  }

  private func setMinAndMaxImageHeight() {
    imageHeightFormatter = NumberFormatter()
    imageHeightFormatter.minimum = imageHeightMin as NSNumber
    imageHeightFormatter.maximum = imageHeightMax as NSNumber
    imageHeightFormatter.maximumFractionDigits = 0
    imageHeightField.formatter = imageHeightFormatter
    imageHeightStepper.minValue = Double(imageHeightMin)
    imageHeightStepper.maxValue = Double(imageHeightMax)
  }

  private func setMinAndMaxNumberOfItems() {
    numberOfItemsFormatter = NumberFormatter()
    numberOfItemsFormatter.minimum = numberOfItemsMin as NSNumber
    numberOfItemsFormatter.maximum = numberOfItemsMax as NSNumber
    numberOfItemsFormatter.maximumFractionDigits = 0
    numberOfItemsField.formatter = numberOfItemsFormatter
    numberOfItemsStepper.minValue = Double(numberOfItemsMin)
    numberOfItemsStepper.maxValue = Double(numberOfItemsMax)
  }

  private func populateImageHeight() {
    imageHeightField.integerValue =  UserDefaults.standard.imageMaxHeight
    imageHeightStepper.integerValue =  UserDefaults.standard.imageMaxHeight
  }

  private func populateNumberOfItems() {
    numberOfItemsField.integerValue = UserDefaults.standard.maxMenuItems
    numberOfItemsStepper.integerValue = UserDefaults.standard.maxMenuItems
  }

  private func setMinAndMaxTitleLength() {
    titleLengthFormatter = NumberFormatter()
    titleLengthFormatter.minimum = titleLengthMin as NSNumber
    titleLengthFormatter.maximum = titleLengthMax as NSNumber
    titleLengthFormatter.maximumFractionDigits = 0
    titleLengthField.formatter = titleLengthFormatter
    titleLengthStepper.minValue = Double(titleLengthMin)
    titleLengthStepper.maxValue = Double(titleLengthMax)
  }

  private func populateTitleLength() {
    titleLengthField.integerValue = UserDefaults.standard.maxMenuItemLength
    titleLengthStepper.integerValue = UserDefaults.standard.maxMenuItemLength
  }

  private func setMinAndMaxPreviewDelay() {
    previewDelayFormatter = NumberFormatter()
    previewDelayFormatter.minimum = previewDelayMin as NSNumber
    previewDelayFormatter.maximum = previewDelayMax as NSNumber
    previewDelayFormatter.maximumFractionDigits = 0
    previewDelayField.formatter = previewDelayFormatter
    previewDelayStepper.minValue = Double(previewDelayMin)
    previewDelayStepper.maxValue = Double(previewDelayMax)
  }

  private func populatePreviewDelay() {
    previewDelayField.integerValue = UserDefaults.standard.previewDelay
    previewDelayStepper.integerValue = UserDefaults.standard.previewDelay
  }

  private func populateShowSpecialSymbols() {
    showSpecialSymbolsButton.state = UserDefaults.standard.showSpecialSymbols ? .on : .off
  }

  private func populateShowMenuIcon() {
    showMenuIconButton.state = UserDefaults.standard.showInStatusBar ? .on : .off
    popupAtMenuIconMenuItem.isEnabled = UserDefaults.standard.showInStatusBar
  }

  private func populateChangeMenuIcon() {
    changeMenuIcon.isEnabled = UserDefaults.standard.showInStatusBar
    switch UserDefaults.standard.menuIcon {
    case "clipboard":
      changeMenuIcon.selectItem(withTag: 1)
    case "scissors":
      changeMenuIcon.selectItem(withTag: 2)
    case "paperclip":
      changeMenuIcon.selectItem(withTag: 3)
    default:
      changeMenuIcon.selectItem(withTag: 0)
    }
  }

  private func populateShowRecentCopy() {
    showRecentCopyButton.state = UserDefaults.standard.showRecentCopyInMenuBar ? .on : .off
  }

  private func populateShowSearchField() {
    showSearchFieldButton.state = UserDefaults.standard.hideSearch ? .off : .on
  }

  private func populateShowTitle() {
    showTitleButton.state = UserDefaults.standard.hideTitle ? .off : .on
  }

  private func populateShowFooter() {
    showFooterButton.state = UserDefaults.standard.hideFooter ? .off : .on
    openPreferencesLabel.isHidden = !UserDefaults.standard.hideFooter
  }

  private func populateHighlightMatch() {
    switch UserDefaults.standard.highlightMatches {
    case "italic":
      highlightMatchesButton.selectItem(withTag: 1)
    case "underline":
      highlightMatchesButton.selectItem(withTag: 2)
    default:
      highlightMatchesButton.selectItem(withTag: 0)
    }
  }
}
// swiftlint:enable type_body_length
