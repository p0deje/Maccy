//
//  KeyboardLayout.swift
//
//  Sauce
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

import Foundation
import Carbon

final class KeyboardLayout {

    // MARK: - Properties
    private var currentKeyboardLayoutInputSource: InputSource
    private var currentASCIICapableInputSouce: InputSource
    private var mappedKeyCodes = [InputSource: [Key: CGKeyCode]]()
    private(set) var inputSources = [InputSource]()

    private let distributedNotificationCenter: DistributedNotificationCenter
    private let notificationCenter: NotificationCenter
    private let modifierTransformer: ModifierTransformer

    // MARK: - Initialize
    init(distributedNotificationCenter: DistributedNotificationCenter = .default(), notificationCenter: NotificationCenter = .default, modifierTransformer: ModifierTransformer = ModifierTransformer()) {
        self.distributedNotificationCenter = distributedNotificationCenter
        self.notificationCenter = notificationCenter
        self.modifierTransformer = modifierTransformer
        self.currentKeyboardLayoutInputSource = InputSource(source: TISCopyCurrentKeyboardLayoutInputSource().takeUnretainedValue())
        self.currentASCIICapableInputSouce = InputSource(source: TISCopyCurrentASCIICapableKeyboardInputSource().takeUnretainedValue())
        mappingInputSources()
        mappingKeyCodes(with: currentKeyboardLayoutInputSource)
        observeNotifications()
    }

    deinit {
        distributedNotificationCenter.removeObserver(self)
        notificationCenter.removeObserver(self)
    }

}

// MARK: - KeyCodes
extension KeyboardLayout {
    func currentKeyCodes() -> [Key: CGKeyCode]? {
        return keyCodes(with: currentKeyboardLayoutInputSource)
    }

    func currentKeyCode(by key: Key) -> CGKeyCode? {
        return keyCode(with: currentKeyboardLayoutInputSource, key: key)
    }

    func keyCodes(with source: InputSource) -> [Key: CGKeyCode]? {
        return mappedKeyCodes[source]
    }

    func keyCode(with source: InputSource, key: Key) -> CGKeyCode? {
        return mappedKeyCodes[source]?[key]
    }
}

// MARK: - Key
extension KeyboardLayout {
    func currentKey(by keyCode: Int) -> Key? {
        return key(with: currentKeyboardLayoutInputSource, keyCode: keyCode)
    }

    func key(with source: InputSource, keyCode: Int) -> Key? {
        return mappedKeyCodes[source]?.first(where: { $0.value == CGKeyCode(keyCode) })?.key
    }
}

// MARK: - Characters
extension KeyboardLayout {
    func currentCharacter(by keyCode: Int, carbonModifiers: Int) -> String? {
        return character(with: currentKeyboardLayoutInputSource, keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    func currentASCIICapableCharacter(by keyCode: Int, carbonModifiers: Int) -> String? {
        return character(with: currentASCIICapableInputSouce, keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    func character(with source: InputSource, keyCode: Int, carbonModifiers: Int) -> String? {
        return character(with: source.source, keyCode: keyCode, carbonModifiers: carbonModifiers)
    }
}

// MARK: - Notifications
extension KeyboardLayout {
    private func observeNotifications() {
        distributedNotificationCenter.addObserver(self,
                                                  selector: #selector(selectedKeyboardInputSourceChanged),
                                                  name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                                  object: nil,
                                                  suspensionBehavior: .deliverImmediately)
        distributedNotificationCenter.addObserver(self,
                                                  selector: #selector(enabledKeyboardInputSourcesChanged),
                                                  name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
                                                  object: nil,
                                                  suspensionBehavior: .deliverImmediately)
    }

    @objc func selectedKeyboardInputSourceChanged() {
        let source = InputSource(source: TISCopyCurrentKeyboardLayoutInputSource().takeUnretainedValue())
        self.currentASCIICapableInputSouce = InputSource(source: TISCopyCurrentASCIICapableKeyboardInputSource().takeUnretainedValue())
        guard source != currentKeyboardLayoutInputSource else { return }
        self.currentKeyboardLayoutInputSource = source
        guard mappedKeyCodes[source] == nil else {
            notificationCenter.post(name: .SauceSelectedKeyboardInputSourceChanged, object: nil)
            return
        }
        mappingKeyCodes(with: source)
        notificationCenter.post(name: .SauceSelectedKeyboardInputSourceChanged, object: nil)
    }

    @objc func enabledKeyboardInputSourcesChanged() {
        mappedKeyCodes.removeAll()
        mappingInputSources()
        mappingKeyCodes(with: currentKeyboardLayoutInputSource)
        notificationCenter.post(name: .SauceEnabledKeyboardInputSoucesChanged, object: nil)
    }
}

// MAKR: - Layouts
private extension KeyboardLayout {
    func mappingInputSources() {
        guard let sources = TISCreateInputSourceList([:] as CFDictionary, false).takeUnretainedValue() as? [TISInputSource] else { return }
        inputSources = sources.map { InputSource(source: $0) }
        inputSources.forEach { mappingKeyCodes(with: $0) }
    }

    func mappingKeyCodes(with source: InputSource) {
        guard let layoutData = TISGetInputSourceProperty(source.source, kTISPropertyUnicodeKeyLayoutData) else { return }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var keyCodes = [Key: CGKeyCode]()
        for i in 0..<128 {
            guard let character = character(with: data, keyCode: i, carbonModifiers: 0) else { continue }
            guard let key = Key(character: character) else { continue }
            keyCodes[key] = CGKeyCode(i)
        }
        mappedKeyCodes[source] = keyCodes
    }

    func character(with source: TISInputSource, keyCode: Int, carbonModifiers: Int) -> String? {
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        return character(with: data, keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    func character(with layoutData: Data, keyCode: Int, carbonModifiers: Int) -> String? {
        // In the case of the special key code, it does not depend on the keyboard layout
        if let specialKeyCode = SpecialKeyCode(keyCode: keyCode) { return specialKeyCode.character }

        let modifierKeyState = (modifierTransformer.convertCharactorSupportCarbonModifiers(from: carbonModifiers) >> 8) & 0xff
        var deadKeyState: UInt32 = 0
        let maxChars = 256
        var chars = [UniChar](repeating: 0, count: maxChars)
        var length = 0
        let error = layoutData.withUnsafeBytes { pointer -> OSStatus in
            guard let keyboardLayoutPointer = pointer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return errSecAllocate }
            return CoreServices.UCKeyTranslate(keyboardLayoutPointer,
                                               UInt16(keyCode),
                                               UInt16(CoreServices.kUCKeyActionDisplay),
                                               UInt32(modifierKeyState),
                                               UInt32(LMGetKbdType()),
                                               OptionBits(CoreServices.kUCKeyTranslateNoDeadKeysBit),
                                               &deadKeyState,
                                               maxChars,
                                               &length,
                                               &chars)
        }
        guard error == noErr else { return nil }
        return NSString(characters: &chars, length: length) as String
    }
}
