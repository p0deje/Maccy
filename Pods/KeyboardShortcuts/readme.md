<div align="center">
	<img width="900" src="https://github.com/sindresorhus/KeyboardShortcuts/raw/master/logo.png" alt="KeyboardShortcuts">
	<br>
</div>

This package lets you add support for user-customizable global keyboard shortcuts to your macOS app in minutes. It's fully sandbox and Mac App Store compatible. And it's used in production by [Dato](https://sindresorhus.com/dato), [Jiffy](https://sindresorhus.com/jiffy), [Plash](https://github.com/sindresorhus/Plash), and [Lungo](https://sindresorhus.com/lungo).

This package is still in its early days. I'm happy to accept more configurability and features. PR welcome! What you see here is just what I needed for my own apps.

<img src="https://github.com/sindresorhus/KeyboardShortcuts/raw/master/screenshot.png" width="532">

## Requirements

macOS 10.11+

## Install

#### Swift Package Manager

Add `https://github.com/sindresorhus/KeyboardShortcuts` in the [“Swift Package Manager” tab in Xcode](https://developer.apple.com/documentation/xcode/adding_package_dependencies_to_your_app).

You also need to set the build setting “Other Linker Flags” to `-weak_framework Combine` to work around [this Xcode bug](https://github.com/feedback-assistant/reports/issues/44).

#### Carthage

```
github "sindresorhus/KeyboardShortcuts"
```

#### CocoaPods

```ruby
pod 'KeyboardShortcuts'
```

## Usage

First, register a name for the keyboard shortcut.

`Constants.swift`

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
	static let toggleUnicornMode = Name("toggleUnicornMode")
}
```

You can then refer to this strongly-typed name in other places.

You will want to make a view where the user can choose a keyboard shortcut.

`PreferencesView.swift`

```swift
import SwiftUI
import KeyboardShortcuts

struct PreferencesView: View {
	var body: some View {
		HStack {
			Text("Toggle Unicorn Mode:")
			KeyboardShortcuts.Recorder(for: .toggleUnicornMode)
		}
	}
}
```

*There's also [support for Cocoa](#cocoa) instead of SwiftUI.*

`KeyboardShortcuts.Recorder` takes care of storing the keyboard shortcut in `UserDefaults` and also warning the user if the chosen keyboard shortcut is already used by the system or the app's main menu.

Add a listener for when the user presses their chosen keyboard shortcut.

`AppDelegate.swift`

```swift
import Cocoa
import KeyboardShortcuts

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ notification: Notification) {
		KeyboardShortcuts.onKeyUp(for: .toggleUnicornMode) {
			// The user pressed the keyboard shortcut for “unicorn mode”!
			self.isUnicornMode.toggle()
		}
	}
}
```

*You can also listen to key down with `.onKeyDown()`*

**That's all! ✨**

You can find a complete example by opening `KeyboardShortcuts.xcodeproj` and then running the `KeyboardShortcutsExample` target.

You can also find a [real-world example](https://github.com/sindresorhus/Plash/blob/b348a62645a873abba8dc11ff0fb8fe423419411/Plash/PreferencesView.swift#L121-L130) in my Plash app.

#### Cocoa

Use [`KeyboardShortcuts.RecorderCocoa`](Sources/KeyboardShortcuts/RecorderCocoa.swift) instead of `KeyboardShortcuts.Recorder`.

```swift
import Cocoa
import KeyboardShortcuts

final class PreferencesViewController: NSViewController {
	override func loadView() {
		view = NSView()

		let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleUnicornMode)
		view.addSubview(recorder)
	}
}
```

## API

[See the API docs.](https://sindresorhus.com/KeyboardShortcuts/Enums/KeyboardShortcuts.html)

## Tips

#### Show a recorded keyboard shortcut in an `NSMenuItem`

See [`NSMenuItem#setShortcut`](https://sindresorhus.com/KeyboardShortcuts/Extensions/NSMenuItem.html).

## FAQ

#### How is it different from [`MASShortcut`](https://github.com/shpakovski/MASShortcut)?

This package:
- Written in Swift with a swifty API.
- More native-looking UI component.
- SwiftUI component included.
- Support for listening to key down, not just key up.
- Swift Package Manager support.
- Connect a shortcut to an `NSMenuItem`.

`MASShortcut`:
- More mature.
- More features.
- Localized.

#### How is it different from [`HotKey`](https://github.com/soffes/HotKey)?

`HotKey` is good for adding hard-coded keyboard shortcuts, but it doesn't provide any UI component for the user to choose their own keyboard shortcuts.

#### Why is this package importing `Carbon`? Isn't that deprecated?

Most of the Carbon APIs were deprecated years ago, but there are some left that Apple never shipped modern replacements for. This includes registering global keyboard shortcuts. However, you should not need to worry about this. Apple will for sure ship new APIs before deprecating the Carbon APIs used here.

#### Does this package cause any permission dialogs?

No.

## Related

- [Preferences](https://github.com/sindresorhus/Preferences) - Add a preferences window to your macOS app in minutes
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin) - Add "Launch at Login" functionality to your macOS app
- [Defaults](https://github.com/sindresorhus/Defaults) - Swifty and modern UserDefaults
- [More…](https://github.com/search?q=user%3Asindresorhus+language%3Aswift)
