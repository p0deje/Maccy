SwiftHEXColors
===========

[![Build Status](http://img.shields.io/travis/thii/SwiftHEXColors.svg?style=flat)](https://travis-ci.org/thii/SwiftHEXColors)
[![Swift Package Manager Compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-4BC51D.svg?style=flat)](https://github.com/apple/swift-package-manager)
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/SwiftHEXColors.svg)](https://img.shields.io/cocoapods/v/SwiftHEXColors.svg)
[![Docs](https://img.shields.io/cocoapods/metrics/doc-percent/SwiftColors.svg)](http://cocoadocs.org/docsets/SwiftHEXColors)
[![Carthage Compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![Platform](https://img.shields.io/cocoapods/p/SwiftHEXColors.svg?style=flat)](http://cocoadocs.org/docsets/SwiftHEXColors)
[![License](https://img.shields.io/cocoapods/l/SwiftHEXColors.svg)](https://raw.githubusercontent.com/thii/SwiftHEXColors/master/LICENSE)

HEX color handling as an extension for UIColor. Written in Swift.

## Examples
### iOS
``` swift
// With hash
let color: UIColor = UIColor(hexString: "#ff8942")

// Without hash, with alpha
let secondColor: UIColor = UIColor(hexString: "ff8942", alpha: 0.5)

// Short handling
let shortColorWithHex: UIColor = UIColor(hexString: "fff")
```

For those who don't want to type the double quotation, you can init a color from a real hex value (an `Int`)

```swift
// With hash
let color: UIColor = UIColor(hex: 0xff8942)

// Without hash, with alpha
let secondColor: UIColor = UIColor(hex: 0xff8942, alpha: 0.5)
```

### OSX
``` swift
// With hash
let color: NSColor = NSColor(hexString: "#ff8942")

// Without hash, with alpha
let secondColor: NSColor = NSColor(hexString: "ff8942", alpha: 0.5)

// Short handling
let shortColorWithHex: NSColor = NSColor(hexString: "fff")

// From a real hex value (an `Int`)
// With hash
let color: NSColor = NSColor(hex: 0xff8942)

// Without hash, with alpha
let secondColor: NSColor = NSColor(hex: 0xff8942, alpha: 0.5)
```

## Installation

### Swift Package Manager

Add this as a dependency in your `Package.swift`:

```swift
import PackageDescription

let package = Package(
    name: "MyPackage",
        dependencies: [
        // Other dependencies
        .Package(url: "https://github.com/thii/SwiftHEXColors.git", majorVersion: 1)
    ]
)
```

### CocoaPods

To integrate SwiftHEXColors into your Xcode project using CocoaPods, specify it in your `Podfile`:

```ruby
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '8.0'
use_frameworks!

pod 'SwiftHEXColors'
```

Then, run the following command:

```bash
$ pod install
```

And add `import SwiftHEXColors` to the top of the files using SwiftHEXColors.

### Carthage

[Carthage](https://github.com/Carthage/Carthage) is a decentralized dependency manager that builds your dependencies and provides you with binary frameworks.

You can install Carthage with [Homebrew](http://brew.sh/) using the following command:

```bash
$ brew update
$ brew install carthage
```

To integrate SwiftHEXColors into your Xcode project using Carthage, specify it in your `Cartfile`:

```ogdl
github "thii/SwiftHEXColors"
```

Run `carthage update` to build the framework and drag the built `SwiftHEXColors.framework` into your Xcode project.

### Manually
- Drag and drop `SwiftHEXColors.swift` file into your project

# Requirements
- Swift 3
- iOS 8.0 or above.

# License
[MIT](http://thi.mit-license.org/)
