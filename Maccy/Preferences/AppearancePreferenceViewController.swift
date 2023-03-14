import Cocoa
import Preferences

class AppearancePreferenceViewController: NSViewController, PreferencePane {
  let preferencePaneIdentifier = Preferences.PaneIdentifier.appearance
  let preferencePaneTitle = NSLocalizedString("preferences_appearance", comment: "")
  let toolbarItemIcon = NSImage(named: .paintpalette)!

  override var nibName: NSNib.Name? { "AppearancePreferenceViewController" }

  @IBOutlet weak var popupAtButton: NSPopUpButton!
  @IBOutlet weak var popupAtMenuIconMenuItem: NSMenuItem!
  @IBOutlet weak var popupAtScreenCenterMenuItem: NSMenuItem!
  @IBOutlet weak var pinToButton: NSPopUpButton!
  @IBOutlet weak var imageHeightSlider: NSSlider!
  @IBOutlet weak var imageHeightLabel: NSTextField!
  @IBOutlet weak var menuSizeSlider: NSSlider!
  @IBOutlet weak var menuSizeLabel: NSTextField!
  @IBOutlet weak var titleLengthSlider: NSSlider!
  @IBOutlet weak var titleLengthLabel: NSTextField!
  @IBOutlet weak var previewDelayField: NSTextField!
  @IBOutlet weak var previewDelayStepper: NSStepper!
  @IBOutlet weak var showMenuIconButton: NSButton!
  @IBOutlet weak var changeMenuIcon: NSPopUpButton!
  @IBOutlet weak var showRecentCopyButton: NSButton!
  @IBOutlet weak var showSearchFieldButton: NSButton!
  @IBOutlet weak var showTitleButton: NSButton!
  @IBOutlet weak var showFooterButton: NSButton!

  private let previewDelayMin = 200
  private let previewDelayMax = 100_000

  private var previewDelayFormatter: NumberFormatter!

  override func viewDidLoad() {
    super.viewDidLoad()
    setMinAndMaxPreviewDelay()
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    populateScreens()
    populatePopupPosition()
    populatePinTo()
    populateImageHeight()
    populateMenuSize()
    populateTitleLength()
    populatePreviewDelay()
    populateShowMenuIcon()
    populateChangeMenuIcon()
    populateShowRecentCopy()
    populateShowSearchField()
    populateShowTitle()
    populateShowFooter()
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

  @IBAction func imageHeightChanged(_ sender: NSSlider) {
    let old = String(UserDefaults.standard.imageMaxHeight)
    let new = String(imageHeightSlider.integerValue)
    updateLabel(old: old, new: new, label: imageHeightLabel)
    UserDefaults.standard.imageMaxHeight = sender.integerValue
  }

  @IBAction func menuSizeChanged(_ sender: NSSlider) {
    let old = String(UserDefaults.standard.maxMenuItems)
    let new = String(menuSizeSlider.integerValue)
    updateLabel(old: old, new: new, label: menuSizeLabel)
    UserDefaults.standard.maxMenuItems = sender.integerValue
  }

  @IBAction func titleLengthChanged(_ sender: NSSlider) {
    let old = String(UserDefaults.standard.maxMenuItemLength)
    let new = String(titleLengthSlider.integerValue)
    updateLabel(old: old, new: new, label: titleLengthLabel)
    UserDefaults.standard.maxMenuItemLength = sender.integerValue
  }

  @IBAction func previewDelayFieldChanged(_ sender: NSTextField) {
    UserDefaults.standard.previewDelay = sender.integerValue
    previewDelayStepper.integerValue = sender.integerValue
  }

  @IBAction func previewDelayStepperChanged(_ sender: NSStepper) {
    UserDefaults.standard.previewDelay = sender.integerValue
    previewDelayField.integerValue = sender.integerValue
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

  private func populateImageHeight() {
    imageHeightSlider.integerValue = UserDefaults.standard.imageMaxHeight
    let new = String(imageHeightSlider.integerValue)
    updateLabel(old: "{imageHeight}", new: new, label: imageHeightLabel)
  }

  private func populateMenuSize() {
    menuSizeSlider.integerValue = UserDefaults.standard.maxMenuItems
    let new = String(menuSizeSlider.integerValue)
    updateLabel(old: "{menuSize}", new: new, label: menuSizeLabel)
  }

  private func updateLabel(old: String, new: String, label: NSTextField) {
    let newLabelValue = label.stringValue.replacingOccurrences(
      of: old,
      with: new,
      options: [],
      range: label.stringValue.range(of: old)
    )
    label.stringValue = newLabelValue
  }

  private func populateTitleLength() {
    titleLengthSlider.integerValue = UserDefaults.standard.maxMenuItemLength
    let new = String(titleLengthSlider.integerValue)
    updateLabel(old: "{maxMenuItemLength}", new: new, label: titleLengthLabel)
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
  }
}
