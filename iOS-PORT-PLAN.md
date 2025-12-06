# Maccy iOS Companion App - Implementation Plan

## Overview

This plan details the implementation of an iOS companion app for Maccy that syncs clipboard history from macOS via iCloud. The iOS app will be read-only (view and copy items) while macOS remains the primary clipboard collector.

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

## Phase 1: Prepare Platform Abstractions

### 1.1 Create Platform Type Aliases

**New file: `Maccy/Platform/PlatformTypes.swift`**

```swift
import SwiftUI

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformPasteboard = NSPasteboard
#else
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformPasteboard = UIPasteboard
#endif
```

**Target membership:** Both macOS and iOS

### 1.2 Create PasteboardType Abstraction

**New file: `Maccy/Platform/PasteboardTypes.swift`**

The current `NSPasteboard.PasteboardType` extension is macOS-only. Create a cross-platform abstraction:

```swift
import Foundation

#if os(macOS)
import AppKit
public typealias PasteboardType = NSPasteboard.PasteboardType
#else
import UIKit
import UniformTypeIdentifiers

public struct PasteboardType: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

extension PasteboardType {
    // Standard types mapped to UTType identifiers
    static let string = PasteboardType(rawValue: UTType.plainText.identifier)
    static let html = PasteboardType(rawValue: UTType.html.identifier)
    static let rtf = PasteboardType(rawValue: UTType.rtf.identifier)
    static let tiff = PasteboardType(rawValue: UTType.tiff.identifier)
    static let png = PasteboardType(rawValue: UTType.png.identifier)
    static let fileURL = PasteboardType(rawValue: UTType.fileURL.identifier)
}
#endif

// Common extension for both platforms
extension PasteboardType {
    static let heic = PasteboardType(rawValue: "public.heic")
    static let jpeg = PasteboardType(rawValue: "public.jpeg")
    static let universalClipboard = PasteboardType(rawValue: "com.apple.is-remote-clipboard")
    static let fromMaccy = PasteboardType(rawValue: "org.p0deje.Maccy")
    // ... other custom types
}
```

**Target membership:** Both macOS and iOS

### 1.3 Create Platform Image Extension

**New file: `Maccy/Platform/PlatformImage+Extensions.swift`**

```swift
import SwiftUI

#if os(macOS)
import AppKit

extension NSImage {
    var cgImageForProcessing: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
#else
import UIKit

extension UIImage {
    var cgImageForProcessing: CGImage? { cgImage }

    func resized(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
```

**Target membership:** Both macOS and iOS

---

## Phase 2: Refactor Data Models for Cross-Platform

### 2.1 Update HistoryItem.swift

**File: `Maccy/Models/HistoryItem.swift`**

Changes needed:
1. Replace `import AppKit` with conditional import
2. Replace `NSImage` with `PlatformImage`
3. Replace `NSPasteboard.PasteboardType` with `PasteboardType`
4. Guard macOS-specific pin logic with `#if os(macOS)`

```swift
#if os(macOS)
import AppKit
import Sauce
#else
import UIKit
#endif
import Defaults
import SwiftData
import Vision

@Model
class HistoryItem {
    #if os(macOS)
    static var supportedPins: Set<String> {
        // ... existing macOS-specific pin logic with Sauce
    }

    @MainActor
    static var availablePins: [String] {
        // ... existing logic
    }

    @MainActor
    static var randomAvailablePin: String { availablePins.randomElement() ?? "" }
    #endif

    // ... rest of properties unchanged

    var image: PlatformImage? {
        guard let data = imageData else { return nil }
        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data)
        #endif
    }

    // Update contentData to use PasteboardType
    private func contentData(_ types: [PasteboardType]) -> Data? {
        let content = contents.first { content in
            types.contains(PasteboardType(rawValue: content.type))
        }
        return content?.value
    }

    #if os(macOS)
    private func performTextRecognition() {
        guard let cgImage = image?.cgImageForProcessing else { return }
        // ... existing OCR logic
    }
    #else
    private func performTextRecognition() {
        guard let cgImage = image?.cgImageForProcessing else { return }
        // Same logic works on iOS with Vision framework
        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
        request.recognitionLevel = .fast
        do {
            try requestHandler.perform([request])
        } catch {
            print("Unable to perform the request: \(error).")
        }
    }
    #endif
}
```

**Target membership:** Both macOS and iOS

### 2.2 HistoryItemContent.swift - No Changes Needed

**File: `Maccy/Models/HistoryItemContent.swift`**

This file is already platform-agnostic (only uses SwiftData).

**Target membership:** Both macOS and iOS

---

## Phase 3: Refactor Storage for iCloud Sync

### 3.1 Update Storage.swift for CloudKit

**File: `Maccy/Storage.swift`**

```swift
import Foundation
import SwiftData

@MainActor
class Storage {
    static let shared = Storage()

    var container: ModelContainer
    var context: ModelContext { container.mainContext }

    var size: String {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).allValues.first?.value as? Int64, size > 1 else {
            return ""
        }
        return ByteCountFormatter().string(fromByteCount: size)
    }

    #if os(macOS)
    private let url = URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")
    #else
    // iOS uses app's documents directory within app group for sharing
    private let url: URL = {
        // Use App Group container for potential widget/extension sharing
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.org.p0deje.Maccy"
        ) {
            return containerURL.appending(path: "Storage.sqlite")
        }
        return URL.documentsDirectory.appending(path: "Storage.sqlite")
    }()
    #endif

    init() {
        // Configure for iCloud sync when enabled
        var config: ModelConfiguration

        #if DEBUG
        if CommandLine.arguments.contains("enable-testing") {
            config = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            config = createConfiguration()
        }
        #else
        config = createConfiguration()
        #endif

        do {
            container = try ModelContainer(for: HistoryItem.self, configurations: config)
        } catch let error {
            fatalError("Cannot load database: \(error.localizedDescription).")
        }
    }

    private func createConfiguration() -> ModelConfiguration {
        // Enable CloudKit sync when user has opted in
        // Note: CloudKit sync requires additional entitlements setup
        #if os(macOS)
        return ModelConfiguration(url: url, cloudKitDatabase: .private("iCloud.org.p0deje.Maccy"))
        #else
        return ModelConfiguration(url: url, cloudKitDatabase: .private("iCloud.org.p0deje.Maccy"))
        #endif
    }
}
```

**Target membership:** Both macOS and iOS

### 3.2 iCloud Entitlements

**macOS entitlements addition:**
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

**New file: `MaccyiOS/MaccyiOS.entitlements`**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
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

---

## Phase 4: Refactor Observables for Cross-Platform

### 4.1 Update History.swift

**File: `Maccy/Observables/History.swift`**

Major changes:
1. Guard macOS-specific clipboard operations
2. Make `select()` platform-aware (copy only on iOS, no paste simulation)
3. Remove references to `NSApp.currentEvent` on iOS

```swift
#if os(macOS)
import AppKit.NSRunningApplication
import Sauce
import Settings
#else
import UIKit
#endif
import Defaults
import Foundation
import Logging
import Observation
import SwiftData

@Observable
class History {
    static let shared = History()
    let logger = Logger(label: "org.p0deje.Maccy")

    // ... existing properties unchanged

    #if os(macOS)
    var pressedShortcutItem: HistoryItemDecorator? {
        // ... existing macOS keyboard shortcut logic
    }
    #endif

    // ... existing init and load() unchanged

    @MainActor
    func select(_ item: HistoryItemDecorator?) {
        guard let item else { return }

        #if os(macOS)
        // Existing macOS logic with modifier flags, paste simulation, etc.
        let modifierFlags = NSApp.currentEvent?.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function]) ?? []

        if modifierFlags.isEmpty {
            AppState.shared.popup.close()
            Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
            if Defaults[.pasteByDefault] {
                Clipboard.shared.paste()
            }
        } else {
            // ... modifier-based actions
        }
        #else
        // iOS: Simply copy to clipboard, no paste simulation possible
        copyToiOSClipboard(item.item)
        #endif

        Task {
            searchQuery = ""
        }
    }

    #if os(iOS)
    private func copyToiOSClipboard(_ item: HistoryItem) {
        // Copy text content to iOS clipboard
        if let text = item.text {
            UIPasteboard.general.string = text
        } else if let imageData = item.imageData, let image = UIImage(data: imageData) {
            UIPasteboard.general.image = image
        }
        // Show feedback (haptic, toast, etc.)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    #endif

    @MainActor
    func clear() {
        // ... existing logic

        #if os(macOS)
        Clipboard.shared.clear()
        AppState.shared.popup.close()
        #endif

        // ... rest unchanged
    }
}
```

**Target membership:** Both macOS and iOS

### 4.2 Update HistoryItemDecorator.swift

**File: `Maccy/Observables/HistoryItemDecorator.swift`**

```swift
#if os(macOS)
import AppKit.NSWorkspace
import Sauce
#else
import UIKit
#endif
import Defaults
import Foundation
import Observation

@Observable
class HistoryItemDecorator: Identifiable, Hashable {
    // ... existing static properties

    #if os(macOS)
    static var previewImageSize: NSSize { NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536) }
    static var thumbnailImageSize: NSSize { NSSize(width: 340, height: Defaults[.imageMaxHeight]) }
    #else
    static var previewImageSize: CGSize { UIScreen.main.bounds.size }
    static var thumbnailImageSize: CGSize { CGSize(width: 340, height: Defaults[.imageMaxHeight]) }
    #endif

    // ... existing id, title, attributedTitle, etc.

    var previewImage: PlatformImage?
    var thumbnailImage: PlatformImage?

    var application: String? {
        if item.universalClipboard {
            return "iCloud"
        }

        #if os(macOS)
        guard let bundle = item.application,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
        else {
            return nil
        }
        return url.deletingPathExtension().lastPathComponent
        #else
        // On iOS, just return the bundle identifier as-is (or formatted)
        return item.application
        #endif
    }

    // Image generation - platform-specific resizing
    @MainActor
    private func generateThumbnailImage() {
        guard let image = item.image else { return }
        #if os(macOS)
        thumbnailImage = image.resized(to: HistoryItemDecorator.thumbnailImageSize)
        #else
        thumbnailImage = image.resized(to: HistoryItemDecorator.thumbnailImageSize)
        #endif
    }

    // ... rest of file with similar adaptations
}
```

**Target membership:** Both macOS and iOS

### 4.3 Update AppState.swift

**File: `Maccy/Observables/AppState.swift`**

Create a slimmed-down version for iOS:

```swift
#if os(macOS)
import AppKit
import Settings
#else
import UIKit
#endif
import Defaults
import Foundation

@Observable
class AppState: Sendable {
    static let shared = AppState()

    #if os(macOS)
    var appDelegate: AppDelegate?
    var popup: Popup
    #endif

    var history: History
    var footer: Footer

    var scrollTarget: UUID?
    var selection: UUID? {
        didSet {
            selectWithoutScrolling(selection)
            scrollTarget = selection
        }
    }

    var hoverSelectionWhileKeyboardNavigating: UUID?
    var isKeyboardNavigating: Bool = true {
        didSet {
            if let hoverSelection = hoverSelectionWhileKeyboardNavigating {
                hoverSelectionWhileKeyboardNavigating = nil
                selection = hoverSelection
            }
        }
    }

    var searchVisible: Bool {
        if !Defaults[.showSearch] { return false }
        switch Defaults[.searchVisibility] {
        case .always: return true
        case .duringSearch: return !history.searchQuery.isEmpty
        }
    }

    init() {
        history = History.shared
        footer = Footer()
        #if os(macOS)
        popup = Popup()
        #endif
    }

    func selectWithoutScrolling(_ item: UUID?) {
        history.selectedItem = nil
        footer.selectedItem = nil

        if let item = history.items.first(where: { $0.id == item }) {
            history.selectedItem = item
        } else if let item = footer.items.first(where: { $0.id == item }) {
            footer.selectedItem = item
        }
    }

    // Navigation methods - shared
    func highlightFirst() { /* ... same logic */ }
    func highlightPrevious() { /* ... same logic */ }
    func highlightNext(allowCycle: Bool = false) { /* ... same logic */ }
    func highlightLast() { /* ... same logic */ }

    @MainActor
    func select() {
        if let item = history.selectedItem, history.items.contains(item) {
            history.select(item)
        } else if let item = footer.selectedItem {
            #if os(macOS)
            if item.confirmation != nil, Defaults[.suppressClearAlert] == false {
                item.showConfirmation = true
            } else {
                item.action()
            }
            #else
            item.action()
            #endif
        }
    }

    #if os(macOS)
    func openAbout() { /* ... macOS only */ }

    @MainActor
    func openPreferences() { /* ... macOS only */ }

    func quit() {
        NSApp.terminate(self)
    }
    #endif
}
```

**Target membership:** Both macOS and iOS

---

## Phase 5: Refactor SwiftUI Views

### 5.1 Files to Share (Both Targets)

These views need minimal or no changes:

| File | Changes Needed |
|------|----------------|
| `Views/HistoryItemView.swift` | None - pure SwiftUI |
| `Views/HistoryListView.swift` | Guard `popup` references |
| `Views/ListItemView.swift` | None - pure SwiftUI |
| `Views/ListItemTitleView.swift` | None - pure SwiftUI |
| `Views/PreviewItemView.swift` | None - pure SwiftUI |
| `Views/SearchFieldView.swift` | None - pure SwiftUI |
| `Views/HeaderView.swift` | None - pure SwiftUI |
| `Views/FooterView.swift` | Guard macOS-specific footer items |
| `Views/FooterItemView.swift` | None - pure SwiftUI |
| `Views/ConfirmationView.swift` | None - pure SwiftUI |
| `Views/WrappingTextView.swift` | None - pure SwiftUI |

### 5.2 Update VisualEffectView.swift

**File: `Maccy/Views/VisualEffectView.swift`**

```swift
import SwiftUI

#if os(macOS)
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .popover
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

@available(macOS 26.0, *)
struct GlassEffectView: View {
    var body: some View {
        Color.clear.glassEffect()
    }
}
#else
struct VisualEffectView: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
    }
}
#endif
```

**Target membership:** Both macOS and iOS

### 5.3 Update KeyHandlingView.swift

**File: `Maccy/Views/KeyHandlingView.swift`**

This file is heavily macOS-specific (NSEvent monitoring). Create conditional implementation:

```swift
import SwiftUI

#if os(macOS)
// Keep existing implementation for macOS
struct KeyHandlingView<Content: View>: View {
    // ... existing macOS implementation
}
#else
// iOS version - no keyboard event handling, just pass through content
struct KeyHandlingView<Content: View>: View {
    @Binding var searchQuery: String
    @FocusState.Binding var searchFocused: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}
#endif
```

**Target membership:** Both macOS and iOS

### 5.4 Update MouseMovedViewModifier.swift

**File: `Maccy/Views/MouseMovedViewModifer.swift`**

```swift
import SwiftUI

#if os(macOS)
// Keep existing macOS implementation
struct MouseMovedViewModifer: ViewModifier {
    // ... existing implementation
}

extension View {
    func onMouseMove(perform: @escaping () -> Void) -> some View {
        modifier(MouseMovedViewModifer(perform: perform))
    }
}
#else
// iOS - no-op, mice don't exist on iOS (unless iPad with pointer)
extension View {
    func onMouseMove(perform: @escaping () -> Void) -> some View {
        self // No-op on iOS
    }
}
#endif
```

**Target membership:** Both macOS and iOS

### 5.5 Update ContentView.swift

**File: `Maccy/Views/ContentView.swift`**

```swift
import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var appState = AppState.shared
    #if os(macOS)
    @State private var modifierFlags = ModifierFlags()
    #endif
    @State private var scenePhase: ScenePhase = .background
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            #if os(macOS)
            if #available(macOS 26.0, *) {
                GlassEffectView()
            } else {
                VisualEffectView()
            }
            #else
            VisualEffectView()
            #endif

            VStack(alignment: .leading, spacing: 0) {
                #if os(macOS)
                KeyHandlingView(searchQuery: $appState.history.searchQuery, searchFocused: $searchFocused) {
                    mainContent
                }
                #else
                mainContent
                #endif
            }
            .animation(.default.speed(3), value: appState.history.items)
            .animation(.easeInOut(duration: 0.2), value: appState.searchVisible)
            #if os(macOS)
            .padding(.vertical, Popup.verticalPadding)
            .padding(.horizontal, Popup.horizontalPadding)
            #else
            .padding()
            #endif
            .onAppear {
                searchFocused = true
            }
            #if os(macOS)
            .onMouseMove {
                appState.isKeyboardNavigating = false
            }
            #endif
            .task {
                try? await appState.history.load()
            }
        }
        .environment(appState)
        #if os(macOS)
        .environment(modifierFlags)
        #endif
        .environment(\.scenePhase, scenePhase)
        #if os(macOS)
        // FloatingPanel notifications - macOS only
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { /* ... */ }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { /* ... */ }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.willShowNotification)) { /* ... */ }
        #else
        .onChange(of: scenePhase) { _, newPhase in
            self.scenePhase = newPhase
        }
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        HeaderView(
            searchFocused: $searchFocused,
            searchQuery: $appState.history.searchQuery
        )

        HistoryListView(
            searchQuery: $appState.history.searchQuery,
            searchFocused: $searchFocused
        )

        FooterView(footer: appState.footer)
    }
}
```

**Target membership:** Both macOS and iOS

---

## Phase 6: Shared Utility Files

### 6.1 Files That Need No Changes (Share Directly)

| File | Notes |
|------|-------|
| `Search.swift` | Change `import AppKit` to `import Foundation` |
| `Sorter.swift` | Change `import AppKit` to `import Foundation` |
| `Throttler.swift` | Already platform-agnostic |
| `ColorImage.swift` | Review for any AppKit dependencies |
| `HighlightMatch.swift` | Already platform-agnostic |
| `PinsPosition.swift` | Already platform-agnostic |
| `SearchVisibility.swift` | Already platform-agnostic |

### 6.2 Update Search.swift

```swift
// Change from:
import AppKit

// To:
import Foundation
import Defaults
import Fuse
```

### 6.3 Update Sorter.swift

```swift
// Change from:
import AppKit

// To:
import Foundation
import Defaults
```

### 6.4 Settings Keys - Defaults.Keys+Names.swift

This file defines all user defaults keys. It should be shared, but some keys are macOS-only.

```swift
// Add conditional compilation for macOS-only settings
extension Defaults.Keys {
    // Shared settings
    static let size = Key<Int>("size", default: 200)
    static let searchMode = Key<Search.Mode>("searchMode", default: .exact)
    static let sortBy = Key<Sorter.By>("sortBy", default: .lastCopiedAt)
    // ... other shared settings

    #if os(macOS)
    // macOS-only settings
    static let pasteByDefault = Key<Bool>("pasteByDefault", default: false)
    static let popupPosition = Key<PopupPosition>("popupPosition", default: .cursor)
    static let enabledPasteboardTypes = Key<Set<NSPasteboard.PasteboardType>>("enabledPasteboardTypes", default: /* ... */)
    // ... other macOS-only settings
    #endif
}
```

**Target membership:** Both macOS and iOS

---

## Phase 7: iOS-Only Files

### 7.1 Create iOS App Entry Point

**New file: `MaccyiOS/MaccyiOSApp.swift`**

```swift
import SwiftUI
import SwiftData

@main
struct MaccyiOSApp: App {
    var body: some Scene {
        WindowGroup {
            iOSContentView()
                .modelContainer(Storage.shared.container)
        }
    }
}
```

**Target membership:** iOS only

### 7.2 Create iOS-Specific Content View

**New file: `MaccyiOS/iOSContentView.swift`**

```swift
import SwiftUI

struct iOSContentView: View {
    @State private var appState = AppState.shared
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ContentView()
                .navigationTitle("Maccy")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $appState.history.searchQuery, prompt: "Search clipboard history")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink {
                            iOSSettingsView()
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
        }
        .environment(appState)
    }
}

#Preview {
    iOSContentView()
        .modelContainer(Storage.shared.container)
}
```

**Target membership:** iOS only

### 7.3 Create iOS Settings View

**New file: `MaccyiOS/iOSSettingsView.swift`**

```swift
import SwiftUI
import Defaults

struct iOSSettingsView: View {
    @Default(.searchMode) private var searchMode
    @Default(.sortBy) private var sortBy
    @Default(.imageMaxHeight) private var imageMaxHeight

    var body: some View {
        Form {
            Section("Search") {
                Picker("Search Mode", selection: $searchMode) {
                    ForEach(Search.Mode.allCases) { mode in
                        Text(mode.description).tag(mode)
                    }
                }
            }

            Section("Display") {
                Picker("Sort By", selection: $sortBy) {
                    ForEach(Sorter.By.allCases) { sort in
                        Text(sort.description).tag(sort)
                    }
                }

                Stepper("Max Image Height: \(imageMaxHeight)", value: $imageMaxHeight, in: 20...200, step: 10)
            }

            Section("Storage") {
                HStack {
                    Text("Database Size")
                    Spacer()
                    Text(Storage.shared.size)
                        .foregroundStyle(.secondary)
                }

                Button("Clear History", role: .destructive) {
                    Task {
                        await History.shared.clearAll()
                    }
                }
            }

            Section("About") {
                Link("GitHub Repository", destination: URL(string: "https://github.com/p0deje/Maccy")!)
                Text("Version \(Bundle.main.appVersion)")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
}
```

**Target membership:** iOS only

---

## Phase 8: macOS-Only Files (No iOS Target Membership)

These files should NOT be added to the iOS target:

| File | Reason |
|------|--------|
| `AppDelegate.swift` | NSApplicationDelegate, menu bar |
| `FloatingPanel.swift` | NSPanel subclass |
| `Clipboard.swift` | NSPasteboard monitoring |
| `GlobalHotKey.swift` | Global hotkey registration |
| `KeyChord.swift` | Keyboard shortcut handling |
| `Popup.swift` | Floating panel management |
| `SoftwareUpdater.swift` | Sparkle framework |
| `About.swift` | macOS about window |
| `ModifierFlags.swift` | NSEvent modifier tracking |
| `Accessibility.swift` | AXIsProcessTrusted |
| `PopupPosition.swift` | Screen positioning (can share partially) |
| `ApplicationImage.swift` | NSWorkspace app icons |
| `ApplicationImageCache.swift` | NSWorkspace app icons |
| `Settings/*.swift` | macOS Settings framework panes |
| `Extensions/NS*.swift` | All AppKit extensions |

---

## Phase 9: Project Configuration

### 9.1 Add iOS Target in Xcode

1. Open `Maccy.xcodeproj`
2. File → New → Target
3. Select "iOS App"
4. Product Name: "Maccy"
5. Bundle Identifier: "org.p0deje.Maccy.iOS" (or "org.p0deje.Maccy" if universal)
6. Interface: SwiftUI
7. Language: Swift

### 9.2 Configure Target Membership

Set file target membership according to these categories:

**Both Targets:**
- `Models/HistoryItem.swift`
- `Models/HistoryItemContent.swift`
- `Storage.swift`
- `Search.swift`
- `Sorter.swift`
- `Throttler.swift`
- `Observables/History.swift`
- `Observables/HistoryItemDecorator.swift`
- `Observables/AppState.swift`
- `Observables/Footer.swift`
- `Observables/FooterItem.swift`
- `Views/*.swift` (most views)
- `Platform/*.swift` (new abstraction files)
- `Extensions/Defaults.Keys+Names.swift`
- `Extensions/String+Shortened.swift`
- `Extensions/Collection+Surrounding.swift`
- `Extensions/Dictionary+RemoveItem.swift`
- `Extensions/Color+Random.swift`
- `Extensions/String+Identifiable.swift`
- `Intents/*.swift` (App Intents)

**macOS Only:**
- `AppDelegate.swift`
- `MaccyApp.swift`
- `FloatingPanel.swift`
- `Clipboard.swift`
- `GlobalHotKey.swift`
- `KeyChord.swift`
- `Observables/Popup.swift`
- `Observables/ModifierFlags.swift`
- `SoftwareUpdater.swift`
- `About.swift`
- `Accessibility.swift`
- `MenuIcon.swift`
- `KeyShortcut.swift`
- `KeyboardLayout.swift`
- `ApplicationImage.swift`
- `ApplicationImageCache.swift`
- `Settings/*.swift`
- `Extensions/NS*.swift`
- `Extensions/Settings.PaneIdentifier+Panes.swift`
- `Extensions/KeyboardShortcuts.Name+Shortcuts.swift`
- `Extensions/Sauce+KeyboardShortcuts.swift`
- `Extensions/KeyEquivalent+Keys.swift`

**iOS Only:**
- `MaccyiOS/MaccyiOSApp.swift`
- `MaccyiOS/iOSContentView.swift`
- `MaccyiOS/iOSSettingsView.swift`

### 9.3 Update Package Dependencies

In `Package.swift` or Xcode's package dependencies, ensure iOS compatibility:

| Package | iOS Support | Notes |
|---------|-------------|-------|
| Defaults | ✅ Yes | Works on iOS |
| Fuse | ✅ Yes | Works on iOS |
| swift-log | ✅ Yes | Works on iOS |
| SwiftHEXColors | ✅ Yes | Works on iOS |
| Sauce | ❌ No | macOS only - guard with `#if os(macOS)` |
| KeyboardShortcuts | ❌ No | macOS only |
| LaunchAtLogin | ❌ No | macOS only |
| Settings | ❌ No | macOS only |
| Sparkle | ❌ No | macOS only |

### 9.4 iOS Deployment Target

- Minimum iOS version: **iOS 17.0** (required for SwiftData and @Observable)
- Devices: iPhone and iPad

---

## Phase 10: Testing & Validation

### 10.1 Unit Tests

Create shared test target that tests cross-platform code:

```swift
// Tests/SharedTests/SearchTests.swift
import XCTest
@testable import Maccy // or MaccyKit if extracted

final class SearchTests: XCTestCase {
    func testExactSearch() { /* ... */ }
    func testFuzzySearch() { /* ... */ }
    func testRegexpSearch() { /* ... */ }
}

// Tests/SharedTests/SorterTests.swift
final class SorterTests: XCTestCase {
    func testSortByLastCopied() { /* ... */ }
    func testSortByFirstCopied() { /* ... */ }
    func testPinnedItemsFirst() { /* ... */ }
}
```

### 10.2 UI Tests

Create platform-specific UI test targets:

- `MaccyUITests` (existing macOS tests)
- `MaccyiOSUITests` (new iOS tests)

### 10.3 CloudKit Testing

1. Enable CloudKit development environment
2. Test sync between macOS and iOS simulators
3. Test conflict resolution (same item modified on both)
4. Test offline scenarios

---

## Summary: File Classification

### Files Requiring Modification for Cross-Platform

| File | Changes |
|------|---------|
| `Models/HistoryItem.swift` | Platform imports, image types, guard macOS-specific code |
| `Storage.swift` | CloudKit configuration, platform-specific paths |
| `Search.swift` | Remove AppKit import |
| `Sorter.swift` | Remove AppKit import |
| `Observables/History.swift` | Guard clipboard operations, platform-specific select() |
| `Observables/HistoryItemDecorator.swift` | Platform image types, NSWorkspace guards |
| `Observables/AppState.swift` | Guard Popup, settings window, quit |
| `Observables/Footer.swift` | Guard macOS-specific items |
| `Views/ContentView.swift` | Guard window notifications, popup padding |
| `Views/HistoryListView.swift` | Guard popup references |
| `Views/VisualEffectView.swift` | Platform-specific implementations |
| `Views/KeyHandlingView.swift` | No-op on iOS |
| `Views/MouseMovedViewModifer.swift` | No-op on iOS |
| `Extensions/Defaults.Keys+Names.swift` | Guard macOS-only keys |

### New Files to Create

| File | Purpose |
|------|---------|
| `Platform/PlatformTypes.swift` | Type aliases for NSImage/UIImage |
| `Platform/PasteboardTypes.swift` | Cross-platform pasteboard type definitions |
| `Platform/PlatformImage+Extensions.swift` | Image resizing extensions |
| `MaccyiOS/MaccyiOSApp.swift` | iOS app entry point |
| `MaccyiOS/iOSContentView.swift` | iOS navigation wrapper |
| `MaccyiOS/iOSSettingsView.swift` | iOS settings screen |
| `MaccyiOS/MaccyiOS.entitlements` | iOS iCloud entitlements |

---

## Implementation Order

1. **Week 1: Platform Abstractions**
   - Create `Platform/` folder with type abstractions
   - Update imports in Search.swift, Sorter.swift

2. **Week 2: Data Layer**
   - Update HistoryItem.swift, HistoryItemContent.swift
   - Update Storage.swift with CloudKit support
   - Set up iCloud entitlements for both targets

3. **Week 3: Observables**
   - Update History.swift, HistoryItemDecorator.swift
   - Update AppState.swift, Footer.swift
   - Add iOS-specific clipboard copy method

4. **Week 4: Views**
   - Update shared SwiftUI views with platform guards
   - Create iOS-specific views
   - Test on both platforms

5. **Week 5: Polish & Testing**
   - Write unit tests for shared code
   - Write UI tests for iOS
   - Test CloudKit sync thoroughly
   - Handle edge cases (no network, conflicts, etc.)

---

## Notes

- **No clipboard monitoring on iOS**: iOS doesn't allow background clipboard monitoring. The iOS app is purely for viewing history synced from macOS.
- **User must have macOS app**: The iOS companion app requires the macOS app to collect clipboard history.
- **iCloud required**: Users must be signed into iCloud on both devices for sync to work.
- **Consider widgets**: A future enhancement could add iOS widgets to show recent clipboard items.
