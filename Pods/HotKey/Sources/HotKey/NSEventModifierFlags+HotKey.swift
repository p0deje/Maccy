//
//  NSEventModifierFlags+HotKey.swift
//  HotKey
//
//  Created by Sam Soffes on 7/21/17.
//  Copyright © 2017 Sam Soffes. All rights reserved.
//

import AppKit
import Carbon

extension NSEvent.ModifierFlags {
	public var carbonFlags: UInt32 {
		var carbonFlags: UInt32 = 0

		if contains(.command) {
			carbonFlags |= UInt32(cmdKey)
		}

		if contains(.option) {
			carbonFlags |= UInt32(optionKey)
		}

		if contains(.control) {
			carbonFlags |= UInt32(controlKey)
		}

		if contains(.shift) {
			carbonFlags |= UInt32(shiftKey)
		}

		return carbonFlags
	}

	public init(carbonFlags: UInt32) {
		self.init()

		if carbonFlags & UInt32(cmdKey) == UInt32(cmdKey) {
			insert(.command)
		}

		if carbonFlags & UInt32(optionKey) == UInt32(optionKey) {
			insert(.option)
		}

		if carbonFlags & UInt32(controlKey) == UInt32(controlKey) {
			insert(.control)
		}

		if carbonFlags & UInt32(shiftKey) == UInt32(shiftKey) {
			insert(.shift)
		}
	}
}
