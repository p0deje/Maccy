import Cocoa

protocol PreferencesStyleController: AnyObject {
	var delegate: PreferencesStyleControllerDelegate? { get set }
	var isKeepingWindowCentered: Bool { get }

	func toolbarItemIdentifiers() -> [NSToolbarItem.Identifier]
	func toolbarItem(preferenceIdentifier: PreferencePane.Identifier) -> NSToolbarItem?
	func selectTab(index: Int)
}

protocol PreferencesStyleControllerDelegate: AnyObject {
	func activateTab(preferenceIdentifier: PreferencePane.Identifier, animated: Bool)
	func activateTab(index: Int, animated: Bool)
}
