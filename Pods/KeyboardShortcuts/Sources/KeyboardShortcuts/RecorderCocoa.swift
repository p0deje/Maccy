import Cocoa
import Carbon.HIToolbox

extension KeyboardShortcuts {
	/**
	A `NSView` that lets the user record a keyboard shortcut.

	You would usually put this in your preferences window.

	It automatically prevents choosing a keyboard shortcut that is already taken by the system or by the app's main menu by showing a user-friendly alert to the user.

	It takes care of storing the keyboard shortcut in `UserDefaults` for you.

	```
	import Cocoa
	import KeyboardShortcuts

	final class PreferencesViewController: NSViewController {
		override func loadView() {
			view = NSView()

			let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleUnicornMode)
			view.addSubview(recorder)
		}
	}
	```
	*/
	public final class RecorderCocoa: NSSearchField, NSSearchFieldDelegate {
		private let minimumWidth: Double = 130
		private var eventMonitor: LocalEventMonitor?
		private let shortcutName: Name
		private let onChange: ((_ shortcut: Shortcut?) -> Void)?

		/// :nodoc:
		override public var canBecomeKeyView: Bool { false }

		/// :nodoc:
		override public var intrinsicContentSize: CGSize {
			var size = super.intrinsicContentSize
			size.width = CGFloat(minimumWidth)
			return size
		}

		private var cancelButton: NSButtonCell?

		private var showsCancelButton: Bool {
			get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
			set {
				(cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButton : nil
			}
		}

		/**
		- Parameter name: Strongly-typed keyboard shortcut name.
		- Parameter onChange: Callback which will be called when the keyboard shortcut is changed/removed by the user. This can be useful when you need more control. For example, when migrating from a different keyboard shortcut solution and you need to store the keyboard shortcut somewhere yourself instead of relying on the built-in storage. However, it's strongly recommended to just rely on the built-in storage when possible.
		*/
		public required init(
			for name: Name,
			onChange: ((_ shortcut: Shortcut?) -> Void)? = nil
		) {
			self.shortcutName = name
			self.onChange = onChange

			super.init(frame: .zero)
			self.delegate = self
			self.placeholderString = "Record Shortcut"
			self.centersPlaceholder = true
			self.alignment = .center
			(self.cell as? NSSearchFieldCell)?.searchButtonCell = nil

			if let shortcut = userDefaultsGet(name: shortcutName) {
				self.stringValue = "\(shortcut)"
			}

			self.wantsLayer = true
			self.translatesAutoresizingMaskIntoConstraints = false
			self.setContentHuggingPriority(.defaultHigh, for: .vertical)
			self.setContentHuggingPriority(.defaultHigh, for: .horizontal)
			self.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(minimumWidth)).isActive = true

			// Hide the cancel button when not showing the shortcut so the placeholder text is properly centered. Must be last.
			self.cancelButton = (self.cell as? NSSearchFieldCell)?.cancelButtonCell
			self.showsCancelButton = !stringValue.isEmpty
		}

		@available(*, unavailable)
		public required init?(coder: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		/// :nodoc:
		public func controlTextDidChange(_ object: Notification) {
			if stringValue.isEmpty {
				saveShortcut(nil)
			}

			showsCancelButton = !stringValue.isEmpty

			if stringValue.isEmpty {
				// Hack to ensure that the placeholder centers after the above `showsCancelButton` setter.
				focus()
			}
		}

		/// :nodoc:
		public func controlTextDidEndEditing(_ object: Notification) {
			eventMonitor = nil
			placeholderString = "Record Shortcut"
			showsCancelButton = !stringValue.isEmpty
		}

		/// :nodoc:
		override public func becomeFirstResponder() -> Bool {
			let shouldBecomeFirstResponder = super.becomeFirstResponder()

			guard shouldBecomeFirstResponder else {
				return shouldBecomeFirstResponder
			}

			placeholderString = "Press Shortcut"
			showsCancelButton = !stringValue.isEmpty
			hideCaret()

			eventMonitor = LocalEventMonitor(events: [.keyDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
				guard let self = self else {
					return nil
				}

				let clickPoint = self.convert(event.locationInWindow, from: nil)
				let clickMargin: CGFloat = 3

				if
					event.type == .leftMouseUp || event.type == .rightMouseUp,
					!self.frame.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint)
				{
					self.blur()
					return nil
				}

				guard event.isKeyEvent else {
					return nil
				}

				if
					event.modifiers.isEmpty,
					event.specialKey == .tab
				{
					self.blur()

					// We intentionally bubble up the event so it can focus the next responder.
					return event
				}

				if
					event.modifiers.isEmpty,
					event.keyCode == kVK_Escape // TODO: Make this strongly typed.
				{
					self.blur()
					return nil
				}

				if
					event.modifiers.isEmpty,
					event.specialKey == .delete
						|| event.specialKey == .deleteForward
						|| event.specialKey == .backspace
				{
					self.clear()
					return nil
				}

				guard
					!event.modifiers.isEmpty
						|| event.specialKey?.isFunctionKey == true,
					let shortcut = Shortcut(event: event)
				else {
					NSSound.beep()
					return nil
				}

				if let menuItem = shortcut.takenByMainMenu {
					// TODO: Find a better way to make it possible to dismiss the alert by pressing "Enter". How can we make the input automatically temporarily lose focus while the alert is open?
					self.blur()

					NSAlert.showModal(
						for: self.window,
						message: "This keyboard shortcut cannot be used as it's already used by the “\(menuItem.title)” menu item."
					)

					self.focus()

					return nil
				}

				guard !shortcut.isTakenBySystem else {
					self.blur()

					NSAlert.showModal(
						for: self.window,
						message: "This keyboard shortcut cannot be used as it's already a system-wide keyboard shortcut.",
						// TODO: Add button to offer to open the relevant system preference pane for the user.
						informativeText: "Most system-wide keyboard shortcuts can be changed in “System Preferences › Keyboard › Shortcuts“."
					)

					self.focus()

					return nil
				}

				self.stringValue = "\(shortcut)"
				self.showsCancelButton = true

				self.saveShortcut(shortcut)
				self.blur()

				return nil
			}.start()

			return shouldBecomeFirstResponder
		}

		private func saveShortcut(_ shortcut: Shortcut?) {
			if let shortcut = shortcut {
				userDefaultsSet(name: shortcutName, shortcut: shortcut)
			} else {
				userDefaultsRemove(name: shortcutName)
			}

			onChange?(shortcut)
		}
	}
}
