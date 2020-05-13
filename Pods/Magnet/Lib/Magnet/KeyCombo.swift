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
    public let QWERTYKeyCode: Int
    public let modifiers: Int
    public let doubledModifiers: Bool
    public var characters: String {
        guard !doubledModifiers else { return "" }
        guard let key = Key(QWERTYKeyCode: QWERTYKeyCode) else { return "" }
        return Sauce.shared.character(by: Int(Sauce.shared.keyCode(by: key)), carbonModifiers: modifiers) ?? ""
    }
    public var keyEquivalent: String {
        guard !doubledModifiers else { return "" }
        guard let key = Key(QWERTYKeyCode: QWERTYKeyCode) else { return "" }
        let modifiers = self.modifiers.convertSupportCocoaModifiers().filterNotShiftModifiers().carbonModifiers()
        return Sauce.shared.character(by: Int(Sauce.shared.keyCode(by: key)), carbonModifiers: modifiers) ?? ""
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

    private let key: Key

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
        self.modifiers = filterdCocoaModifiers.carbonModifiers(isSupportFunctionKey: true)
        self.QWERTYKeyCode = Int(key.QWERTYKeyCode)
        self.doubledModifiers = false
        self.key = key
    }

    public convenience init?(doubledCarbonModifiers modifiers: Int) {
        self.init(doubledCocoaModifiers: modifiers.convertSupportCocoaModifiers())
    }

    public init?(doubledCocoaModifiers modifiers: NSEvent.ModifierFlags) {
        guard modifiers.isSingleFlags else { return nil }
        self.modifiers = modifiers.carbonModifiers()
        self.QWERTYKeyCode = 0
        self.doubledModifiers = true
        self.key = .a
    }

    // MARK: - NSCoping
    public func copy(with zone: NSZone?) -> Any {
        if doubledModifiers {
            return KeyCombo(doubledCarbonModifiers: modifiers) as Any
        } else {
            return KeyCombo(QWERTYKeyCode: QWERTYKeyCode, carbonModifiers: modifiers) as Any
        }
    }

    // MARK: - NSCoding
    public init?(coder aDecoder: NSCoder) {
        // Changed KeyCode to QWERTYKeyCode from v3.0.0
        let containsKeyCode = aDecoder.containsValue(forKey: "keyCode")
        if containsKeyCode {
            self.QWERTYKeyCode = aDecoder.decodeInteger(forKey: "keyCode")
        } else {
            self.QWERTYKeyCode = aDecoder.decodeInteger(forKey: "QWERTYKeyCode")
        }
        guard let key = Key(QWERTYKeyCode: QWERTYKeyCode) else { return nil }
        self.modifiers = aDecoder.decodeInteger(forKey: "modifiers")
        self.doubledModifiers = aDecoder.decodeBool(forKey: "doubledModifiers")
        self.key = key
    }

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(QWERTYKeyCode, forKey: "QWERTYKeyCode")
        aCoder.encode(modifiers, forKey: "modifiers")
        aCoder.encode(doubledModifiers, forKey: "doubledModifiers")
    }

    // MARK: - Codable
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.keyCode) {
            // Changed KeyCode to QWERTYKeyCode from v3.0.0
            self.QWERTYKeyCode = try container.decode(Int.self, forKey: .keyCode)
        } else {
            self.QWERTYKeyCode = try container.decode(Int.self, forKey: .QWERTYKeyCode)
        }
        guard let key = Key(QWERTYKeyCode: QWERTYKeyCode) else {
            throw KeyCombo.InitializeError()
        }
        self.modifiers = try container.decode(Int.self, forKey: .modifiers)
        self.doubledModifiers = try container.decode(Bool.self, forKey: .doubledModifiers)
        self.key = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(QWERTYKeyCode, forKey: .QWERTYKeyCode)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(doubledModifiers, forKey: .doubledModifiers)
    }

    // MARK: - Coding Keys
    private enum CodingKeys: String, CodingKey {
        case keyCode
        case QWERTYKeyCode
        case modifiers
        case doubledModifiers
    }

    // MARK: - Equatable
    public override func isEqual(_ object: Any?) -> Bool {
        guard let keyCombo = object as? KeyCombo else { return false }
        return QWERTYKeyCode == keyCombo.QWERTYKeyCode &&
                modifiers == keyCombo.modifiers &&
                doubledModifiers == keyCombo.doubledModifiers
    }

}

// MARK: - Error
public extension KeyCombo {
    struct InitializeError: Error {}
}
