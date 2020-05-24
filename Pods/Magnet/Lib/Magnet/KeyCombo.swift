//
//  KeyCombo.swift
//
//  Magnet
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

import Cocoa
import Carbon
import Sauce

public final class KeyCombo: NSObject, NSCopying, NSCoding, Codable {

    // MARK: - Properties
    public let key: Key
    public let modifiers: Int
    public let doubledModifiers: Bool
    public var QWERTYKeyCode: Int {
        guard !doubledModifiers else { return 0 }
        return Int(key.QWERTYKeyCode)
    }
    public var characters: String {
        guard !doubledModifiers else { return "" }
        return Sauce.shared.character(by: Int(Sauce.shared.keyCode(by: key)), carbonModifiers: modifiers) ?? ""
    }
    public var keyEquivalent: String {
        guard !doubledModifiers else { return "" }
        let keyCode = Int(Sauce.shared.keyCode(by: key))
        guard key.isAlphabet else { return Sauce.shared.character(by: keyCode, cocoaModifiers: []) ?? "" }
        let modifiers = self.modifiers.convertSupportCocoaModifiers().filterNotShiftModifiers()
        return Sauce.shared.character(by: keyCode, cocoaModifiers: modifiers) ?? ""
    }
    public var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        return modifiers.convertSupportCocoaModifiers()
    }
    public var keyEquivalentModifierMaskString: String {
        return keyEquivalentModifierMask.keyEquivalentStrings().joined()
    }
    public var currentKeyCode: CGKeyCode {
        guard !doubledModifiers else { return 0 }
        return Sauce.shared.keyCode(by: key)
    }

    // MARK: - Initialize
    public convenience init?(QWERTYKeyCode: Int, carbonModifiers: Int) {
        self.init(QWERTYKeyCode: QWERTYKeyCode, cocoaModifiers: carbonModifiers.convertSupportCocoaModifiers())
    }

    public convenience init?(QWERTYKeyCode: Int, cocoaModifiers: NSEvent.ModifierFlags) {
        guard let key = Key(QWERTYKeyCode: QWERTYKeyCode) else { return nil }
        self.init(key: key, cocoaModifiers: cocoaModifiers)
    }

    public convenience init?(key: Key, carbonModifiers: Int) {
        self.init(key: key, cocoaModifiers: carbonModifiers.convertSupportCocoaModifiers())
    }

    public init?(key: Key, cocoaModifiers: NSEvent.ModifierFlags) {
        var filterdCocoaModifiers = cocoaModifiers.filterUnsupportModifiers()
        // In the case of the function key, will need to add the modifier manually
        if key.isFunctionKey {
            filterdCocoaModifiers.insert(.function)
        }
        guard filterdCocoaModifiers.containsSupportModifiers else { return nil }
        self.key = key
        self.modifiers = filterdCocoaModifiers.carbonModifiers(isSupportFunctionKey: true)
        self.doubledModifiers = false
    }

    public convenience init?(doubledCarbonModifiers modifiers: Int) {
        self.init(doubledCocoaModifiers: modifiers.convertSupportCocoaModifiers())
    }

    public init?(doubledCocoaModifiers modifiers: NSEvent.ModifierFlags) {
        let filterdCocoaModifiers = modifiers.filterUnsupportModifiers()
        guard modifiers.isSingleFlags else { return nil }
        self.key = .a
        self.modifiers = filterdCocoaModifiers.carbonModifiers()
        self.doubledModifiers = true
    }

    // MARK: - NSCoping
    public func copy(with zone: NSZone?) -> Any {
        if doubledModifiers {
            return KeyCombo(doubledCarbonModifiers: modifiers) as Any
        } else {
            return KeyCombo(key: key, carbonModifiers: modifiers) as Any
        }
    }

    // MARK: - NSCoding
    public init?(coder aDecoder: NSCoder) {
        self.doubledModifiers = aDecoder.decodeBool(forKey: CodingKeys.doubledModifiers.rawValue)
        self.modifiers = aDecoder.decodeInteger(forKey: CodingKeys.modifiers.rawValue)
        guard !doubledModifiers else {
            self.key = .a
            return
        }
        // Changed KeyCode to Key from v3.2.0
        guard !aDecoder.containsValue(forKey: CodingKeys.key.rawValue) else {
            guard let keyRawValue = aDecoder.decodeObject(forKey: CodingKeys.key.rawValue) as? String else { return nil }
            guard let key = Key(rawValue: keyRawValue) else { return nil }
            self.key = key
            return
        }
        // Changed KeyCode to QWERTYKeyCode from v3.0.0
        let QWERTYKeyCode: Int
        if aDecoder.containsValue(forKey: CodingKeys.keyCode.rawValue) {
            QWERTYKeyCode = aDecoder.decodeInteger(forKey: CodingKeys.keyCode.rawValue)
        } else {
            QWERTYKeyCode = aDecoder.decodeInteger(forKey: CodingKeys.QWERTYKeyCode.rawValue)
        }
        guard let key = Key(QWERTYKeyCode: QWERTYKeyCode) else { return nil }
        self.key = key
    }

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(key.rawValue, forKey: CodingKeys.key.rawValue)
        aCoder.encode(modifiers, forKey: CodingKeys.modifiers.rawValue)
        aCoder.encode(doubledModifiers, forKey: CodingKeys.doubledModifiers.rawValue)
    }

    // MARK: - Codable
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.doubledModifiers = try container.decode(Bool.self, forKey: .doubledModifiers)
        self.modifiers = try container.decode(Int.self, forKey: .modifiers)
        guard !doubledModifiers else {
            self.key = .a
            return
        }
        // Changed KeyCode to Key from v3.2.0
        guard !container.contains(.key) else {
            self.key = try container.decode(Key.self, forKey: .key)
            return
        }
        // Changed KeyCode to QWERTYKeyCode from v3.0.0
        let QWERTYKeyCode: Int
        if container.contains(.keyCode) {
            QWERTYKeyCode = try container.decode(Int.self, forKey: .keyCode)
        } else {
            QWERTYKeyCode = try container.decode(Int.self, forKey: .QWERTYKeyCode)
        }
        guard let key = Key(QWERTYKeyCode: QWERTYKeyCode) else { throw KeyCombo.InitializeError() }
        self.key = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(doubledModifiers, forKey: .doubledModifiers)
    }

    // MARK: - Coding Keys
    private enum CodingKeys: String, CodingKey {
        case key
        case keyCode
        case QWERTYKeyCode
        case modifiers
        case doubledModifiers
    }

    // MARK: - Equatable
    public override func isEqual(_ object: Any?) -> Bool {
        guard let keyCombo = object as? KeyCombo else { return false }
        return key == keyCombo.key &&
            modifiers == keyCombo.modifiers &&
            doubledModifiers == keyCombo.doubledModifiers
    }

}

// MARK: - Error
public extension KeyCombo {
    struct InitializeError: Error {}
}
