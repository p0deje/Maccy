// 
//  ModifierEventHandler.swift
//
//  Magnet
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
// 
//  Copyright © 2015-2020 Clipy Project.
//

import Cocoa

public final class ModifierEventHandler {

    // MARK: - Properties
    public var doubleTapped: ((NSEvent.ModifierFlags) -> Void)?

    private var tappingModifierFlags = NSEvent.ModifierFlags()
    private var isTappingMultiModifiers = false
    private var lastHandledEventTimestamp: TimeInterval?
    private let cleanTimeInterval: DispatchTimeInterval
    private let cleanQueue: DispatchQueue

    // MARK: - Initialize
    public init(cleanTimeInterval: DispatchTimeInterval = .milliseconds(300), cleanQueue: DispatchQueue = .main) {
        self.cleanTimeInterval = cleanTimeInterval
        self.cleanQueue = cleanQueue
    }

}

// MARK: - Handling
public extension ModifierEventHandler {
    func handleModifiersEvent(with modifierFlags: NSEvent.ModifierFlags, timestamp: TimeInterval) {
        guard lastHandledEventTimestamp != timestamp else { return }
        lastHandledEventTimestamp = timestamp

        handleDoubleTapModifierEvent(modifierFlags: modifierFlags)
    }

    private func handleDoubleTapModifierEvent(modifierFlags: NSEvent.ModifierFlags) {
        let tappedModifierFlags = modifierFlags.filterUnsupportModifiers()
        let commandTapped = tappedModifierFlags.contains(.command)
        let shiftTapped = tappedModifierFlags.contains(.shift)
        let controlTapped = tappedModifierFlags.contains(.control)
        let optionTapped = tappedModifierFlags.contains(.option)
        let tappedModifierCount = [commandTapped, shiftTapped, controlTapped, optionTapped].trueCount
        guard tappedModifierCount != 0 else { return }
        guard tappedModifierCount == 1 else {
            isTappingMultiModifiers = true
            return
        }
        guard !isTappingMultiModifiers else {
            isTappingMultiModifiers = false
            return
        }
        if (tappingModifierFlags.contains(.command) && commandTapped) ||
            (tappingModifierFlags.contains(.shift) && shiftTapped) ||
            (tappingModifierFlags.contains(.control) && controlTapped) ||
            (tappingModifierFlags.contains(.option) && optionTapped) {
            doubleTapped?(tappingModifierFlags)
            tappingModifierFlags = NSEvent.ModifierFlags()
        } else {
            tappingModifierFlags = tappedModifierFlags
        }

        // After a certain amount of time, the tapped modifier will be reset.
        cleanQueue.asyncAfter(deadline: .now() + cleanTimeInterval) { [weak self] in
            self?.tappingModifierFlags = NSEvent.ModifierFlags()
        }
    }
}
