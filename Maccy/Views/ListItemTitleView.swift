import Defaults
import SwiftUI

// MARK: - Truncation helpers

/// Font matching SwiftUI's default `.body` on macOS.
private let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

/// Truncate a single line by inserting " ... " in the middle if it exceeds maxWidth.
/// Uses NSAttributedString for accurate pixel-width measurement.
func truncateLine(_ text: String, maxWidth: CGFloat) -> String {
  let ellipsis = " ... "
  let attrs: [NSAttributedString.Key: Any] = [.font: bodyFont]

  func width(of s: String) -> CGFloat {
    NSAttributedString(string: s, attributes: attrs).size().width
  }

  guard width(of: text) > maxWidth else { return text }

  let chars = Array(text)

  // Binary search the longest prefix that still allows suffix + ellipsis to fit.
  var lo = 0
  var hi = chars.count / 2
  while lo < hi {
    let mid = (lo + hi + 1) / 2
    let suffixStart = chars.count - mid
    let candidate = String(chars[0..<mid]) + ellipsis + String(chars[suffixStart...])
    if width(of: candidate) <= maxWidth {
      lo = mid
    } else {
      hi = mid - 1
    }
  }

  if lo == 0 {
    // Nothing fits with ellipsis; just cut to width.
    var result = ""
    for ch in chars {
      guard width(of: result + String(ch)) <= maxWidth else { break }
      result += String(ch)
    }
    return result
  }

  let suffixStart = chars.count - lo
  return String(chars[0..<lo]) + ellipsis + String(chars[suffixStart...])
}

/// Truncate multi-line text: split by newlines, take first maxLines lines,
/// truncate each long line individually, join with newlines.
func truncateText(_ raw: String, maxWidth: CGFloat, maxLines: Int) -> String {
  let lines = raw.components(separatedBy: .newlines)
  let capped = lines.prefix(maxLines)
  return capped.map { truncateLine($0, maxWidth: maxWidth) }.joined(separator: "\n")
}

// MARK: - ListItemTitleView

struct ListItemTitleView<Title: View>: View {
  var attributedTitle: AttributedString?
  var rawTitle: String?
  @ViewBuilder var title: () -> Title
  @Default(.titleLines) private var titleLines
  @Default(.windowSize) private var windowSize
  @Default(.showApplicationIcons) private var showIcons

  /// Estimated text area width: window width minus padding for icons, spacers,
  /// shortcuts, and trailing margin.
  private var estimatedTextWidth: CGFloat {
    let base = windowSize.width
    let iconArea: CGFloat = showIcons ? 30 : 15
    let shortcutsArea: CGFloat = 40
    let margin: CGFloat = 20
    return max(base - iconArea - shortcutsArea - margin, 80)
  }

  var body: some View {
    Group {
      if let attributedTitle {
        Text(attributedTitle)
          .accessibilityIdentifier("copy-history-item")
          .lineLimit(titleLines)
          .truncationMode(.middle)
      } else if let rawTitle {
        Text(truncateText(rawTitle, maxWidth: estimatedTextWidth, maxLines: titleLines))
          .accessibilityIdentifier("copy-history-item")
          .lineLimit(titleLines)
      } else {
        title()
          .accessibilityIdentifier("copy-history-item")
          .lineLimit(titleLines)
          .truncationMode(.middle)
          .drawingGroup()
      }
    }
  }
}
