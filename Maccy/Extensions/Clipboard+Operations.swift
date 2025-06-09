import Defaults
import Sauce

// MARK: - Copy and Paste Operations Extensions
extension Clipboard {
    func clearFormatting(_ contents: [HistoryItemContent]) -> [HistoryItemContent] {
        var newContents: [HistoryItemContent] = contents
        let stringContents = contents.filter { NSPasteboard.PasteboardType($0.type) == .string }

        // If there is no string representation of data,
        // behave like we didn't have to remove formatting.
        if !stringContents.isEmpty {
            newContents = stringContents

            // Preserve file URLs.
            // https://github.com/p0deje/Maccy/issues/962
            let fileURLContents = contents.filter { NSPasteboard.PasteboardType($0.type) == .fileURL }
            if !fileURLContents.isEmpty {
                newContents += fileURLContents
            }
        }

        return newContents
    }

    // Some applications requires window be unfocused and focused back to sync the clipboard.
    // - Chrome Remote Desktop (https://github.com/p0deje/Maccy/issues/948)
    // - Netbeans (https://github.com/p0deje/Maccy/issues/879)
    func sync() {
        guard let app = sourceApp,
              app.bundleURL?.lastPathComponent == "Chrome Remote Desktop.app" ||
                app.localizedName?.contains("NetBeans") == true else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.hide(self)
    }
}
