# LoginServiceKit
[![Release version](https://img.shields.io/github/release/Clipy/LoginServiceKit.svg)]()
[![License: MIT](https://img.shields.io/github/license/Clipy/LoginServiceKit.svg)](https://github.com/Clipy/LoginServiceKit/blob/master/LICENSE)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

Easy manage login items in macOS.

## Usage
### CocoaPods
```
pod 'LoginServiceKit', :git => 'https://github.com/Clipy/LoginServiceKit.git'
```

### Carthage
```
github "Clipy/LoginServiceKit"
```

## Example
#### Check exist login item
```swift
let isExistLoginItem = LoginServiceKit.isExistLoginItems() // default Bundle.main.bundlePath
```

or

```swift
let isExistLoginItem = LoginServiceKit.isExistLoginItems(at: Bundle.main.bundlePath)
```

#### Add login item 
```swift
LoginServiceKit.addLoginItems() // default Bundle.main.bundlePath
```

or

```swift
LoginServiceKit.addLoginItems(at: Bundle.main.bundlePath)
```

#### Remove login item
```swift
LoginServiceKit.removeLoginItems() // default Bundle.main.bundlePath
```

or 

```swift
LoginServiceKit.removeLoginItems(at: Bundle.main.bundlePath)
```

### Contributing
1. Fork it ( https://github.com/Clipy/LoginServiceKit/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
