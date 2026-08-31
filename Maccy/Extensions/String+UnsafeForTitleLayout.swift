import Foundation

extension String {
  // Unicode scalars that are known to hang CoreText's line truncation on
  // macOS 26. See https://github.com/p0deje/Maccy/issues/1520.
  //
  // U+FFFC OBJECT REPLACEMENT CHARACTER is the placeholder for an inline
  // attachment, so rich text with embedded images (chat messages with inline
  // emoticons, Notes, Mail) carries one per attachment in its plain text
  // flavor. Two or more of them next to non-Latin text send
  // __NSCoreTypesetterTruncateLine into an infinite loop when the text is
  // laid out with .lineLimit(1) and .truncationMode(.middle), pinning a core
  // at 100% CPU with no way to recover from inside the app.
  private static let scalarsUnsafeForTitleLayout: Set<Unicode.Scalar> = [
    "\u{FFFC}"
  ]

  var containsScalarsUnsafeForTitleLayout: Bool {
    unicodeScalars.contains { String.scalarsUnsafeForTitleLayout.contains($0) }
  }

  // Filtering happens per Unicode scalar rather than per Character on purpose.
  // U+FFFC followed by a combining mark forms a single grapheme cluster, so
  // comparing Characters would leave the unsafe scalar in place and the hang
  // would survive.
  func removingScalarsUnsafeForTitleLayout() -> String {
    guard containsScalarsUnsafeForTitleLayout else {
      return self
    }

    var scalars = String.UnicodeScalarView()
    for scalar in unicodeScalars where !String.scalarsUnsafeForTitleLayout.contains(scalar) {
      scalars.append(scalar)
    }

    return String(scalars)
  }
}
