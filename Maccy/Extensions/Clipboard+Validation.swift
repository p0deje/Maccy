import Defaults
import Foundation

// MARK: - Pasteboard Validation Extensions
extension Clipboard {
    func shouldIgnore(_ types: Set<NSPasteboard.PasteboardType>) -> Bool {
        let ignoredTypes = self.ignoredTypes
            .union(Defaults[.ignoredPasteboardTypes].map({ NSPasteboard.PasteboardType($0) }))

        return types.isDisjoint(with: enabledTypes) ||
            !types.isDisjoint(with: ignoredTypes)
    }

    func shouldIgnore(_ sourceAppBundle: String) -> Bool {
        if Defaults[.ignoreAllAppsExceptListed] {
            return !Defaults[.ignoredApps].contains(sourceAppBundle)
        } else {
            return Defaults[.ignoredApps].contains(sourceAppBundle)
        }
    }

    func shouldIgnore(_ item: NSPasteboardItem) -> Bool {
        for regexp in Defaults[.ignoreRegexp] {
            if let string = item.string(forType: .string) {
                do {
                    let regex = try NSRegularExpression(pattern: regexp)
                    if regex.numberOfMatches(in: string, range: NSRange(string.startIndex..., in: string)) > 0 {
                        return true
                    }
                } catch {
                    return false
                }
            }
        }
        return false
    }

    func isEmptyString(_ item: NSPasteboardItem) -> Bool {
        guard let string = item.string(forType: .string) else {
            return true
        }

        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func richText(_ item: NSPasteboardItem) -> Bool {
        if let rtf = item.data(forType: .rtf) {
            if let attributedString = NSAttributedString(rtf: rtf, documentAttributes: nil) {
                return !attributedString.string.isEmpty
            }
        }

        if let html = item.data(forType: .html) {
            if let attributedString = NSAttributedString(html: html, documentAttributes: nil) {
                return !attributedString.string.isEmpty
            }
        }

        return false
    }
}
