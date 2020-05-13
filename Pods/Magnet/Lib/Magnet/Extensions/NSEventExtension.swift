// 
//  NSEventExtension.swift
//
//  Magnet
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
// 
//  Copyright © 2015-2020 Clipy Project.
//

import Cocoa
import Carbon

public extension NSEvent.ModifierFlags {
    var containsSupportModifiers: Bool {
        return contains(.command) || contains(.option) || contains(.control) || contains(.shift) || contains(.function)
    }
    var isSingleFlags: Bool {
        let commandSelected = contains(.command)
        let optionSelected = contains(.option)
        let controlSelected = contains(.control)
        let shiftSelected = contains(.shift)
        return [commandSelected, optionSelected, controlSelected, shiftSelected].trueCount == 1
    }

    func filterUnsupportModifiers() -> NSEvent.ModifierFlags {
        var filterdModifierFlags = NSEvent.ModifierFlags(rawValue: 0)
        if contains(.command) {
            filterdModifierFlags.insert(.command)
        }
        if contains(.option) {
            filterdModifierFlags.insert(.option)
        }
        if contains(.control) {
            filterdModifierFlags.insert(.control)
        }
        if contains(.shift) {
            filterdModifierFlags.insert(.shift)
        }
        return filterdModifierFlags
    }

    func filterNotShiftModifiers() -> NSEvent.ModifierFlags {
        guard contains(.shift) else { return NSEvent.ModifierFlags(rawValue: 0) }
        return .shift
    }

    func carbonModifiers(isSupportFunctionKey: Bool = false) -> Int {
        var carbonModifiers: Int = 0
        if contains(.command) {
            carbonModifiers |= cmdKey
        }
        if contains(.option) {
            carbonModifiers |= optionKey
        }
        if contains(.control) {
            carbonModifiers |= controlKey
        }
        if contains(.shift) {
            carbonModifiers |= shiftKey
        }
        if contains(.function) && isSupportFunctionKey {
            carbonModifiers |= Int(NSEvent.ModifierFlags.function.rawValue)
        }
        return carbonModifiers
    }

    func keyEquivalentStrings() -> [String] {
        var strings = [String]()
        if contains(.control) {
            strings.append("⌃")
        }
        if contains(.option) {
            strings.append("⌥")
        }
        if contains(.shift) {
            strings.append("⇧")
        }
        if contains(.command) {
            strings.append("⌘")
        }
        return strings
    }
}
