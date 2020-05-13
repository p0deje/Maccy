//
//  Key.swift
//
//  Sauce
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

import Foundation
import Carbon

// swiftlint:disable file_length function_body_length type_body_length identifier_name
public enum Key {
    case a
    case s
    case d
    case f
    case h
    case g
    case z
    case x
    case c
    case v
    case b
    case q
    case w
    case e
    case r
    case y
    case t
    case one
    case two
    case three
    case four
    case six
    case five
    case equal
    case nine
    case seven
    case minus
    case eight
    case zero
    case rightBracket
    case o
    case u
    case leftBracket
    case i
    case p
    case l
    case j
    case quote
    case k
    case semicolon
    case backslash
    case comma
    case slash
    case n
    case m
    case period
    case grave
    case keypadDecimal
    case keypadMultiply
    case keypadPlus
    case keypadClear
    case keypadDivide
    case keypadEnter
    case keypadMinus
    case keypadEquals
    case keypadZero
    case keypadOne
    case keypadTwo
    case keypadThree
    case keypadFour
    case keypadFive
    case keypadSix
    case keypadSeven
    case keypadEight
    case keypadNine
    /* keycodes for keys that are independent of keyboard layout */
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
    /* keycodes for JIS keyboard only */
    case yen
    case underscore
    case keypadComma
    case eisu
    case kana

    // MARK: - Initiazlie
    public init?(character: String) {
        let lowercasedString = character.lowercased()
        switch lowercasedString {
        case "a": self = .a
        case "s": self = .s
        case "d": self = .d
        case "f": self = .f
        case "h": self = .h
        case "g": self = .g
        case "z": self = .z
        case "x": self = .x
        case "c": self = .c
        case "v": self = .v
        case "b": self = .b
        case "q": self = .q
        case "w": self = .w
        case "e": self = .e
        case "r": self = .r
        case "y": self = .y
        case "t": self = .t
        case "1", "one": self = .one
        case "2", "two": self = .two
        case "3", "three": self = .three
        case "4", "four": self = .four
        case "6", "six": self = .six
        case "5", "five": self = .five
        case "equal", "=": self = .equal
        case "9", "nine": self = .nine
        case "7", "seven": self = .seven
        case "minus", "-": self = .minus
        case "8", "eight": self = .eight
        case "0", "zero": self = .zero
        case "rightbracket", "]": self = .rightBracket
        case "o": self = .o
        case "u": self = .u
        case "leftbracket", "[": self = .leftBracket
        case "i": self = .i
        case "p": self = .p
        case "l": self = .l
        case "j": self = .j
        case "quote", "'": self = .quote
        case "k": self = .k
        case "semicolon", ";": self = .semicolon
        case "backslash", "\\": self = .backslash
        case "comma", ",": self = .comma
        case "slash", "/": self = .slash
        case "n": self = .n
        case "m": self = .m
        case "period", ".": self = .period
        case "grave", "`": self = .grave
        case "keypaddecimal": self = .keypadDecimal
        case "keypadmultiply": self = .keypadMultiply
        case "keypadplus": self = .keypadPlus
        case "keypadclear": self = .keypadClear
        case "keypaddivide": self = .keypadDivide
        case "keypadenter": self = .keypadEnter
        case "keypadminus": self = .keypadMinus
        case "keypadequals": self = .keypadEquals
        case "keypad0", "keypadzero": self = .keypadZero
        case "keypad1", "keypadone": self = .keypadOne
        case "keypad2", "keypadtwo": self = .keypadTwo
        case "keypad3", "keypadthree": self = .keypadThree
        case "keypad4", "keypadfour": self = .keypadFour
        case "keypad5", "keypadfive": self = .keypadFive
        case "keypad6", "keypadsix": self = .keypadSix
        case "keypad7", "keypadseven": self = .keypadSeven
        case "keypad8", "keypadeight": self = .keypadEight
        case "keypad9", "keypadnine": self = .keypadNine
        case "return", SpecialKeyCode.return.character.lowercased(): self = .return
        case "tab", SpecialKeyCode.tab.character.lowercased(): self = .tab
        case "space", SpecialKeyCode.space.character.lowercased(): self = .space
        case "delete", SpecialKeyCode.delete.character.lowercased(): self = .delete
        case "escape", SpecialKeyCode.escape.character.lowercased(): self = .escape
        case "f17", SpecialKeyCode.f17.character.lowercased(): self = .f17
        case "f18", SpecialKeyCode.f18.character.lowercased(): self = .f18
        case "f19", SpecialKeyCode.f19.character.lowercased(): self = .f19
        case "f20", SpecialKeyCode.f20.character.lowercased(): self = .f20
        case "f5", SpecialKeyCode.f5.character.lowercased(): self = .f5
        case "f6", SpecialKeyCode.f6.character.lowercased(): self = .f6
        case "f7", SpecialKeyCode.f7.character.lowercased(): self = .f7
        case "f3", SpecialKeyCode.f3.character.lowercased(): self = .f3
        case "f8", SpecialKeyCode.f8.character.lowercased(): self = .f8
        case "f9", SpecialKeyCode.f9.character.lowercased(): self = .f9
        case "f11", SpecialKeyCode.f11.character.lowercased(): self = .f11
        case "f13", SpecialKeyCode.f13.character.lowercased(): self = .f13
        case "f16", SpecialKeyCode.f16.character.lowercased(): self = .f16
        case "f14", SpecialKeyCode.f14.character.lowercased(): self = .f14
        case "f10", SpecialKeyCode.f10.character.lowercased(): self = .f10
        case "f12", SpecialKeyCode.f12.character.lowercased(): self = .f12
        case "f15", SpecialKeyCode.f15.character.lowercased(): self = .f15
        case "help", SpecialKeyCode.help.character.lowercased(): self = .help
        case "home", SpecialKeyCode.home.character.lowercased(): self = .home
        case "pageup", SpecialKeyCode.pageUp.character.lowercased(): self = .pageUp
        case "forwarddelete", SpecialKeyCode.forwardDelete.character.lowercased(): self = .forwardDelete
        case "f4", SpecialKeyCode.f4.character.lowercased(): self = .f4
        case "end", SpecialKeyCode.end.character.lowercased(): self = .end
        case "f2", SpecialKeyCode.f2.character.lowercased(): self = .f2
        case "pagedown", SpecialKeyCode.pageDown.character.lowercased(): self = .pageDown
        case "f1", SpecialKeyCode.f1.character.lowercased(): self = .f1
        case "leftarrow", SpecialKeyCode.leftArrow.character.lowercased(): self = .leftArrow
        case "rightarrow", SpecialKeyCode.rightArrow.character.lowercased(): self = .rightArrow
        case "downarrow", SpecialKeyCode.downArrow.character.lowercased(): self = .downArrow
        case "uparrow", SpecialKeyCode.upArrow.character.lowercased(): self = .upArrow
        case "¥", SpecialKeyCode.yen.character.lowercased(): self = .yen
        case "_", SpecialKeyCode.underscore.character.lowercased(): self = .underscore
        // .keypadComma is omitted because it is not recognizable by a character string.
        case "英数", SpecialKeyCode.eisu.character.lowercased(): self = .eisu
        case "かな", SpecialKeyCode.kana.character.lowercased(): self = .kana
        default: return nil
        }
    }

    public init?(QWERTYKeyCode keyCode: Int) {
        switch keyCode {
        case kVK_ANSI_A: self = .a
        case kVK_ANSI_S: self = .s
        case kVK_ANSI_D: self = .d
        case kVK_ANSI_F: self = .f
        case kVK_ANSI_H: self = .h
        case kVK_ANSI_G: self = .g
        case kVK_ANSI_Z: self = .z
        case kVK_ANSI_X: self = .x
        case kVK_ANSI_C: self = .c
        case kVK_ANSI_V: self = .v
        case kVK_ANSI_B: self = .b
        case kVK_ANSI_Q: self = .q
        case kVK_ANSI_W: self = .w
        case kVK_ANSI_E: self = .e
        case kVK_ANSI_R: self = .r
        case kVK_ANSI_Y: self = .y
        case kVK_ANSI_T: self = .t
        case kVK_ANSI_1: self = .one
        case kVK_ANSI_2: self = .two
        case kVK_ANSI_3: self = .three
        case kVK_ANSI_4: self = .four
        case kVK_ANSI_6: self = .six
        case kVK_ANSI_5: self = .five
        case kVK_ANSI_Equal: self = .equal
        case kVK_ANSI_9: self = .nine
        case kVK_ANSI_7: self = .seven
        case kVK_ANSI_Minus: self = .minus
        case kVK_ANSI_8: self = .eight
        case kVK_ANSI_0: self = .zero
        case kVK_ANSI_RightBracket: self = .rightBracket
        case kVK_ANSI_O: self = .o
        case kVK_ANSI_U: self = .u
        case kVK_ANSI_LeftBracket: self = .leftBracket
        case kVK_ANSI_I: self = .i
        case kVK_ANSI_P: self = .p
        case kVK_ANSI_L: self = .l
        case kVK_ANSI_J: self = .j
        case kVK_ANSI_Quote: self = .quote
        case kVK_ANSI_K: self = .k
        case kVK_ANSI_Semicolon: self = .semicolon
        case kVK_ANSI_Backslash: self = .backslash
        case kVK_ANSI_Comma: self = .comma
        case kVK_ANSI_Slash: self = .slash
        case kVK_ANSI_N: self = .n
        case kVK_ANSI_M: self = .m
        case kVK_ANSI_Period: self = .period
        case kVK_ANSI_Grave: self = .grave
        case kVK_ANSI_KeypadDecimal: self = .keypadDecimal
        case kVK_ANSI_KeypadMultiply: self = .keypadMultiply
        case kVK_ANSI_KeypadPlus: self = .keypadPlus
        case kVK_ANSI_KeypadClear: self = .keypadClear
        case kVK_ANSI_KeypadDivide: self = .keypadDivide
        case kVK_ANSI_KeypadEnter: self = .keypadEnter
        case kVK_ANSI_KeypadMinus: self = .keypadMinus
        case kVK_ANSI_KeypadEquals: self = .keypadEquals
        case kVK_ANSI_Keypad0: self = .keypadZero
        case kVK_ANSI_Keypad1: self = .keypadOne
        case kVK_ANSI_Keypad2: self = .keypadTwo
        case kVK_ANSI_Keypad3: self = .keypadThree
        case kVK_ANSI_Keypad4: self = .keypadFour
        case kVK_ANSI_Keypad5: self = .keypadFive
        case kVK_ANSI_Keypad6: self = .keypadSix
        case kVK_ANSI_Keypad7: self = .keypadSeven
        case kVK_ANSI_Keypad8: self = .keypadEight
        case kVK_ANSI_Keypad9: self = .keypadNine
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
    public var QWERTYKeyCode: CGKeyCode {
        switch self {
        case .a: return CGKeyCode(kVK_ANSI_A)
        case .s: return CGKeyCode(kVK_ANSI_S)
        case .d: return CGKeyCode(kVK_ANSI_D)
        case .f: return CGKeyCode(kVK_ANSI_F)
        case .h: return CGKeyCode(kVK_ANSI_H)
        case .g: return CGKeyCode(kVK_ANSI_G)
        case .z: return CGKeyCode(kVK_ANSI_Z)
        case .x: return CGKeyCode(kVK_ANSI_X)
        case .c: return CGKeyCode(kVK_ANSI_C)
        case .v: return CGKeyCode(kVK_ANSI_V)
        case .b: return CGKeyCode(kVK_ANSI_B)
        case .q: return CGKeyCode(kVK_ANSI_Q)
        case .w: return CGKeyCode(kVK_ANSI_W)
        case .e: return CGKeyCode(kVK_ANSI_E)
        case .r: return CGKeyCode(kVK_ANSI_R)
        case .y: return CGKeyCode(kVK_ANSI_Y)
        case .t: return CGKeyCode(kVK_ANSI_T)
        case .one: return CGKeyCode(kVK_ANSI_1)
        case .two: return CGKeyCode(kVK_ANSI_2)
        case .three: return CGKeyCode(kVK_ANSI_3)
        case .four: return CGKeyCode(kVK_ANSI_4)
        case .six: return CGKeyCode(kVK_ANSI_6)
        case .five: return CGKeyCode(kVK_ANSI_5)
        case .equal: return CGKeyCode(kVK_ANSI_Equal)
        case .nine: return CGKeyCode(kVK_ANSI_9)
        case .seven: return CGKeyCode(kVK_ANSI_7)
        case .minus: return CGKeyCode(kVK_ANSI_Minus)
        case .eight: return CGKeyCode(kVK_ANSI_8)
        case .zero: return CGKeyCode(kVK_ANSI_0)
        case .rightBracket: return CGKeyCode(kVK_ANSI_RightBracket)
        case .o: return CGKeyCode(kVK_ANSI_O)
        case .u: return CGKeyCode(kVK_ANSI_U)
        case .leftBracket: return CGKeyCode(kVK_ANSI_LeftBracket)
        case .i: return CGKeyCode(kVK_ANSI_I)
        case .p: return CGKeyCode(kVK_ANSI_P)
        case .l: return CGKeyCode(kVK_ANSI_L)
        case .j: return CGKeyCode(kVK_ANSI_J)
        case .quote: return CGKeyCode(kVK_ANSI_Quote)
        case .k: return CGKeyCode(kVK_ANSI_K)
        case .semicolon: return CGKeyCode(kVK_ANSI_Semicolon)
        case .backslash: return CGKeyCode(kVK_ANSI_Backslash)
        case .comma: return CGKeyCode(kVK_ANSI_Comma)
        case .slash: return CGKeyCode(kVK_ANSI_Slash)
        case .n: return CGKeyCode(kVK_ANSI_N)
        case .m: return CGKeyCode(kVK_ANSI_M)
        case .period: return CGKeyCode(kVK_ANSI_Period)
        case .grave: return CGKeyCode(kVK_ANSI_Grave)
        case .keypadDecimal: return CGKeyCode(kVK_ANSI_KeypadDecimal)
        case .keypadMultiply: return CGKeyCode(kVK_ANSI_KeypadMultiply)
        case .keypadPlus: return CGKeyCode(kVK_ANSI_KeypadPlus)
        case .keypadClear: return CGKeyCode(kVK_ANSI_KeypadClear)
        case .keypadDivide: return CGKeyCode(kVK_ANSI_KeypadDivide)
        case .keypadEnter: return CGKeyCode(kVK_ANSI_KeypadEnter)
        case .keypadMinus: return CGKeyCode(kVK_ANSI_KeypadMinus)
        case .keypadEquals: return CGKeyCode(kVK_ANSI_KeypadEquals)
        case .keypadZero: return CGKeyCode(kVK_ANSI_Keypad0)
        case .keypadOne: return CGKeyCode(kVK_ANSI_Keypad1)
        case .keypadTwo: return CGKeyCode(kVK_ANSI_Keypad2)
        case .keypadThree: return CGKeyCode(kVK_ANSI_Keypad3)
        case .keypadFour: return CGKeyCode(kVK_ANSI_Keypad4)
        case .keypadFive: return CGKeyCode(kVK_ANSI_Keypad5)
        case .keypadSix: return CGKeyCode(kVK_ANSI_Keypad6)
        case .keypadSeven: return CGKeyCode(kVK_ANSI_Keypad7)
        case .keypadEight: return CGKeyCode(kVK_ANSI_Keypad8)
        case .keypadNine: return CGKeyCode(kVK_ANSI_Keypad9)
        case .return: return CGKeyCode(kVK_Return)
        case .tab: return CGKeyCode(kVK_Tab)
        case .space: return CGKeyCode(kVK_Space)
        case .delete: return CGKeyCode(kVK_Delete)
        case .escape: return CGKeyCode(kVK_Escape)
        case .f17: return CGKeyCode(kVK_F17)
        case .f18: return CGKeyCode(kVK_F18)
        case .f19: return CGKeyCode(kVK_F19)
        case .f20: return CGKeyCode(kVK_F20)
        case .f5: return CGKeyCode(kVK_F5)
        case .f6: return CGKeyCode(kVK_F6)
        case .f7: return CGKeyCode(kVK_F7)
        case .f3: return CGKeyCode(kVK_F3)
        case .f8: return CGKeyCode(kVK_F8)
        case .f9: return CGKeyCode(kVK_F9)
        case .f11: return CGKeyCode(kVK_F11)
        case .f13: return CGKeyCode(kVK_F13)
        case .f16: return CGKeyCode(kVK_F16)
        case .f14: return CGKeyCode(kVK_F14)
        case .f10: return CGKeyCode(kVK_F10)
        case .f12: return CGKeyCode(kVK_F12)
        case .f15: return CGKeyCode(kVK_F15)
        case .help: return CGKeyCode(kVK_Help)
        case .home: return CGKeyCode(kVK_Home)
        case .pageUp: return CGKeyCode(kVK_PageUp)
        case .forwardDelete: return CGKeyCode(kVK_ForwardDelete)
        case .f4: return CGKeyCode(kVK_F4)
        case .end: return CGKeyCode(kVK_End)
        case .f2: return CGKeyCode(kVK_F2)
        case .pageDown: return CGKeyCode(kVK_PageDown)
        case .f1: return CGKeyCode(kVK_F1)
        case .leftArrow: return CGKeyCode(kVK_LeftArrow)
        case .rightArrow: return CGKeyCode(kVK_RightArrow)
        case .downArrow: return CGKeyCode(kVK_DownArrow)
        case .upArrow: return CGKeyCode(kVK_UpArrow)
        case .yen: return CGKeyCode(kVK_JIS_Yen)
        case .underscore: return CGKeyCode(kVK_JIS_Underscore)
        case .keypadComma: return CGKeyCode(kVK_JIS_KeypadComma)
        case .eisu: return CGKeyCode(kVK_JIS_Eisu)
        case .kana: return CGKeyCode(kVK_JIS_Kana)
        }
    }

}

// MARK: - Equatable
extension Key: Equatable {
    public static func == (lhs: Key, rhs: Key) -> Bool {
        return lhs.QWERTYKeyCode == rhs.QWERTYKeyCode
    }
}
