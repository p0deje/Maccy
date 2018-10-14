//
//  HotKey.swift
//  HotKey
//
//  Created by Sam Soffes on 7/21/17.
//  Copyright © 2017 Sam Soffes. All rights reserved.
//

import AppKit
import Carbon

public final class HotKey {

	// MARK: - Types

	public typealias Handler = () -> Void

	
	// MARK: - Properties

	let identifier = UUID()

	public let keyCombo: KeyCombo
	public var keyDownHandler: Handler?
	public var keyUpHandler: Handler?
    public var isPaused = false {
        didSet {
            if isPaused {
                HotKeysController.unregister(self)
            } else {
                HotKeysController.register(self)
            }
        }
    }


	// MARK: - Initializers

	public init(keyCombo: KeyCombo, keyDownHandler: Handler? = nil, keyUpHandler: Handler? = nil) {
		self.keyCombo = keyCombo
		self.keyDownHandler = keyDownHandler
		self.keyUpHandler = keyUpHandler

		HotKeysController.register(self)
	}

	public convenience init(carbonKeyCode: UInt32, carbonModifiers: UInt32, keyDownHandler: Handler? = nil, keyUpHandler: Handler? = nil) {
		let keyCombo = KeyCombo(carbonKeyCode: carbonKeyCode, carbonModifiers: carbonModifiers)
		self.init(keyCombo: keyCombo, keyDownHandler: keyDownHandler, keyUpHandler: keyUpHandler)
	}

	public convenience init(key: Key, modifiers: NSEvent.ModifierFlags, keyDownHandler: Handler? = nil, keyUpHandler: Handler? = nil) {
		let keyCombo = KeyCombo(key: key, modifiers: modifiers)
		self.init(keyCombo: keyCombo, keyDownHandler: keyDownHandler, keyUpHandler: keyUpHandler)
	}

	deinit {
		HotKeysController.unregister(self)
	}
}
