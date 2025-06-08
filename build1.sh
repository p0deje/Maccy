killall Maccy 2>/dev/null || true
cd /Users/promex04/Documents/CodeStore/Maccy && xcodebuild -project Maccy.xcodeproj -scheme Maccy -configuration Debug build CODE_SIGNING_ALLOWED=NO
cd /Users/promex04/Documents/CodeStore/Maccy && open /Users/promex04/Library/Developer/Xcode/DerivedData/Maccy-ejogudfzsnhcvydvldwnibmcizxu/Build/Products/Debug/Maccy.app