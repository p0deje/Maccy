import Cocoa

public struct PreferencePaneIdentifier: Hashable, RawRepresentable, Codable {
	public typealias Identifier = PreferencePaneIdentifier

	public let rawValue: String

	public init(rawValue: String) {
		self.rawValue = rawValue
	}
}

public protocol PreferencePane: NSViewController {
	typealias Identifier = PreferencePaneIdentifier

	var preferencePaneIdentifier: Identifier { get }
	var preferencePaneTitle: String { get }
	var toolbarItemIcon: NSImage { get }
}

extension PreferencePane {
	public var toolbarItemIdentifier: NSToolbarItem.Identifier {
		preferencePaneIdentifier.toolbarItemIdentifier
	}

	public var toolbarItemIcon: NSImage { .empty }
}

extension PreferencePane.Identifier {
	public init(_ rawValue: String) {
		self.init(rawValue: rawValue)
	}

	public init(fromToolbarItemIdentifier itemIdentifier: NSToolbarItem.Identifier) {
		self.init(rawValue: itemIdentifier.rawValue)
	}

	public var toolbarItemIdentifier: NSToolbarItem.Identifier {
		NSToolbarItem.Identifier(rawValue)
	}
}
