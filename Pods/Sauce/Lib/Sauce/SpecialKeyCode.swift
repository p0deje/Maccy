//
//  SpecialKeyCode.swift
//
//  Sauce
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

import Foundation
import Carbon

// swiftlint:disable identifier_name

/**
 *  keycodes for keys that are independent of keyboard layout
 *  ref: Carbon.framework
 *
 *  UCKeyTranslate can not convert a layout-independent keycode to string.
 **/
enum SpecialKeyCode {
    case `return`
    case tab
    case space
    case delete
    case escape
    case f17
    case f18
    case f19
    case f20
    case f5
    case f6
    case f7
    case f3
    case f8
    case f9
    case f11
    case f13
    case f16
    case f14
    case f10
    case f12
    case f15
    case help
    case home
    case pageUp
    case forwardDelete
    case f4
    case end
    case f2
    case pageDown
    case f1
    case leftArrow
    case rightArrow
    case downArrow
    case upArrow
    case yen
    case underscore
    case keypadComma
    case eisu
    case kana

    // MARK: - Initialize
    init?(keyCode: Int) {
        switch keyCode {
        case kVK_Return: self = .return
        case kVK_Tab: self = .tab
        case kVK_Space: self = .space
        case kVK_Delete: self = .delete
        case kVK_Escape: self = .escape
        case kVK_F17: self = .f17
        case kVK_F18: self = .f18
        case kVK_F19: self = .f19
        case kVK_F20: self = .f20
        case kVK_F5: self = .f5
        case kVK_F6: self = .f6
        case kVK_F7: self = .f7
        case kVK_F3: self = .f3
        case kVK_F8: self = .f8
        case kVK_F9: self = .f9
        case kVK_F11: self = .f11
        case kVK_F13: self = .f13
        case kVK_F16: self = .f16
        case kVK_F14: self = .f14
        case kVK_F10: self = .f10
        case kVK_F12: self = .f12
        case kVK_F15: self = .f15
        case kVK_Help: self = .help
        case kVK_Home: self = .home
        case kVK_PageUp: self = .pageUp
        case kVK_ForwardDelete: self = .forwardDelete
        case kVK_F4: self = .f4
        case kVK_End: self = .end
        case kVK_F2: self = .f2
        case kVK_PageDown: self = .pageDown
        case kVK_F1: self = .f1
        case kVK_LeftArrow: self = .leftArrow
        case kVK_RightArrow: self = .rightArrow
        case kVK_DownArrow: self = .downArrow
        case kVK_UpArrow: self = .upArrow
        case kVK_JIS_Yen: self = .yen
        case kVK_JIS_Underscore: self = .underscore
        case kVK_JIS_KeypadComma: self = .keypadComma
        case kVK_JIS_Eisu: self = .eisu
        case kVK_JIS_Kana: self = .kana
        default: return nil
        }
    }

    // MARK: - Properties
    var character: String {
        switch self {
        case .return: return 0x21A9.string // ↩
        case .tab: return 0x21E5.string // ⇥
        case .space: return "Space"
        case .delete: return 0x232B.string // ⌫
        case .escape: return 0x238B.string // ⎋
        case .f17: return "F17"
        case .f18: return "F18"
        case .f19: return "F19"
        case .f20: return "F20"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f3: return "F3"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f11: return "F11"
        case .f13: return "F13"
        case .f16: return "F16"
        case .f14: return "F14"
        case .f10: return "F10"
        case .f12: return "F12"
        case .f15: return "F15"
        case .help: return "?⃝"
        case .home: return 0x2196.string // ↖
        case .pageUp: return 0x21DE.string // ⇞
        case .forwardDelete: return 0x2326.string // ⌦
        case .f4: return "F4"
        case .end: return 0x2198.string // ↘
        case .f2: return "F2"
        case .pageDown: return 0x21DF.string // ⇟
        case .f1: return "F1"
        case .leftArrow: return 0x2190.string // ←
        case .rightArrow: return 0x2192.string // →
        case .downArrow: return 0x2193.string // ↓
        case .upArrow: return 0x2191.string // ↑
        case .yen: return "¥"
        case .underscore: return "_"
        case .keypadComma: return ","
        case .eisu: return "英数"
        case .kana: return "かな"
        }
    }
}

private extension Int {
    var string: String {
        return String(format: "%C", self)
    }
}
