import SwiftUI

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformScreen = NSScreen
#else
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformScreen = UIScreen
#endif
