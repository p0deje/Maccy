// 
//  IntExtension.swift
//
//  Magnet
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
// 
//  Copyright © 2015-2020 Clipy Project.
//

import Cocoa
import Carbon

public extension Int {
    @available(*, deprecated, renamed: "convertSupportCocoaModifiers")
    func convertSupportCococaModifiers() -> NSEvent.ModifierFlags {
        return convertSupportCocoaModifiers()
    }

    func convertSupportCocoaModifiers() -> NSEvent.ModifierFlags {
        var cocoaFlags: NSEvent.ModifierFlags = NSEvent.ModifierFlags(rawValue: 0)
        if (self & cmdKey) != 0 {
            cocoaFlags.insert(.command)
        }
        if (self & optionKey) != 0 {
            cocoaFlags.insert(.option)
        }
        if (self & controlKey) != 0 {
            cocoaFlags.insert(.control)
        }
        if (self & shiftKey) != 0 {
            cocoaFlags.insert(.shift)
        }
        return cocoaFlags
    }
}
