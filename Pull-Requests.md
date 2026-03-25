gh repo clone p0deje/Maccy
cd Maccy

## Code signing identity

security find-identity -p codesigning -v

## Command line build

xcodebuild -project Maccy.xcodeproj \
  -scheme Maccy \
  -configuration Release \
  -derivedDataPath /tmp/Maccy_DerivedData_$(date +%s)

## Code signing

codesign --force --deep -o runtime \
  --sign "Apple Development: mithun@gmx.net (YCZ77TRJ73)" \
  "Maccy.app/Contents/Frameworks/Sparkle.framework"

codesign --force --deep -o runtime \
  --sign "Apple Development: mithun@gmx.net (YCZ77TRJ73)" \
  "Maccy.app"

## Check code signing
codesign -dv --verbose=4 "Maccy.app" 2>&1 | grep TeamIdentifier
codesign -dv --verbose=4 "Maccy.app/Contents/Frameworks/Sparkle.framework" 2>&1 | grep TeamIdentifier

## Template

git fetch origin pull/xxxx/head:xxxx
git merge --no-ff --no-commit xxxx
git commit -m 'Some comment'

## Working PRs

git fetch origin pull/1110/head:1110
git merge --no-ff --no-commit 1110
git commit -m 'Customize preview item character limit and size'

git fetch origin pull/1149/head:1149
git merge --no-ff --no-commit 1149
git commit -m 'Adds privacy mode setting with fixes for DisplayLink issues'

git fetch origin pull/1152/head:extracttext
git merge --no-ff --no-commit extracttext
git commit -m 'Add extract text from image feature to clipboard preview'

git fetch origin pull/1262/head:1262
git merge --no-ff --no-commit 1262
git commit -m 'Unlimited history'

git fetch origin pull/1320/head:1320
git merge --no-ff --no-commit 1320
git commit -m 'Clipboard Accumulation'

git fetch origin pull/1324/head:1324
git merge --no-ff --no-commit 1324
git commit -m 'Enable paste stack'

git fetch origin pull/1325/head:1325
git merge --no-ff --no-commit 1325
git commit -m 'Use correct icon for preview toggle button'

git fetch origin pull/1328/head:1328
git merge --no-ff --no-commit 1328
git commit -m 'Fix: show red border for invalid history size input'

git fetch origin pull/1329/head:1329
git merge --no-ff --no-commit 1329
git commit -m 'Fix OpenPreferencesWarning text overflow on long localizations'

git fetch origin pull/1338/head:1338
git merge --no-ff --no-commit 1338
git commit -m 'Add Hex Color Swatch Show Setting in Preferences'

git fetch origin pull/1342/head:1342
git merge --no-ff --no-commit 1342
git commit -m 'Perf: use in-memory cache instead of full DB fetch in findSimilarItem'

git fetch origin pull/1345/head:1345
git merge --no-ff --no-commit 1345
git commit -m 'Ignore rule for clipboard entries based on plain-text length'

git fetch origin pull/1357/head:1357
git merge --no-ff --no-commit 1357
git commit -m 'Show image dimensions in preview'

git fetch origin pull/1358/head:1358
git merge --no-ff --no-commit 1358
git commit -m 'Fix clipboard/source attribution, history edge cases, and storage recovery'

## With workarounds

git fetch origin pull/1322/head:1322
git merge --no-ff --no-commit 1322
git commit -m 'Feature: Sort pins alphabetically at both, popup and panels'

git fetch origin pull/1356/head:1356
git merge --no-ff --no-commit 1356
git commit -m 'Add Tag Feature'

# Miscellaneous Git commands

git add .
git commit -m 'Added sort by pin case to pagination'
git reset HEAD~

## Not working PRs

git fetch origin pull/1078/head:1078
git merge --no-ff --no-commit 1078
git commit -m 'Add Secret Functionality with Keyboard Shortcut and UI Updates'

git fetch origin pull/1178/head:pushpasted
git merge --no-ff --no-commit pushpasted
git commit -m 'Add option to push pasted item to bottom of the list'

git fetch origin pull/1206/head:1206
git merge --no-ff --no-commit 1206
git commit -m 'Implement paste stack'

git fetch origin pull/1218/head:previewimage
git merge --no-ff --no-commit previewimage
git commit -m 'Add preview image size setting and update related UI components'

git fetch origin pull/1221/head:tabbed
git merge --no-ff --no-commit tabbed
git commit -m 'Add tabs and improve window sizing'

git fetch origin pull/1247/head:uipolish
git merge --no-ff --no-commit uipolish
git commit -m 'UI polish improvements'

git fetch origin pull/1262/head:1262
git merge --no-ff --no-commit 1262
git commit -m 'Unlimited History'

git fetch origin pull/1265/head:1265
git merge --no-ff --no-commit 1265
git commit -m 'Re-arrange pins using Option keys'

git fetch origin pull/1318/head:1318
git merge --no-ff --no-commit 1318
git commit -m 'Add item editing functionality'
