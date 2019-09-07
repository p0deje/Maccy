import Carbon

public enum Key {

    // MARK: - Letters

    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z

    // MARK: - Numbers

    case zero
    case one
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight
    case nine

    // MARK: - Symbols

    case period
    case quote
    case rightBracket
    case semicolon
    case slash
    case backslash
    case comma
    case equal
    case grave // Backtick
    case leftBracket
    case minus

    // MARK: - Whitespace

    case space
    case tab
    case `return`

    // MARK: - Modifiers

    case command
    case rightCommand
    case option
    case rightOption
    case control
    case rightControl
    case shift
    case rightShift
    case function
    case capsLock

    // MARK: - Navigation

    case pageUp
    case pageDown
    case home
    case end
    case upArrow
    case rightArrow
    case downArrow
    case leftArrow

    // MARK: - Functions

    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12
    case f13
    case f14
    case f15
    case f16
    case f17
    case f18
    case f19
    case f20

    // MARK: - Keypad

    case keypad0
    case keypad1
    case keypad2
    case keypad3
    case keypad4
    case keypad5
    case keypad6
    case keypad7
    case keypad8
    case keypad9
    case keypadClear
    case keypadDecimal
    case keypadDivide
    case keypadEnter
    case keypadEquals
    case keypadMinus
    case keypadMultiply
    case keypadPlus

    // MARK: - Misc

    case escape
    case delete
    case forwardDelete
    case help
    case volumeUp
    case volumeDown
    case mute

    // MARK: - Initializers

	public init?(string: String) {
		switch string.lowercased() {
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
		case "one", "1": self = .one
		case "two", "2": self = .two
		case "three", "3": self = .three
		case "four", "4": self = .four
		case "six", "6": self = .six
		case "five", "5": self = .five
		case "equal", "=": self = .equal
		case "nine", "9": self = .nine
		case "seven", "7": self = .seven
		case "minus", "-": self = .minus
		case "eight", "8": self = .eight
		case "zero", "0": self = .zero
		case "rightBracket", "]": self = .rightBracket
		case "o": self = .o
		case "u": self = .u
		case "leftBracket", "[": self = .leftBracket
		case "i": self = .i
		case "p": self = .p
		case "l": self = .l
		case "j": self = .j
		case "quote", "\"": self = .quote
		case "k": self = .k
		case "semicolon", ";": self = .semicolon
		case "backslash", "\\": self = .backslash
		case "comma", ",": self = .comma
		case "slash", "/": self = .slash
		case "n": self = .n
		case "m": self = .m
		case "period", ".": self = .period
		case "grave", "`", "ˋ", "｀": self = .grave
		case "keypaddecimal": self = .keypadDecimal
		case "keypadmultiply": self = .keypadMultiply
		case "keypadplus": self = .keypadPlus
		case "keypadclear", "⌧": self = .keypadClear
		case "keypaddivide": self = .keypadDivide
		case "keypadenter": self = .keypadEnter
		case "keypadminus": self = .keypadMinus
		case "keypadequals": self = .keypadEquals
		case "keypad0": self = .keypad0
		case "keypad1": self = .keypad1
		case "keypad2": self = .keypad2
		case "keypad3": self = .keypad3
		case "keypad4": self = .keypad4
		case "keypad5": self = .keypad5
		case "keypad6": self = .keypad6
		case "keypad7": self = .keypad7
		case "keypad8": self = .keypad8
		case "keypad9": self = .keypad9
		case "return", "\r", "↩︎", "⏎", "⮐": self = .return
		case "tab", "\t", "⇥": self = .tab
		case "space", " ", "␣": self = .space
		case "delete", "⌫": self = .delete
		case "escape", "⎋": self = .escape
		case "command", "⌘", "": self = .command
		case "shift", "⇧": self = .shift
		case "capslock", "⇪": self = .capsLock
		case "option", "⌥": self = .option
		case "control", "⌃": self = .control
		case "rightcommand": self = .rightCommand
		case "rightshift": self = .rightShift
		case "rightoption": self = .rightOption
		case "rightcontrol": self = .rightControl
		case "function", "fn": self = .function
		case "f17", "F17": self = .f17
		case "volumeup", "🔊": self = .volumeUp
		case "volumedown", "🔉": self = .volumeDown
		case "mute", "🔇": self = .mute
		case "f18", "F18": self = .f18
		case "f19", "F19": self = .f19
		case "f20", "F20": self = .f20
		case "f5", "F5": self = .f5
		case "f6", "F6": self = .f6
		case "f7", "F7": self = .f7
		case "f3", "F3": self = .f3
		case "f8", "F8": self = .f8
		case "f9", "F9": self = .f9
		case "f11", "F11": self = .f11
		case "f13", "F13": self = .f13
		case "f16", "F16": self = .f16
		case "f14", "F14": self = .f14
		case "f10", "F10": self = .f10
		case "f12", "F12": self = .f12
		case "f15", "F15": self = .f15
		case "help", "?⃝": self = .help
		case "home", "↖": self = .home
		case "pageup", "⇞": self = .pageUp
		case "forwarddelete", "⌦": self = .forwardDelete
		case "f4", "F4": self = .f4
		case "end", "↘": self = .end
		case "f2", "F2": self = .f2
		case "pagedown", "⇟": self = .pageDown
		case "f1", "F1": self = .f1
		case "leftarrow", "←": self = .leftArrow
		case "rightarrow", "→": self = .rightArrow
		case "downarrow", "↓": self = .downArrow
		case "uparrow", "↑": self = .upArrow
		default: return nil
		}
	}

	public init?(carbonKeyCode: UInt32) {
		switch carbonKeyCode {
		case UInt32(kVK_ANSI_A): self = .a
		case UInt32(kVK_ANSI_S): self = .s
		case UInt32(kVK_ANSI_D): self = .d
		case UInt32(kVK_ANSI_F): self = .f
		case UInt32(kVK_ANSI_H): self = .h
		case UInt32(kVK_ANSI_G): self = .g
		case UInt32(kVK_ANSI_Z): self = .z
		case UInt32(kVK_ANSI_X): self = .x
		case UInt32(kVK_ANSI_C): self = .c
		case UInt32(kVK_ANSI_V): self = .v
		case UInt32(kVK_ANSI_B): self = .b
		case UInt32(kVK_ANSI_Q): self = .q
		case UInt32(kVK_ANSI_W): self = .w
		case UInt32(kVK_ANSI_E): self = .e
		case UInt32(kVK_ANSI_R): self = .r
		case UInt32(kVK_ANSI_Y): self = .y
		case UInt32(kVK_ANSI_T): self = .t
		case UInt32(kVK_ANSI_1): self = .one
		case UInt32(kVK_ANSI_2): self = .two
		case UInt32(kVK_ANSI_3): self = .three
		case UInt32(kVK_ANSI_4): self = .four
		case UInt32(kVK_ANSI_6): self = .six
		case UInt32(kVK_ANSI_5): self = .five
		case UInt32(kVK_ANSI_Equal): self = .equal
		case UInt32(kVK_ANSI_9): self = .nine
		case UInt32(kVK_ANSI_7): self = .seven
		case UInt32(kVK_ANSI_Minus): self = .minus
		case UInt32(kVK_ANSI_8): self = .eight
		case UInt32(kVK_ANSI_0): self = .zero
		case UInt32(kVK_ANSI_RightBracket): self = .rightBracket
		case UInt32(kVK_ANSI_O): self = .o
		case UInt32(kVK_ANSI_U): self = .u
		case UInt32(kVK_ANSI_LeftBracket): self = .leftBracket
		case UInt32(kVK_ANSI_I): self = .i
		case UInt32(kVK_ANSI_P): self = .p
		case UInt32(kVK_ANSI_L): self = .l
		case UInt32(kVK_ANSI_J): self = .j
		case UInt32(kVK_ANSI_Quote): self = .quote
		case UInt32(kVK_ANSI_K): self = .k
		case UInt32(kVK_ANSI_Semicolon): self = .semicolon
		case UInt32(kVK_ANSI_Backslash): self = .backslash
		case UInt32(kVK_ANSI_Comma): self = .comma
		case UInt32(kVK_ANSI_Slash): self = .slash
		case UInt32(kVK_ANSI_N): self = .n
		case UInt32(kVK_ANSI_M): self = .m
		case UInt32(kVK_ANSI_Period): self = .period
		case UInt32(kVK_ANSI_Grave): self = .grave
		case UInt32(kVK_ANSI_KeypadDecimal): self = .keypadDecimal
		case UInt32(kVK_ANSI_KeypadMultiply): self = .keypadMultiply
		case UInt32(kVK_ANSI_KeypadPlus): self = .keypadPlus
		case UInt32(kVK_ANSI_KeypadClear): self = .keypadClear
		case UInt32(kVK_ANSI_KeypadDivide): self = .keypadDivide
		case UInt32(kVK_ANSI_KeypadEnter): self = .keypadEnter
		case UInt32(kVK_ANSI_KeypadMinus): self = .keypadMinus
		case UInt32(kVK_ANSI_KeypadEquals): self = .keypadEquals
		case UInt32(kVK_ANSI_Keypad0): self = .keypad0
		case UInt32(kVK_ANSI_Keypad1): self = .keypad1
		case UInt32(kVK_ANSI_Keypad2): self = .keypad2
		case UInt32(kVK_ANSI_Keypad3): self = .keypad3
		case UInt32(kVK_ANSI_Keypad4): self = .keypad4
		case UInt32(kVK_ANSI_Keypad5): self = .keypad5
		case UInt32(kVK_ANSI_Keypad6): self = .keypad6
		case UInt32(kVK_ANSI_Keypad7): self = .keypad7
		case UInt32(kVK_ANSI_Keypad8): self = .keypad8
		case UInt32(kVK_ANSI_Keypad9): self = .keypad9
		case UInt32(kVK_Return): self = .`return`
		case UInt32(kVK_Tab): self = .tab
		case UInt32(kVK_Space): self = .space
		case UInt32(kVK_Delete): self = .delete
		case UInt32(kVK_Escape): self = .escape
		case UInt32(kVK_Command): self = .command
		case UInt32(kVK_Shift): self = .shift
		case UInt32(kVK_CapsLock): self = .capsLock
		case UInt32(kVK_Option): self = .option
		case UInt32(kVK_Control): self = .control
		case UInt32(kVK_RightCommand): self = .rightCommand
		case UInt32(kVK_RightShift): self = .rightShift
		case UInt32(kVK_RightOption): self = .rightOption
		case UInt32(kVK_RightControl): self = .rightControl
		case UInt32(kVK_Function): self = .function
		case UInt32(kVK_F17): self = .f17
		case UInt32(kVK_VolumeUp): self = .volumeUp
		case UInt32(kVK_VolumeDown): self = .volumeDown
		case UInt32(kVK_Mute): self = .mute
		case UInt32(kVK_F18): self = .f18
		case UInt32(kVK_F19): self = .f19
		case UInt32(kVK_F20): self = .f20
		case UInt32(kVK_F5): self = .f5
		case UInt32(kVK_F6): self = .f6
		case UInt32(kVK_F7): self = .f7
		case UInt32(kVK_F3): self = .f3
		case UInt32(kVK_F8): self = .f8
		case UInt32(kVK_F9): self = .f9
		case UInt32(kVK_F11): self = .f11
		case UInt32(kVK_F13): self = .f13
		case UInt32(kVK_F16): self = .f16
		case UInt32(kVK_F14): self = .f14
		case UInt32(kVK_F10): self = .f10
		case UInt32(kVK_F12): self = .f12
		case UInt32(kVK_F15): self = .f15
		case UInt32(kVK_Help): self = .help
		case UInt32(kVK_Home): self = .home
		case UInt32(kVK_PageUp): self = .pageUp
		case UInt32(kVK_ForwardDelete): self = .forwardDelete
		case UInt32(kVK_F4): self = .f4
		case UInt32(kVK_End): self = .end
		case UInt32(kVK_F2): self = .f2
		case UInt32(kVK_PageDown): self = .pageDown
		case UInt32(kVK_F1): self = .f1
		case UInt32(kVK_LeftArrow): self = .leftArrow
		case UInt32(kVK_RightArrow): self = .rightArrow
		case UInt32(kVK_DownArrow): self = .downArrow
		case UInt32(kVK_UpArrow): self = .upArrow
		default: return nil
		}
	}
	
	public var carbonKeyCode: UInt32 {
		switch self {
		case .a: return UInt32(kVK_ANSI_A)
		case .s: return UInt32(kVK_ANSI_S)
		case .d: return UInt32(kVK_ANSI_D)
		case .f: return UInt32(kVK_ANSI_F)
		case .h: return UInt32(kVK_ANSI_H)
		case .g: return UInt32(kVK_ANSI_G)
		case .z: return UInt32(kVK_ANSI_Z)
		case .x: return UInt32(kVK_ANSI_X)
		case .c: return UInt32(kVK_ANSI_C)
		case .v: return UInt32(kVK_ANSI_V)
		case .b: return UInt32(kVK_ANSI_B)
		case .q: return UInt32(kVK_ANSI_Q)
		case .w: return UInt32(kVK_ANSI_W)
		case .e: return UInt32(kVK_ANSI_E)
		case .r: return UInt32(kVK_ANSI_R)
		case .y: return UInt32(kVK_ANSI_Y)
		case .t: return UInt32(kVK_ANSI_T)
		case .one: return UInt32(kVK_ANSI_1)
		case .two: return UInt32(kVK_ANSI_2)
		case .three: return UInt32(kVK_ANSI_3)
		case .four: return UInt32(kVK_ANSI_4)
		case .six: return UInt32(kVK_ANSI_6)
		case .five: return UInt32(kVK_ANSI_5)
		case .equal: return UInt32(kVK_ANSI_Equal)
		case .nine: return UInt32(kVK_ANSI_9)
		case .seven: return UInt32(kVK_ANSI_7)
		case .minus: return UInt32(kVK_ANSI_Minus)
		case .eight: return UInt32(kVK_ANSI_8)
		case .zero: return UInt32(kVK_ANSI_0)
		case .rightBracket: return UInt32(kVK_ANSI_RightBracket)
		case .o: return UInt32(kVK_ANSI_O)
		case .u: return UInt32(kVK_ANSI_U)
		case .leftBracket: return UInt32(kVK_ANSI_LeftBracket)
		case .i: return UInt32(kVK_ANSI_I)
		case .p: return UInt32(kVK_ANSI_P)
		case .l: return UInt32(kVK_ANSI_L)
		case .j: return UInt32(kVK_ANSI_J)
		case .quote: return UInt32(kVK_ANSI_Quote)
		case .k: return UInt32(kVK_ANSI_K)
		case .semicolon: return UInt32(kVK_ANSI_Semicolon)
		case .backslash: return UInt32(kVK_ANSI_Backslash)
		case .comma: return UInt32(kVK_ANSI_Comma)
		case .slash: return UInt32(kVK_ANSI_Slash)
		case .n: return UInt32(kVK_ANSI_N)
		case .m: return UInt32(kVK_ANSI_M)
		case .period: return UInt32(kVK_ANSI_Period)
		case .grave: return UInt32(kVK_ANSI_Grave)
		case .keypadDecimal: return UInt32(kVK_ANSI_KeypadDecimal)
		case .keypadMultiply: return UInt32(kVK_ANSI_KeypadMultiply)
		case .keypadPlus: return UInt32(kVK_ANSI_KeypadPlus)
		case .keypadClear: return UInt32(kVK_ANSI_KeypadClear)
		case .keypadDivide: return UInt32(kVK_ANSI_KeypadDivide)
		case .keypadEnter: return UInt32(kVK_ANSI_KeypadEnter)
		case .keypadMinus: return UInt32(kVK_ANSI_KeypadMinus)
		case .keypadEquals: return UInt32(kVK_ANSI_KeypadEquals)
		case .keypad0: return UInt32(kVK_ANSI_Keypad0)
		case .keypad1: return UInt32(kVK_ANSI_Keypad1)
		case .keypad2: return UInt32(kVK_ANSI_Keypad2)
		case .keypad3: return UInt32(kVK_ANSI_Keypad3)
		case .keypad4: return UInt32(kVK_ANSI_Keypad4)
		case .keypad5: return UInt32(kVK_ANSI_Keypad5)
		case .keypad6: return UInt32(kVK_ANSI_Keypad6)
		case .keypad7: return UInt32(kVK_ANSI_Keypad7)
		case .keypad8: return UInt32(kVK_ANSI_Keypad8)
		case .keypad9: return UInt32(kVK_ANSI_Keypad9)
		case .`return`: return UInt32(kVK_Return)
		case .tab: return UInt32(kVK_Tab)
		case .space: return UInt32(kVK_Space)
		case .delete: return UInt32(kVK_Delete)
		case .escape: return UInt32(kVK_Escape)
		case .command: return UInt32(kVK_Command)
		case .shift: return UInt32(kVK_Shift)
		case .capsLock: return UInt32(kVK_CapsLock)
		case .option: return UInt32(kVK_Option)
		case .control: return UInt32(kVK_Control)
		case .rightCommand: return UInt32(kVK_RightCommand)
		case .rightShift: return UInt32(kVK_RightShift)
		case .rightOption: return UInt32(kVK_RightOption)
		case .rightControl: return UInt32(kVK_RightControl)
		case .function: return UInt32(kVK_Function)
		case .f17: return UInt32(kVK_F17)
		case .volumeUp: return UInt32(kVK_VolumeUp)
		case .volumeDown: return UInt32(kVK_VolumeDown)
		case .mute: return UInt32(kVK_Mute)
		case .f18: return UInt32(kVK_F18)
		case .f19: return UInt32(kVK_F19)
		case .f20: return UInt32(kVK_F20)
		case .f5: return UInt32(kVK_F5)
		case .f6: return UInt32(kVK_F6)
		case .f7: return UInt32(kVK_F7)
		case .f3: return UInt32(kVK_F3)
		case .f8: return UInt32(kVK_F8)
		case .f9: return UInt32(kVK_F9)
		case .f11: return UInt32(kVK_F11)
		case .f13: return UInt32(kVK_F13)
		case .f16: return UInt32(kVK_F16)
		case .f14: return UInt32(kVK_F14)
		case .f10: return UInt32(kVK_F10)
		case .f12: return UInt32(kVK_F12)
		case .f15: return UInt32(kVK_F15)
		case .help: return UInt32(kVK_Help)
		case .home: return UInt32(kVK_Home)
		case .pageUp: return UInt32(kVK_PageUp)
		case .forwardDelete: return UInt32(kVK_ForwardDelete)
		case .f4: return UInt32(kVK_F4)
		case .end: return UInt32(kVK_End)
		case .f2: return UInt32(kVK_F2)
		case .pageDown: return UInt32(kVK_PageDown)
		case .f1: return UInt32(kVK_F1)
		case .leftArrow: return UInt32(kVK_LeftArrow)
		case .rightArrow: return UInt32(kVK_RightArrow)
		case .downArrow: return UInt32(kVK_DownArrow)
		case .upArrow: return UInt32(kVK_UpArrow)
		}
	}
}

extension Key: CustomStringConvertible {
    public var description: String {
        switch  self {
        case .a: return "A"
        case .s: return "S"
        case .d: return "D"
        case .f: return "F"
        case .h: return "H"
        case .g: return "G"
        case .z: return "Z"
        case .x: return "X"
        case .c: return "C"
        case .v: return "V"
        case .b: return "B"
        case .q: return "Q"
        case .w: return "W"
        case .e: return "E"
        case .r: return "R"
        case .y: return "Y"
        case .t: return "T"
        case .one, .keypad1: return "1"
        case .two, .keypad2: return "2"
        case .three, .keypad3: return "3"
        case .four, .keypad4: return "4"
        case .six, .keypad6: return "6"
        case .five, .keypad5: return "5"
        case .equal: return "="
        case .nine, .keypad9: return "9"
        case .seven, .keypad7: return "7"
        case .minus: return "-"
        case .eight, .keypad8: return "8"
        case .zero, .keypad0: return "0"
        case .rightBracket: return "]"
        case .o: return "O"
        case .u: return "U"
        case .leftBracket: return "["
        case .i: return "I"
        case .p: return "P"
        case .l: return "L"
        case .j: return "J"
        case .quote: return "\""
        case .k: return "K"
        case .semicolon: return ";"
        case .backslash: return "\\"
        case .comma: return ","
        case .slash: return "/"
        case .n: return "N"
        case .m: return "M"
        case .period: return "."
        case .grave: return "`"
        case .keypadDecimal: return "."
        case .keypadMultiply: return "𝗑"
        case .keypadPlus: return "+"
        case .keypadClear: return "⌧"
        case .keypadDivide: return "/"
        case .keypadEnter: return "↩︎"
        case .keypadMinus: return "-"
        case .keypadEquals: return "="
        case .`return`: return "↩︎"
        case .tab: return "⇥"
        case .space: return "␣"
        case .delete: return "⌫"
        case .escape: return "⎋"
        case .command, .rightCommand: return "⌘"
        case .shift, .rightShift: return "⇧"
        case .capsLock: return "⇪"
        case .option, .rightOption: return "⌥"
        case .control, .rightControl: return "⌃"
        case .function: return "fn"
        case .f17: return "F17"
        case .volumeUp: return "🔊"
        case .volumeDown: return "🔉"
        case .mute: return "🔇"
        case .f18: return "F18"
        case .f19: return "F19"
        case .f20: return "F20"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f3: return "F3"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f11: return "F11"
        case .f13: return "F13"
        case .f16: return "F16"
        case .f14: return "F14"
        case .f10: return "F10"
        case .f12: return "F12"
        case .f15: return "F15"
        case .help: return "?⃝"
        case .home: return "↖"
        case .pageUp: return "⇞"
        case .forwardDelete: return "⌦"
        case .f4: return "F4"
        case .end: return "↘"
        case .f2: return "F2"
        case .pageDown: return "⇟"
        case .f1: return "F1"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .downArrow: return "↓"
        case .upArrow: return "↑"
        }
    }
}
