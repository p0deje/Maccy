# CLAUDE.md

## Project Overview
Maccy is a lightweight, keyboard-first clipboard manager for macOS, written in Swift 5 using SwiftUI and AppKit. Targets macOS 14.0 (Sonoma)+. Licensed under MIT.

## Build & Test
- **Build:** Open `Maccy.xcodeproj` in Xcode and build the `Maccy` scheme, or use `xcodebuild -scheme Maccy build`
- **Test:** `xcodebuild -scheme Maccy test` (uses `Maccy.xctestplan`; note: HistoryTests are currently skipped)
- No Package.swift or Makefile; dependencies are managed directly in the Xcode project

## Project Structure
- `Maccy/` — Main source (~96 Swift files)
  - `Models/` — Core Data models (HistoryItem)
  - `Observables/` — State management (AppState, History, Popup, Footer)
  - `Extensions/` — Swift extensions (`NSImage+Resized.swift`, etc.)
  - `Intents/` — Siri Shortcuts / AppIntents
  - `History.xcdatamodeld/` — Core Data schema
  - `*.lproj/` — Localizations (16+ languages)
  - `AppDelegate.swift` — App entry point
  - `Clipboard.swift` — Clipboard monitoring
  - `Search.swift` — Search modes (exact, fuzzy, regex, mixed)
- `MaccyTests/` — Unit tests
- `MaccyUITests/` — UI tests

## Code Style & Conventions
- Swift naming conventions (CamelCase types, camelCase members)
- Extension files use `TypeName+Feature.swift` naming
- Observer pattern with `AppState`; singletons like `Clipboard.shared`
- **SwiftLint** (`.swiftlint.yml`): disabled rules — `multiple_closures_with_trailing_closure`, `non_optional_string_data_conversion`, `todo`; line length ignores comments

## Linting & Tools
- **SwiftLint** — code style enforcement
- **Periphery** (`.periphery.yml`) — dead code detection (retains ObjC-accessible symbols)
- **Bartycrouch** (`.bartycrouch.toml`) — localization sync and translation via DeepL
