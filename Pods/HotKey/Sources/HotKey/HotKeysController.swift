import Carbon

final class HotKeysController {

	// MARK: - Types

	final class HotKeyBox {
		let identifier: UUID
		weak var hotKey: HotKey?
		let carbonHotKeyID: UInt32
		var carbonEventHotKey: EventHotKeyRef?

		init(hotKey: HotKey, carbonHotKeyID: UInt32) {
			self.identifier = hotKey.identifier
			self.hotKey = hotKey
			self.carbonHotKeyID = carbonHotKeyID
		}
	}

	// MARK: - Properties

	static var hotKeys = [UInt32: HotKeyBox]()
	static private var hotKeysCount: UInt32 = 0

	static let eventHotKeySignature: UInt32 = {
		let string = "SSHk"
		var result: FourCharCode = 0
		for char in string.utf16 {
			result = (result << 8) + FourCharCode(char)
		}
		return result
	}()

	private static let eventSpec = [
		EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
		EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
	]

	private static var eventHandler: EventHandlerRef?

	// MARK: - Registration

	static func register(_ hotKey: HotKey) {
        // Don't register an already registered HotKey
        if hotKeys.values.first(where: { $0.identifier == hotKey.identifier }) != nil {
            return
        }

		// Increment the count which will become out next ID
		hotKeysCount += 1

		// Create a box for our metadata and weak HotKey
		let box = HotKeyBox(hotKey: hotKey, carbonHotKeyID: hotKeysCount)
		hotKeys[box.carbonHotKeyID] = box

		// Register with the system
		var eventHotKey: EventHotKeyRef?
		let hotKeyID = EventHotKeyID(signature: eventHotKeySignature, id: box.carbonHotKeyID)
		let registerError = RegisterEventHotKey(
			hotKey.keyCombo.carbonKeyCode,
			hotKey.keyCombo.carbonModifiers,
			hotKeyID,
			GetEventDispatcherTarget(),
			0,
			&eventHotKey
		)

		// Ensure registration worked
		guard registerError == noErr, eventHotKey != nil else {
			return
		}

		// Store the event so we can unregister it later
		box.carbonEventHotKey = eventHotKey

		// Setup the event handler if needed
		updateEventHandler()
	}

	static func unregister(_ hotKey: HotKey) {
		// Find the box
		guard let box = self.box(for: hotKey) else {
			return
		}

		// Unregister the hot key
		UnregisterEventHotKey(box.carbonEventHotKey)

		// Destroy the box
		box.hotKey = nil
		hotKeys.removeValue(forKey: box.carbonHotKeyID)
	}


	// MARK: - Events

	static func handleCarbonEvent(_ event: EventRef?) -> OSStatus {
		// Ensure we have an event
		guard let event = event else {
			return OSStatus(eventNotHandledErr)
		}

		// Get the hot key ID from the event
		var hotKeyID = EventHotKeyID()
		let error = GetEventParameter(
			event,
			UInt32(kEventParamDirectObject),
			UInt32(typeEventHotKeyID),
			nil,
			MemoryLayout<EventHotKeyID>.size,
			nil,
			&hotKeyID
		)

		if error != noErr {
			return error
		}

		// Ensure we have a HotKey registered for this ID
		guard hotKeyID.signature == eventHotKeySignature,
			let hotKey = self.hotKey(for: hotKeyID.id)
		else {
			return OSStatus(eventNotHandledErr)
		}

		// Call the handler
		switch GetEventKind(event) {
		case UInt32(kEventHotKeyPressed):
			if !hotKey.isPaused, let handler = hotKey.keyDownHandler {
				handler()
				return noErr
			}
		case UInt32(kEventHotKeyReleased):
			if !hotKey.isPaused, let handler = hotKey.keyUpHandler {
				handler()
				return noErr
			}
		default:
			break
		}

		return OSStatus(eventNotHandledErr)
	}

	private static func updateEventHandler() {
		if hotKeysCount == 0 || eventHandler != nil {
			return
		}

		// Register for key down and key up
		let eventSpec = [
			EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
			EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
		]

		// Install the handler
		InstallEventHandler(GetEventDispatcherTarget(), hotKeyEventHandler, 2, eventSpec, nil, &eventHandler)
	}


	// MARK: - Querying

	private static func hotKey(for carbonHotKeyID: UInt32) -> HotKey? {
		if let hotKey = hotKeys[carbonHotKeyID]?.hotKey {
			return hotKey
		}

		hotKeys.removeValue(forKey: carbonHotKeyID)
		return nil
	}

	private static func box(for hotKey: HotKey) -> HotKeyBox? {
		for box in hotKeys.values {
			if box.identifier == hotKey.identifier {
				return box
			}
		}

		return nil
	}
}

private func hotKeyEventHandler(eventHandlerCall: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
	return HotKeysController.handleCarbonEvent(event)
}
