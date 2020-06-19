import SwiftUI

@available(macOS 10.15, *)
extension KeyboardShortcuts {
	/**
	A SwiftUI `View` that lets the user record a keyboard shortcut.

	You would usually put this in your preferences window.

	It automatically prevents choosing a keyboard shortcut that is already taken by the system or by the app's main menu by showing a user-friendly alert to the user.

	It takes care of storing the keyboard shortcut in `UserDefaults` for you.

	```
	import SwiftUI
	import KeyboardShortcuts

	struct PreferencesView: View {
		var body: some View {
			HStack {
				Text("Toggle Unicorn Mode:")
				KeyboardShortcuts.Recorder(for: .toggleUnicornMode)
			}
		}
	}
	```
	*/
	public struct Recorder: NSViewRepresentable { // swiftlint:disable:this type_name
		/// :nodoc:
		public typealias NSViewType = RecorderCocoa

		private let name: Name

		public init(for name: Name) {
			self.name = name
		}

		/// :nodoc:
		public func makeNSView(context: Context) -> NSViewType { .init(for: name) }

		/// :nodoc:
		public func updateNSView(_ nsView: NSViewType, context: Context) {}
	}
}

@available(macOS 10.15, *)
struct SwiftUI_Previews: PreviewProvider {
    static var previews: some View {
		KeyboardShortcuts.Recorder(for: .Name("xcodePreview"))
    }
}
