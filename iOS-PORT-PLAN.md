# Maccy iOS Companion App - Implementation Plan

## Overview

This plan details the implementation of an iOS companion app for Maccy that syncs clipboard history from macOS via iCloud. The iOS app will be read-only (view and copy items) while macOS remains the primary clipboard collector.

## Current Status

### ✅ COMPLETED

- **Phase 1: Platform Abstractions** - All platform type files created
- **Phase 2: Search & Sorter Updates** - Removed AppKit dependencies
- **Phase 3: Data Model Updates** - HistoryItem.swift updated for cross-platform
- **Phase 4: Storage Updates** - CloudKit configuration added
- **Phase 5: Observables Updates** - All observables updated with conditional compilation
- **Phase 6: SwiftUI View Updates** - All shared views updated
- **Phase 7: iOS-Specific Files** - App entry point and views created
- **Phase 8: Defaults.Keys Updates** - Cross-platform settings with iCloudSync key

### ⏳ REMAINING (Requires Xcode)

- **Phase 9: Xcode Project Configuration** - Add iOS target, set target membership
- **Phase 10: Entitlements** - Create iOS entitlements file with iCloud/CloudKit
- **Phase 11: Testing & Validation** - Test build, sync, and functionality

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Shared Code                               │
│  Models, Views, Search, Sorter, Storage (with CloudKit)         │
└─────────────────────────────────────────────────────────────────┘
          │                                    │
          ▼                                    ▼
┌─────────────────────────┐      ┌─────────────────────────┐
│     macOS App           │      │      iOS App            │
│  - Clipboard monitoring │      │  - View history         │
│  - Menu bar UI          │      │  - Search/filter        │
│  - Keyboard shortcuts   │      │  - Copy to clipboard    │
│  - Floating panel       │      │  - Settings subset      │
│  - Full settings        │◄────►│  - iCloud sync          │
│  - iCloud sync          │      │                         │
└─────────────────────────┘      └─────────────────────────┘
          │                                    │
          └──────────────┬─────────────────────┘
                         ▼
               ┌──────────────────┐
               │   iCloud/CloudKit │
               │   (SwiftData)     │
               └──────────────────┘
```

---

## Completed Work Summary

### New Files Created

| File | Purpose |
|------|---------|
| `Maccy/Platform/PlatformTypes.swift` | Type aliases (PlatformImage, PlatformScreen) |
| `Maccy/Platform/PasteboardTypes.swift` | Cross-platform pasteboard type definitions |
| `Maccy/Platform/PlatformImage+Extensions.swift` | Image processing extensions |
| `MaccyiOS/MaccyiOSApp.swift` | iOS app entry point (@main) |
| `MaccyiOS/iOSContentView.swift` | iOS navigation wrapper with search |
| `MaccyiOS/iOSSettingsView.swift` | iOS settings screen |

### Modified Files

| File | Changes Made |
|------|--------------|
| `Maccy/Search.swift` | Changed `import AppKit` to `import Foundation` |
| `Maccy/Sorter.swift` | Changed `import AppKit` to `import Foundation` |
| `Maccy/Models/HistoryItem.swift` | Conditional imports, PlatformImage, macOS-only pins guarded |
| `Maccy/Storage.swift` | Platform-specific paths, CloudKit configuration, iCloudSync support |
| `Maccy/Observables/History.swift` | iOS clipboard copy, macOS-only features guarded |
| `Maccy/Observables/HistoryItemDecorator.swift` | Platform-specific image sizes, conditional inits |
| `Maccy/Observables/AppState.swift` | macOS-only properties guarded (popup, appDelegate) |
| `Maccy/Observables/Footer.swift` | iOS has simplified footer items |
| `Maccy/Observables/FooterItem.swift` | Shortcuts macOS-only |
| `Maccy/Views/VisualEffectView.swift` | iOS uses `.ultraThinMaterial` |
| `Maccy/Views/KeyHandlingView.swift` | iOS passthrough version |
| `Maccy/Views/MouseMovedViewModifer.swift` | iOS no-op |
| `Maccy/Views/ContentView.swift` | Conditional padding, notifications |
| `Maccy/Views/HistoryListView.swift` | Popup references guarded |
| `Maccy/Views/ListItemView.swift` | Platform-specific image rendering |
| `Maccy/Views/HistoryItemView.swift` | Conditional ListItemView calls |
| `Maccy/ColorImage.swift` | UIGraphicsImageRenderer for iOS |
| `Maccy/Extensions/Defaults.Keys+Names.swift` | Added `iCloudSync` key, macOS-only keys guarded |

---

## Phase 9: Xcode Project Configuration (TODO)

### 9.1 Add iOS Target in Xcode

1. Open `Maccy.xcodeproj`
2. File → New → Target
3. Select "iOS App"
4. Product Name: "Maccy"
5. Bundle Identifier: "org.p0deje.Maccy.iOS"
6. Interface: SwiftUI
7. Language: Swift
8. Minimum Deployment: iOS 17.0

### 9.2 Configure Target Membership

**Both Targets (macOS + iOS):**
- `Models/HistoryItem.swift`
- `Models/HistoryItemContent.swift`
- `Storage.swift`
- `Search.swift`
- `Sorter.swift`
- `Throttler.swift`
- `ColorImage.swift`
- `HighlightMatch.swift`
- `PinsPosition.swift`
- `SearchVisibility.swift`
- `Observables/History.swift`
- `Observables/HistoryItemDecorator.swift`
- `Observables/AppState.swift`
- `Observables/Footer.swift`
- `Observables/FooterItem.swift`
- `Views/ContentView.swift`
- `Views/HistoryListView.swift`
- `Views/HistoryItemView.swift`
- `Views/ListItemView.swift`
- `Views/ListItemTitleView.swift`
- `Views/PreviewItemView.swift`
- `Views/SearchFieldView.swift`
- `Views/HeaderView.swift`
- `Views/FooterView.swift`
- `Views/FooterItemView.swift`
- `Views/ConfirmationView.swift`
- `Views/WrappingTextView.swift`
- `Views/VisualEffectView.swift`
- `Views/KeyHandlingView.swift`
- `Views/MouseMovedViewModifer.swift`
- `Platform/PlatformTypes.swift`
- `Platform/PasteboardTypes.swift`
- `Platform/PlatformImage+Extensions.swift`
- `Extensions/Defaults.Keys+Names.swift`
- `Extensions/String+Shortened.swift`
- `Extensions/Collection+Surrounding.swift`
- `Extensions/Dictionary+RemoveItem.swift`
- `Extensions/Color+Random.swift`
- `Extensions/String+Identifiable.swift`
- `Intents/*.swift` (App Intents if applicable)

**macOS Only:**
- `MaccyApp.swift`
- `AppDelegate.swift`
- `FloatingPanel.swift`
- `Clipboard.swift`
- `GlobalHotKey.swift`
- `KeyChord.swift`
- `KeyShortcut.swift`
- `KeyboardLayout.swift`
- `Observables/Popup.swift`
- `Observables/ModifierFlags.swift`
- `SoftwareUpdater.swift`
- `About.swift`
- `Accessibility.swift`
- `MenuIcon.swift`
- `ApplicationImage.swift`
- `ApplicationImageCache.swift`
- `PopupPosition.swift`
- `Settings/*.swift` (all settings panes)
- `Extensions/NS*.swift` (all AppKit extensions)
- `Extensions/Settings.PaneIdentifier+Panes.swift`
- `Extensions/KeyboardShortcuts.Name+Shortcuts.swift`
- `Extensions/Sauce+KeyboardShortcuts.swift`
- `Extensions/KeyEquivalent+Keys.swift`

**iOS Only:**
- `MaccyiOS/MaccyiOSApp.swift`
- `MaccyiOS/iOSContentView.swift`
- `MaccyiOS/iOSSettingsView.swift`

### 9.3 Update Package Dependencies

Ensure iOS compatibility in Xcode's package dependencies:

| Package | iOS Support | Action |
|---------|-------------|--------|
| Defaults | ✅ Yes | Include for iOS target |
| Fuse | ✅ Yes | Include for iOS target |
| swift-log | ✅ Yes | Include for iOS target |
| SwiftHEXColors | ✅ Yes | Include for iOS target |
| Sauce | ❌ No | Exclude from iOS target |
| KeyboardShortcuts | ❌ No | Exclude from iOS target |
| LaunchAtLogin | ❌ No | Exclude from iOS target |
| Settings | ❌ No | Exclude from iOS target |
| Sparkle | ❌ No | Exclude from iOS target |

---

## Phase 10: Entitlements (TODO)

### 10.1 Create iOS Entitlements File

**New file: `MaccyiOS/MaccyiOS.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.org.p0deje.Maccy</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.org.p0deje.Maccy</string>
    </array>
</dict>
</plist>
```

### 10.2 Update macOS Entitlements

Add to existing `Maccy.entitlements`:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.org.p0deje.Maccy</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
```

### 10.3 CloudKit Dashboard Setup

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/)
2. Create container: `iCloud.org.p0deje.Maccy`
3. SwiftData will auto-create the schema on first sync

---

## Phase 11: Testing & Validation (TODO)

### 11.1 Build Verification

1. Build macOS target - verify no regressions
2. Build iOS target - verify compilation succeeds
3. Run on iOS Simulator

### 11.2 Functional Testing

- [ ] iOS app launches successfully
- [ ] History items display correctly
- [ ] Search works as expected
- [ ] Tapping item copies to clipboard
- [ ] Haptic feedback on copy
- [ ] Settings screen works
- [ ] Clear history works with confirmation

### 11.3 iCloud Sync Testing

1. Enable iCloud sync in macOS Maccy settings
2. Enable iCloud sync in iOS Maccy settings
3. Copy something on macOS
4. Verify it appears on iOS (may take a few seconds)
5. Test offline behavior
6. Test conflict resolution

### 11.4 Edge Cases

- [ ] Empty history state
- [ ] Large images
- [ ] Very long text
- [ ] Special characters in text
- [ ] No iCloud account signed in
- [ ] iCloud sync disabled

---

## Quick Start Guide for Continuing

1. **Open Xcode** and open `Maccy.xcodeproj`

2. **Add iOS Target:**
   - File → New → Target → iOS App
   - Name: "Maccy", Bundle ID: "org.p0deje.Maccy.iOS"
   - Minimum iOS 17.0

3. **Set Target Membership:**
   - Select each file in Project Navigator
   - In File Inspector, check/uncheck target membership per lists above
   - Key: Platform/ folder and MaccyiOS/ folder files need correct membership

4. **Configure Packages:**
   - In Package Dependencies, exclude macOS-only packages from iOS target:
     - Sauce, KeyboardShortcuts, LaunchAtLogin, Settings, Sparkle

5. **Add Entitlements:**
   - Create `MaccyiOS/MaccyiOS.entitlements` with iCloud config
   - Update macOS entitlements with iCloud config

6. **Build & Test:**
   - Build macOS target first to verify no regressions
   - Build iOS target
   - Test on simulator

---

## Notes

- **No clipboard monitoring on iOS**: iOS doesn't allow background clipboard monitoring. The iOS app is purely for viewing history synced from macOS.
- **User must have macOS app**: The iOS companion app requires the macOS app to collect clipboard history.
- **iCloud required**: Users must be signed into iCloud on both devices for sync to work.
- **Consider widgets**: A future enhancement could add iOS widgets to show recent clipboard items.
