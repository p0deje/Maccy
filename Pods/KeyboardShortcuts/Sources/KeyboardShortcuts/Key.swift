import Cocoa
import Carbon.HIToolbox

extension KeyboardShortcuts {
	// swiftlint:disable identifier_name
	/// Represents a key on the keyboard.
	public enum Key: RawRepresentable {
		// MARK: Letters
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
		// swiftlint:enable identifier_name

		// MARK: Numbers
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

		// MARK: Modifiers
		case capsLock
		case shift
		case function
		case control
		case option
		case command
		case rightCommand
		case rightOption
		case rightControl
		case rightShift

		// MARK: Miscellaneous
		case `return`
		case backslash
		case backtick
		case comma
		case equal
		case minus
		case period
		case quote
		case semicolon
		case slash
		case space
		case tab
		case leftBracket
		case rightBracket
		case pageUp
		case pageDown
		case home
		case end
		case upArrow
		case rightArrow
		case downArrow
		case leftArrow
		case escape
		case delete
		case deleteForward
		case help
		case mute
		case volumeUp
		case volumeDown

		// MARK: Function
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

		// MARK: Keypad
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

		// MARK: Initializers

		/// Create a `Key` from a key code.
		public init?(rawValue: Int) {
			switch rawValue {
			case kVK_ANSI_A:
				self = .a
			case kVK_ANSI_B:
				self = .b
			case kVK_ANSI_C:
				self = .c
			case kVK_ANSI_D:
				self = .d
			case kVK_ANSI_E:
				self = .e
			case kVK_ANSI_F:
				self = .f
			case kVK_ANSI_G:
				self = .g
			case kVK_ANSI_H:
				self = .h
			case kVK_ANSI_I:
				self = .i
			case kVK_ANSI_J:
				self = .j
			case kVK_ANSI_K:
				self = .k
			case kVK_ANSI_L:
				self = .l
			case kVK_ANSI_M:
				self = .m
			case kVK_ANSI_N:
				self = .n
			case kVK_ANSI_O:
				self = .o
			case kVK_ANSI_P:
				self = .p
			case kVK_ANSI_Q:
				self = .q
			case kVK_ANSI_R:
				self = .r
			case kVK_ANSI_S:
				self = .s
			case kVK_ANSI_T:
				self = .t
			case kVK_ANSI_U:
				self = .u
			case kVK_ANSI_V:
				self = .v
			case kVK_ANSI_W:
				self = .w
			case kVK_ANSI_X:
				self = .x
			case kVK_ANSI_Y:
				self = .y
			case kVK_ANSI_Z:
				self = .z
			case kVK_ANSI_0:
				self = .zero
			case kVK_ANSI_1:
				self = .one
			case kVK_ANSI_2:
				self = .two
			case kVK_ANSI_3:
				self = .three
			case kVK_ANSI_4:
				self = .four
			case kVK_ANSI_5:
				self = .five
			case kVK_ANSI_6:
				self = .six
			case kVK_ANSI_7:
				self = .seven
			case kVK_ANSI_8:
				self = .eight
			case kVK_ANSI_9:
				self = .nine
			case kVK_CapsLock:
				self = .capsLock
			case kVK_Shift:
				self = .shift
			case kVK_Function:
				self = .function
			case kVK_Control:
				self = .control
			case kVK_Option:
				self = .option
			case kVK_Command:
				self = .command
			case kVK_RightCommand:
				self = .rightCommand
			case kVK_RightOption:
				self = .rightOption
			case kVK_RightControl:
				self = .rightControl
			case kVK_RightShift:
				self = .rightShift
			case kVK_Return:
				self = .`return`
			case kVK_ANSI_Backslash:
				self = .backslash
			case kVK_ANSI_Grave:
				self = .backtick
			case kVK_ANSI_Comma:
				self = .comma
			case kVK_ANSI_Equal:
				self = .equal
			case kVK_ANSI_Minus:
				self = .minus
			case kVK_ANSI_Period:
				self = .period
			case kVK_ANSI_Quote:
				self = .quote
			case kVK_ANSI_Semicolon:
				self = .semicolon
			case kVK_ANSI_Slash:
				self = .slash
			case kVK_Space:
				self = .space
			case kVK_Tab:
				self = .tab
			case kVK_ANSI_LeftBracket:
				self = .leftBracket
			case kVK_ANSI_RightBracket:
				self = .rightBracket
			case kVK_PageUp:
				self = .pageUp
			case kVK_PageDown:
				self = .pageDown
			case kVK_Home:
				self = .home
			case kVK_End:
				self = .end
			case kVK_UpArrow:
				self = .upArrow
			case kVK_RightArrow:
				self = .rightArrow
			case kVK_DownArrow:
				self = .downArrow
			case kVK_LeftArrow:
				self = .leftArrow
			case kVK_Escape:
				self = .escape
			case kVK_Delete:
				self = .delete
			case kVK_ForwardDelete:
				self = .deleteForward
			case kVK_Help:
				self = .help
			case kVK_Mute:
				self = .mute
			case kVK_VolumeUp:
				self = .volumeUp
			case kVK_VolumeDown:
				self = .volumeDown
			case kVK_F1:
				self = .f1
			case kVK_F2:
				self = .f2
			case kVK_F3:
				self = .f3
			case kVK_F4:
				self = .f4
			case kVK_F5:
				self = .f5
			case kVK_F6:
				self = .f6
			case kVK_F7:
				self = .f7
			case kVK_F8:
				self = .f8
			case kVK_F9:
				self = .f9
			case kVK_F10:
				self = .f10
			case kVK_F11:
				self = .f11
			case kVK_F12:
				self = .f12
			case kVK_F13:
				self = .f13
			case kVK_F14:
				self = .f14
			case kVK_F15:
				self = .f15
			case kVK_F16:
				self = .f16
			case kVK_F17:
				self = .f17
			case kVK_F18:
				self = .f18
			case kVK_F19:
				self = .f19
			case kVK_F20:
				self = .f20
			case kVK_ANSI_Keypad0:
				self = .keypad0
			case kVK_ANSI_Keypad1:
				self = .keypad1
			case kVK_ANSI_Keypad2:
				self = .keypad2
			case kVK_ANSI_Keypad3:
				self = .keypad3
			case kVK_ANSI_Keypad4:
				self = .keypad4
			case kVK_ANSI_Keypad5:
				self = .keypad5
			case kVK_ANSI_Keypad6:
				self = .keypad6
			case kVK_ANSI_Keypad7:
				self = .keypad7
			case kVK_ANSI_Keypad8:
				self = .keypad8
			case kVK_ANSI_Keypad9:
				self = .keypad9
			case kVK_ANSI_KeypadClear:
				self = .keypadClear
			case kVK_ANSI_KeypadDecimal:
				self = .keypadDecimal
			case kVK_ANSI_KeypadDivide:
				self = .keypadDivide
			case kVK_ANSI_KeypadEnter:
				self = .keypadEnter
			case kVK_ANSI_KeypadEquals:
				self = .keypadEquals
			case kVK_ANSI_KeypadMinus:
				self = .keypadMinus
			case kVK_ANSI_KeypadMultiply:
				self = .keypadMultiply
			case kVK_ANSI_KeypadPlus:
				self = .keypadPlus
			default:
				return nil
			}
		}

		// MARK: Properties

		/// The raw key code.
		public var rawValue: Int {
			switch self {
			case .a:
				return kVK_ANSI_A
			case .b:
				return kVK_ANSI_B
			case .c:
				return kVK_ANSI_C
			case .d:
				return kVK_ANSI_D
			case .e:
				return kVK_ANSI_E
			case .f:
				return kVK_ANSI_F
			case .g:
				return kVK_ANSI_G
			case .h:
				return kVK_ANSI_H
			case .i:
				return kVK_ANSI_I
			case .j:
				return kVK_ANSI_J
			case .k:
				return kVK_ANSI_K
			case .l:
				return kVK_ANSI_L
			case .m:
				return kVK_ANSI_M
			case .n:
				return kVK_ANSI_N
			case .o:
				return kVK_ANSI_O
			case .p:
				return kVK_ANSI_P
			case .q:
				return kVK_ANSI_Q
			case .r:
				return kVK_ANSI_R
			case .s:
				return kVK_ANSI_S
			case .t:
				return kVK_ANSI_T
			case .u:
				return kVK_ANSI_U
			case .v:
				return kVK_ANSI_V
			case .w:
				return kVK_ANSI_W
			case .x:
				return kVK_ANSI_X
			case .y:
				return kVK_ANSI_Y
			case .z:
				return kVK_ANSI_Z
			case .zero:
				return kVK_ANSI_0
			case .one:
				return kVK_ANSI_1
			case .two:
				return kVK_ANSI_2
			case .three:
				return kVK_ANSI_3
			case .four:
				return kVK_ANSI_4
			case .five:
				return kVK_ANSI_5
			case .six:
				return kVK_ANSI_6
			case .seven:
				return kVK_ANSI_7
			case .eight:
				return kVK_ANSI_8
			case .nine:
				return kVK_ANSI_9
			case .capsLock:
				return kVK_CapsLock
			case .shift:
				return kVK_Shift
			case .function:
				return kVK_Function
			case .control:
				return kVK_Control
			case .option:
				return kVK_Option
			case .command:
				return kVK_Command
			case .rightCommand:
				return kVK_RightCommand
			case .rightOption:
				return kVK_RightOption
			case .rightControl:
				return kVK_RightControl
			case .rightShift:
				return kVK_RightShift
			case .`return`:
				return kVK_Return
			case .backslash:
				return kVK_ANSI_Backslash
			case .backtick:
				return kVK_ANSI_Grave
			case .comma:
				return kVK_ANSI_Comma
			case .equal:
				return kVK_ANSI_Equal
			case .minus:
				return kVK_ANSI_Minus
			case .period:
				return kVK_ANSI_Period
			case .quote:
				return kVK_ANSI_Quote
			case .semicolon:
				return kVK_ANSI_Semicolon
			case .slash:
				return kVK_ANSI_Slash
			case .space:
				return kVK_Space
			case .tab:
				return kVK_Tab
			case .leftBracket:
				return kVK_ANSI_LeftBracket
			case .rightBracket:
				return kVK_ANSI_RightBracket
			case .pageUp:
				return kVK_PageUp
			case .pageDown:
				return kVK_PageDown
			case .home:
				return kVK_Home
			case .end:
				return kVK_End
			case .upArrow:
				return kVK_UpArrow
			case .rightArrow:
				return kVK_RightArrow
			case .downArrow:
				return kVK_DownArrow
			case .leftArrow:
				return kVK_LeftArrow
			case .escape:
				return kVK_Escape
			case .delete:
				return kVK_Delete
			case .deleteForward:
				return kVK_ForwardDelete
			case .help:
				return kVK_Help
			case .mute:
				return kVK_Mute
			case .volumeUp:
				return kVK_VolumeUp
			case .volumeDown:
				return kVK_VolumeDown
			case .f1:
				return kVK_F1
			case .f2:
				return kVK_F2
			case .f3:
				return kVK_F3
			case .f4:
				return kVK_F4
			case .f5:
				return kVK_F5
			case .f6:
				return kVK_F6
			case .f7:
				return kVK_F7
			case .f8:
				return kVK_F8
			case .f9:
				return kVK_F9
			case .f10:
				return kVK_F10
			case .f11:
				return kVK_F11
			case .f12:
				return kVK_F12
			case .f13:
				return kVK_F13
			case .f14:
				return kVK_F14
			case .f15:
				return kVK_F15
			case .f16:
				return kVK_F16
			case .f17:
				return kVK_F17
			case .f18:
				return kVK_F18
			case .f19:
				return kVK_F19
			case .f20:
				return kVK_F20
			case .keypad0:
				return kVK_ANSI_Keypad0
			case .keypad1:
				return kVK_ANSI_Keypad1
			case .keypad2:
				return kVK_ANSI_Keypad2
			case .keypad3:
				return kVK_ANSI_Keypad3
			case .keypad4:
				return kVK_ANSI_Keypad4
			case .keypad5:
				return kVK_ANSI_Keypad5
			case .keypad6:
				return kVK_ANSI_Keypad6
			case .keypad7:
				return kVK_ANSI_Keypad7
			case .keypad8:
				return kVK_ANSI_Keypad8
			case .keypad9:
				return kVK_ANSI_Keypad9
			case .keypadClear:
				return kVK_ANSI_KeypadClear
			case .keypadDecimal:
				return kVK_ANSI_KeypadDecimal
			case .keypadDivide:
				return kVK_ANSI_KeypadDivide
			case .keypadEnter:
				return kVK_ANSI_KeypadEnter
			case .keypadEquals:
				return kVK_ANSI_KeypadEquals
			case .keypadMinus:
				return kVK_ANSI_KeypadMinus
			case .keypadMultiply:
				return kVK_ANSI_KeypadMultiply
			case .keypadPlus:
				return kVK_ANSI_KeypadPlus
			}
		}
	}
}

extension KeyboardShortcuts.Key {
	/// All the function keys.
	static let functionKeys: Set<Self> = [
		.f1,
		.f2,
		.f3,
		.f4,
		.f5,
		.f6,
		.f7,
		.f8,
		.f9,
		.f10,
		.f11,
		.f12,
		.f13,
		.f14,
		.f15,
		.f16,
		.f17,
		.f18,
		.f19,
		.f20
	]

	/// Returns true if the key is a function key. For example, `F1`.
	var isFunctionKey: Bool { Self.functionKeys.contains(self) }
}
