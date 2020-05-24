import Cocoa

/**
A window that allows you to disable all user interactions via `isUserInteractionEnabled`.

Used to avoid breaking animations when the user clicks too fast. Disable user interactions during animations and you're set.
*/
class UserInteractionPausableWindow: NSWindow {
	var isUserInteractionEnabled = true

	override func sendEvent(_ event: NSEvent) {
		guard isUserInteractionEnabled || !event.isUserInteraction else {
			return
		}

		super.sendEvent(event)
	}

	override func responds(to selector: Selector!) -> Bool {
		// Deactivate toolbar interactions from the Main Menu.
		if selector == #selector(NSWindow.toggleToolbarShown(_:)) {
			return false
		}

		return super.responds(to: selector)
	}
}
