This change raises the storage limit from 999 to 3000 items and improves memory behavior for large clipboard histories. Normal popup browsing no longer hydrates the full history into memory, avoiding excessive memory usage. It also bounds expensive preview/list rendering work and fixes status-bar popup edge cases on multi-display setups.

## Impact

- Avoided the previous excessive memory usage seen with large histories, where Activity Monitor could reach roughly 700-900 MB during testing
- Final warm idle after cleanup settled around 93 MB in local testing
- Increased storage capacity from 999 to 3000 items
- Prevented full-history hydration during normal browsing

## Priority Changes

### 1. Large History And Memory

- Added paginated history loading with forward/backward page fetches so normal browsing starts with a bounded set of unpinned items instead of materializing the full store.
- The retained unpinned browse window follows the configured storage limit, with one page as the minimum, instead of using a separate hardcoded window size.
- Changed idle cleanup from 60 seconds to 30 seconds after the popup closes. Cleanup drops decorators, clears cached app icons, resets navigation selection, and recreates the SwiftData container after yielding once to reduce short-lived memory peaks.
- Added thumbnail backfill for older image items. Backfill runs only while the popup is open and stops when the popup closes.
- Added app-icon and preview-image cleanup so cached icons, file watchers, preview images, and image generation tasks do not stay resident unnecessarily.
- Released the Settings window controller when Settings closes so Settings-only SwiftUI panes, observers, Sparkle updater state, and pinned-item query state are not retained for the rest of the app lifetime.

### 2. Preview And Row Rendering

- Capped preview text through a bounded preview path instead of rendering very large text bodies directly.
- Added data size display alongside number of copies so the preview can stay small while still showing the original item size.
- List rows now use `displayTitle`, a capped title/excerpt, and search highlighting runs inside that displayed excerpt.
- Keyed preview content by item id and reset preview state cleanly when switching selected items.
- Added preview auto-open safeguards, including suppressing auto-open on initial status-bar presentation until a future hover or selection change.

### 3. Search

- Added cancellable, revision-guarded search so stale async work cannot apply results after the query changes.
- Full-history search builds a temporary search corpus instead of replacing the normal paginated browse list.
- Search still shows immediate results from the currently loaded page, then restores the paginated browse window when the query is cleared.

### 4. Status Bar And Popup Positioning

- Routed status item clicks through `Popup.open` / `Popup.close`, added click debounce, and guarded opening with an `isOpening` flag.
- Added fallback sizing before measured content height is available to avoid strange first-open shapes.
- Validated status item placement and added mouse/active-screen fallbacks when AppKit reports an invalid status rect, then clamps the popup to the chosen screen.
- Locked preview placement during a popup presentation so it does not jump sides while scrolling.

### 5. Storage And Clipboard

- Increased the storage limit from 999 to 3000 items.
<img width="622" height="396" alt="image" src="https://github.com/user-attachments/assets/daa54657-1120-48d1-ac65-f005a97e125c" />
<br/>

- Downscaled very large copied images before storage when they exceed the configured dimension cap.
- Added content fingerprints for duplicate detection, replacing duplicate lookup through all loaded decorators.
- Added pre-rendered thumbnail bytes for image history items.
- Added a fingerprint unit test verifying transient pasteboard types and content order do not affect fingerprint equality.

## Before Testing

This branch adds optional SwiftData fields for fingerprints and thumbnails. Existing stores should be eligible for lightweight migration.

The local `MaccyPatched.app` test build still uses Maccy's existing storage path because storage is hardcoded to `~/Library/Application Support/Maccy/Storage.sqlite`, so back up the local store before testing with important clipboard history.

```bash
STORAGE_DIR="$HOME/Library/Application Support/Maccy"
BACKUP_DIR="$HOME/Desktop/MaccyBackup/$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"
for file in \
  "$STORAGE_DIR/Storage.sqlite" \
  "$STORAGE_DIR/Storage.sqlite-shm" \
  "$STORAGE_DIR/Storage.sqlite-wal"
do
  [ -e "$file" ] && cp -v "$file" "$BACKUP_DIR/"
done
```

## Testing

- Built Release configuration and installed a local side-by-side test app with:

```bash
set -euo pipefail

APP_NAME="MaccyPatched"
BUILD_DIR="/tmp/MaccyPatchedBuild"
APP="$HOME/Applications/$APP_NAME.app"
SOURCE_APP="$BUILD_DIR/Build/Products/Release/Maccy.app"
PLIST="$APP/Contents/Info.plist"

set_plist() {
  local key="$1"
  local type="$2"
  local value="$3"

  /usr/libexec/PlistBuddy -c "Set :$key $value" "$PLIST" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$PLIST"
}

pkill -x Maccy || true
pkill -f "$APP" || true

xcodebuild \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build

mkdir -p "$HOME/Applications"
rm -rf "$APP"
cp -R "$SOURCE_APP" "$APP"

set_plist CFBundleIdentifier string "org.p0deje.$APP_NAME"
set_plist CFBundleName string "$APP_NAME"
set_plist CFBundleDisplayName string "$APP_NAME"
set_plist SUEnableAutomaticChecks bool false

codesign --force --deep --sign - "$APP"
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"

open -a "$APP"
```

- The command above builds `Maccy.app`, installs it locally as `MaccyPatched.app`, patches the local test bundle metadata, signs it ad hoc, clears quarantine attributes, verifies the signature, and opens it.
- It stops any running `Maccy` or `MaccyPatched` process first because the local side-by-side build still uses Maccy's shared storage path.
- Tested with a full dataset (3000 items) to validate performance and memory behavior under maximum load.
- Tested large text previews ranging from 95 KB to 150 MB.
- Tested search performance with hundreds of results.
- Verified idle close/reopen and Settings open/close behavior.
- Verified status-bar first-open behavior and popup placement across MacBook display and external monitor.
- Verified stable scroll behavior after reverting the aggressive moving window to a fixed storage-limit-sized window.

## Screenshots

### 1. Initial idle after launch: around 47.9 MB
<img width="1072" height="752" alt="Initial idle around 47.9 MB" src="https://github.com/user-attachments/assets/9cc4a80f-eab7-469f-b8d3-6c00026e794a" />

### 2. Temporary memory peak during activity/scroll: around 150.4 MB
<img width="1072" height="752" alt="Temporary memory peak around 150.4 MB" src="https://github.com/user-attachments/assets/31dbb6eb-ebcc-4764-a439-607ee0130851" />

### 3. Warm idle after normal use: around 101.7 MB
<img width="1072" height="752" alt="Warm idle around 101.7 MB" src="https://github.com/user-attachments/assets/a3c7bde6-c153-48a5-b43c-7880f48df42d" />

### 4. Final warm idle after idle cleanup: around 93.3 MB
<img width="1072" height="752" alt="Final warm idle around 93.3 MB" src="https://github.com/user-attachments/assets/b83ae5ac-a741-47c5-9da4-159a249bb28f" />

## Notes

- The in-memory unpinned window intentionally follows the configured storage limit. A smaller moving window reduced memory further in theory, but caused SwiftUI scroll instability and occasional blank-list behavior during testing, so this patch keeps the stable approach.
- Full-history search no longer mutates the paginated browse list. A future cleanup could move more of the search work off the main actor.
- Image resizing and thumbnail generation currently rely on AppKit APIs. A future cleanup could move this to ImageIO/CoreGraphics for safer background rendering.

## Important Note

This repository is a fork of the original [Maccy](https://maccy.app) project. It is not affiliated with, endorsed by, or maintained by the original Maccy project, and the original Maccy maintainers are not responsible for changes made in this fork.