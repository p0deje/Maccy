# Magnet
![CI](https://github.com/Clipy/Magnet/workflows/CI/badge.svg)
[![Release version](https://img.shields.io/github/release/Clipy/Magnet.svg)](https://github.com/Clipy/Magnet/releases/latest)
[![License: MIT](https://img.shields.io/github/license/Clipy/Magnet.svg)](https://github.com/Clipy/Magnet/blob/master/LICENSE)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![Version](https://img.shields.io/cocoapods/v/Magnet.svg)](http://cocoadocs.org/docsets/Magnet)
[![Platform](https://img.shields.io/cocoapods/p/Magnet.svg)](http://cocoadocs.org/docsets/Magnet)
[![SPM supported](https://img.shields.io/badge/SPM-supported-DE5C43.svg?style=flat)](https://swift.org/package-manager)

Customize global hotkeys in macOS. Supports usual hotkey and double tap hotkey like Alfred.app.

Also supports sandbox application.

## Usage
### CocoaPods
```
pod 'Magnet'
```

### Carthage
```
github "Clipy/Magnet"
```

## Upgrading from Magnet v2.x to v3.x
See [Upgrading from Magnet v2.x](/Documentation/Upgrading_Magnet_2.md)

## Example
### Register Normal hotkey
Add `⌘ + Control + B` hotkey.

```swift
if let keyCombo = KeyCombo(key: .b, cocoaModifiers: [.command, .control]]) {
   let hotKey = HotKey(identifier: "CommandControlB", keyCombo: keyCombo, target: self, action: #selector())
   hotKey.register() // or HotKeyCenter.shared.register(with: hotKey)
}
```

Or you can use closures.
```swift
if let keyCombo = KeyCombo(key: .b, cocoaModifiers: [.command, .control]) {
    let hotKey = HotKey(identifier: "CommandControlB", keyCombo: keyCombo) { hotKey in
        // Called when ⌘ + Control + B is pressed
    }
    hotKey.register()
}        
```

### Register Double tap hotkey
Add `⌘ double tap` hotkey.
```swift
if let keyCombo = KeyCombo(doubledCocoaModifiers: .command) {
   let hotKey = HotKey(identifier: "CommandDoubleTap", keyCombo: keyCombo, target: self, action: #selector())
   hotKey.register() // or HotKeyCenter.shared.register(with: hotKey)
}
```

Add `Control double tap` hotkey.
```swift
if let keyCombo = KeyCombo(doubledCarbonModifiers: controlKey) {
   let hotKey = HotKey(identifier: "ControlDoubleTap", keyCombo: keyCombo, target: self, action: #selector())
   hotKey.register() // or HotKeyCenter.shared.register(with: hotKey)
}
```

#### Support modifiers
Double tap hotkey only support following modifiers.
- Command Key
  - `NSEventModifierFlags.command` or `cmdKey`
- Shift Key
  - `NSEventModifierFlags.shift` or `shiftKey`
- Option Key
  - `NSEventModifierFlags.option` or `optionKey`
- Control Key
  - `NSEventModifierFlags.control` or `controlKey`

### Unregister hotkeys
```swift
HotKeyCenter.shared.unregisterAll()
```

or

```swift
HotKeyCenter.shared.unregisterHotKey(with: "identifier")
```

or

```swift
let hotKey = HotKey(identifier: "identifier", keyCombo: KeyCombo, target: self, action: #selector())
hotKey.unregister() // or HotKeyCenter.shared.unregister(with: hotKey)
```

## Dependencies
- [Sauce](https://github.com/Clipy/Sauce)

## How to Build
1. Move to the project root directory
2. Install dependency library with `carthage` or `git submodule`
3. `carthage checkout --use-submodules` or `git submodule update --init --recursive`
4. Open `Magnet.xcworkspace` on Xcode.
5. build.
