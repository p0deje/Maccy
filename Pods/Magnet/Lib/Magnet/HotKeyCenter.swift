//
//  HotKeyCenter.swift
//
//  Magnet
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

import Cocoa
import Carbon

public final class HotKeyCenter {

    // MARK: - Properties
    public static let shared = HotKeyCenter()

    private var hotKeys = [String: HotKey]()
    private var hotKeyCount: UInt32 = 0
    private let modifierEventHandler: ModifierEventHandler
    private let notificationCenter: NotificationCenter

    // MARK: - Initialize
    init(modifierEventHandler: ModifierEventHandler = .init(), notificationCenter: NotificationCenter = .default) {
        self.modifierEventHandler = modifierEventHandler
        self.notificationCenter = notificationCenter
        installHotKeyPressedEventHandler()
        installModifiersChangedEventHandlerIfNeeded()
        observeApplicationTerminate()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

}

// MARK: - Register & Unregister
public extension HotKeyCenter {
    @discardableResult
    func register(with hotKey: HotKey) -> Bool {
        guard !hotKeys.keys.contains(hotKey.identifier) else { return false }
        guard !hotKeys.values.contains(hotKey) else { return false }

        hotKeys[hotKey.identifier] = hotKey
        guard !hotKey.keyCombo.doubledModifiers else { return true }
        /*
         *  Normal macOS shortcut
         *
         *  Discussion:
         *    When registering a hotkey, a KeyCode that conforms to the
         *    keyboard layout at the time of registration is registered.
         *    To register a `v` on the QWERTY keyboard, `9` is registered,
         *    and to register a `v` on the Dvorak keyboard, `47` is registered.
         *    Therefore, if you change the keyboard layout after registering
         *    a hot key, the hot key is not assigned to the correct key.
         *    To solve this problem, you need to re-register the hotkeys
         *    when you change the layout, but it's not supported by the
         *    Apple Genuine app either, so it's not supported now.
         */
        let hotKeyId = EventHotKeyID(signature: UTGetOSTypeFromString("Magnet" as CFString), id: hotKeyCount)
        var carbonHotKey: EventHotKeyRef?
        let error = RegisterEventHotKey(UInt32(hotKey.keyCombo.currentKeyCode),
                                        UInt32(hotKey.keyCombo.modifiers),
                                        hotKeyId,
                                        GetEventDispatcherTarget(),
                                        0,
                                        &carbonHotKey)
        guard error == noErr else {
            unregister(with: hotKey)
            return false
        }
        hotKey.hotKeyId = hotKeyId.id
        hotKey.hotKeyRef = carbonHotKey
        hotKeyCount += 1

        return true
    }

    func unregister(with hotKey: HotKey) {
        if let carbonHotKey = hotKey.hotKeyRef {
            UnregisterEventHotKey(carbonHotKey)
        }
        hotKeys.removeValue(forKey: hotKey.identifier)
        hotKey.hotKeyId = nil
        hotKey.hotKeyRef = nil
    }

    @discardableResult
    func unregisterHotKey(with identifier: String) -> Bool {
        guard let hotKey = hotKeys[identifier] else { return false }
        unregister(with: hotKey)
        return true
    }

    func unregisterAll() {
        hotKeys.forEach { unregister(with: $1) }
    }
}

// MARK: - Terminate
extension HotKeyCenter {
    private func observeApplicationTerminate() {
        notificationCenter.addObserver(self,
                                       selector: #selector(HotKeyCenter.applicationWillTerminate),
                                       name: NSApplication.willTerminateNotification,
                                       object: nil)
    }

    @objc func applicationWillTerminate() {
        unregisterAll()
    }
}

// MARK: - HotKey Events
private extension HotKeyCenter {
    func installHotKeyPressedEventHandler() {
        var pressedEventType = EventTypeSpec()
        pressedEventType.eventClass = OSType(kEventClassKeyboard)
        pressedEventType.eventKind = OSType(kEventHotKeyPressed)
        InstallEventHandler(GetEventDispatcherTarget(), { _, inEvent, _ -> OSStatus in
            return HotKeyCenter.shared.sendPressedKeyboardEvent(inEvent!)
        }, 1, &pressedEventType, nil, nil)
    }

    func sendPressedKeyboardEvent(_ event: EventRef) -> OSStatus {
        assert(Int(GetEventClass(event)) == kEventClassKeyboard, "Unknown event class")

        var hotKeyId = EventHotKeyID()
        let error = GetEventParameter(event,
                                      EventParamName(kEventParamDirectObject),
                                      EventParamName(typeEventHotKeyID),
                                      nil,
                                      MemoryLayout<EventHotKeyID>.size,
                                      nil,
                                      &hotKeyId)

        guard error == noErr else { return error }
        assert(hotKeyId.signature == UTGetOSTypeFromString("Magnet" as CFString), "Invalid hot key id")

        let hotKey = hotKeys.values.first(where: { $0.hotKeyId == hotKeyId.id })
        switch GetEventKind(event) {
        case EventParamName(kEventHotKeyPressed):
            hotKey?.invoke()
        default:
            assert(false, "Unknown event kind")
        }
        return noErr
    }
}

// MARK: - Double Tap Modifier Event
private extension HotKeyCenter {
    func installModifiersChangedEventHandlerIfNeeded() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.modifierEventHandler.handleModifiersEvent(with: event.modifierFlags, timestamp: event.timestamp)
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event -> NSEvent? in
            self?.modifierEventHandler.handleModifiersEvent(with: event.modifierFlags, timestamp: event.timestamp)
            return event
        }
        modifierEventHandler.doubleTapped = { [weak self] tappedModifierFlags in
            self?.hotKeys.values
                .filter { $0.keyCombo.doubledModifiers }
                .filter { $0.keyCombo.modifiers == tappedModifierFlags.carbonModifiers() }
                .forEach { $0.invoke() }
        }
    }
}
