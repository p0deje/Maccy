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
    private var tappedModifierKey = NSEvent.ModifierFlags(rawValue: 0)
    private var multiModifiers = false
    private var lastHandledEventTimeStamp: TimeInterval?
    private let notificationCenter: NotificationCenter

    // MARK: - Initialize
    init(notificationCenter: NotificationCenter = .default) {
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
        // Normal macOS shortcut
        /*
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
        if error != 0 {
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
            return HotKeyCenter.shared.sendCarbonEvent(inEvent!)
        }, 1, &pressedEventType, nil, nil)
    }

    func sendCarbonEvent(_ event: EventRef) -> OSStatus {
        assert(Int(GetEventClass(event)) == kEventClassKeyboard, "Unknown event class")

        var hotKeyId = EventHotKeyID()
        let error = GetEventParameter(event,
                                      EventParamName(kEventParamDirectObject),
                                      EventParamName(typeEventHotKeyID),
                                      nil,
                                      MemoryLayout<EventHotKeyID>.size,
                                      nil,
                                      &hotKeyId)

        if error != 0 { return error }

        assert(hotKeyId.signature == UTGetOSTypeFromString("Magnet" as CFString), "Invalid hot key id")

        let hotKey = hotKeys.values.first(where: { $0.hotKeyId == hotKeyId.id })
        switch GetEventKind(event) {
        case EventParamName(kEventHotKeyPressed):
            hotKeyDown(hotKey)
        default:
            assert(false, "Unknown event kind")
        }
        return noErr
    }

    func hotKeyDown(_ hotKey: HotKey?) {
        guard let hotKey = hotKey else { return }
        hotKey.invoke()
    }
}

// MARK: - Double Tap Modifier Event
private extension HotKeyCenter {
    func installModifiersChangedEventHandlerIfNeeded() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.sendModifiersChangeEvent(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event -> NSEvent? in
            self?.sendModifiersChangeEvent(event)
            return event
        }
    }

    func sendModifiersChangeEvent(_ event: NSEvent) {
        guard lastHandledEventTimeStamp != event.timestamp else { return }
        lastHandledEventTimeStamp = event.timestamp

        let modifierFlags = event.modifierFlags
        let commandTapped = modifierFlags.contains(.command)
        let shiftTapped = modifierFlags.contains(.shift)
        let controlTapped = modifierFlags.contains(.control)
        let optionTapped = modifierFlags.contains(.option)
        let modifiersCount = [commandTapped, optionTapped, shiftTapped, controlTapped].trueCount
        guard modifiersCount != 0 else { return }
        guard modifiersCount == 1 else {
            multiModifiers = true
            return
        }
        guard !multiModifiers else {
            multiModifiers = false
            return
        }
        if (tappedModifierKey.contains(.command) && commandTapped) ||
            (tappedModifierKey.contains(.shift) && shiftTapped)    ||
            (tappedModifierKey.contains(.control) && controlTapped) ||
            (tappedModifierKey.contains(.option) && optionTapped) {
            doubleTapped(with: tappedModifierKey.carbonModifiers())
            tappedModifierKey = NSEvent.ModifierFlags(rawValue: 0)
        } else {
            if commandTapped {
                tappedModifierKey = .command
            } else if shiftTapped {
                tappedModifierKey = .shift
            } else if controlTapped {
                tappedModifierKey = .control
            } else if optionTapped {
                tappedModifierKey = .option
            } else {
                tappedModifierKey = NSEvent.ModifierFlags(rawValue: 0)
            }
        }
        // Clean Flag
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: { [weak self] in
            self?.tappedModifierKey = NSEvent.ModifierFlags(rawValue: 0)
        })
    }

    func doubleTapped(with key: Int) {
        hotKeys.values
            .filter { $0.keyCombo.doubledModifiers && $0.keyCombo.modifiers == key }
            .forEach { $0.invoke() }
    }
}
