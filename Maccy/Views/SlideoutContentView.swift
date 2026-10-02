import AppKit
import SwiftUI

struct SplitCandidate: Identifiable, Hashable, Sendable {
  enum Kind: String, Sendable {
    case url
    case email
    case phone
    case number
    case identifier

    var localizedName: String {
      NSLocalizedString("split_element_\(rawValue)", comment: "Split element type")
    }
  }

  let id: String
  let kind: Kind
  let value: String
  let range: NSRange
}

struct SplitLine: Identifiable, Sendable {
  let id: Int
  let value: String
  let displayValue: String
  let elements: [SplitCandidate]
  let elementAnalysisSkipped: Bool
}

struct SplitParseResult: Sendable {
  let lines: [SplitLine]
  let wasTruncated: Bool
}

enum SplitParser {
  private struct Rule {
    let kind: SplitCandidate.Kind
    let regex: NSRegularExpression
    let priority: Int
  }

  private static let rules: [Rule] = [
    Rule(
      kind: .url,
      regex: try! NSRegularExpression(pattern: #"(?i)(?:https?://|www\.)[^\s<>\"'，。！？、；：）》】]+"#),
      priority: 0
    ),
    Rule(
      kind: .email,
      regex: try! NSRegularExpression(pattern: #"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#),
      priority: 1
    ),
    Rule(
      kind: .phone,
      regex: try! NSRegularExpression(pattern: #"(?:\+?86[\s-]?)?1[3-9]\d{9}"#),
      priority: 2
    ),
    Rule(
      kind: .number,
      regex: try! NSRegularExpression(pattern: #"[-+]?\d+(?:\.\d+)?%?"#),
      priority: 3
    ),
    Rule(
      kind: .identifier,
      regex: try! NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9_.-]{2,}"#),
      priority: 4
    )
  ]

  // Keep parsing bounded. A clipboard item can contain a very large log or
  // generated document; rendering and regex-scanning all of it on the popup's
  // main thread makes the panel appear frozen.
  private static let maxDisplayedLines = 500
  private static let maxAnalyzedCharacters = 2_000_000
  private static let maxElementAnalysisCharacters = 200_000
  private static let maxRenderedLineCharacters = 4_000

  static func parse(_ text: String) -> SplitParseResult {
    // Do not materialize or scan an unbounded single-line clipboard item just
    // to discover that it is too large to render. Keep one extra character so
    // the UI can distinguish an exact-limit input from truncated content.
    let boundedPrefix = text.prefix(maxAnalyzedCharacters + 1)
    let inputWasTruncated = boundedPrefix.count > maxAnalyzedCharacters
    let boundedText = inputWasTruncated
      ? String(boundedPrefix.dropLast())
      : String(boundedPrefix)

    var lines: [SplitLine] = []
    lines.reserveCapacity(min(maxDisplayedLines, 32))
    var analyzedCharacters = 0
    var wasTruncated = inputWasTruncated

    for rawLine in boundedText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
      let line = String(rawLine)
      guard !line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else { continue }

      let tooLongForElements = line.count > maxElementAnalysisCharacters
      let elements = tooLongForElements ? [] : self.elements(line)
      let displayValue = line.count > maxRenderedLineCharacters
        ? String(line.prefix(maxRenderedLineCharacters)) + "…"
        : line
      lines.append(
        SplitLine(
          id: lines.count,
          value: line,
          displayValue: displayValue,
          elements: elements,
          elementAnalysisSkipped: tooLongForElements
        )
      )
      analyzedCharacters += line.count

      if lines.count >= maxDisplayedLines || analyzedCharacters >= maxAnalyzedCharacters {
        wasTruncated = true
        break
      }
    }

    return SplitParseResult(lines: lines, wasTruncated: wasTruncated)
  }

  static func elements(_ line: String) -> [SplitCandidate] {
    guard !line.isEmpty else { return [] }

    let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
    var matches: [(priority: Int, range: NSRange, kind: SplitCandidate.Kind, value: String)] = []

    for rule in rules {
      for match in rule.regex.matches(in: line, range: fullRange) {
        guard let swiftRange = Range(match.range, in: line) else { continue }
        let rawValue = String(line[swiftRange])
        let trimCharacters = CharacterSet(charactersIn: ".,，。！？；：、)】]}>\"'")
        var valueStart = rawValue.startIndex
        while valueStart < rawValue.endIndex,
          rawValue[valueStart].unicodeScalars.allSatisfy(trimCharacters.contains) {
          valueStart = rawValue.index(after: valueStart)
        }
        var valueEnd = rawValue.endIndex
        while valueEnd > valueStart {
          let previous = rawValue.index(before: valueEnd)
          guard rawValue[previous].unicodeScalars.allSatisfy(trimCharacters.contains) else { break }
          valueEnd = previous
        }
        let value = String(rawValue[valueStart..<valueEnd])
        guard !value.isEmpty else { continue }
        let absoluteValueStart = line.index(
          swiftRange.lowerBound,
          offsetBy: rawValue.distance(from: rawValue.startIndex, to: valueStart)
        )
        let absoluteValueEnd = line.index(
          swiftRange.lowerBound,
          offsetBy: rawValue.distance(from: rawValue.startIndex, to: valueEnd)
        )
        let valueRange = NSRange(absoluteValueStart..<absoluteValueEnd, in: line)
        matches.append((rule.priority, valueRange, rule.kind, value))
      }
    }

    let ordered = matches.sorted {
      if $0.range.location == $1.range.location {
        return $0.priority < $1.priority
      }
      return $0.range.location < $1.range.location
    }

    var occupied = IndexSet()
    return ordered.compactMap { match in
      let range = match.range.location..<(match.range.location + match.range.length)
      guard !range.contains(where: occupied.contains) else { return nil }
      occupied.insert(integersIn: range)
      return SplitCandidate(
        id: "\(match.kind.rawValue)-\(match.range.location)-\(match.value)",
        kind: match.kind,
        value: match.value,
        range: match.range
      )
    }
  }
}

private struct SplitInlineSegment: Identifiable {
  let id: String
  let text: String
  let element: SplitCandidate?
}

private struct InlineFlowLayout: Layout {
  var spacing: CGFloat = 4

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let result = layout(proposalWidth: proposal.width, subviews: subviews)
    return result.size
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let result = layout(proposalWidth: bounds.width, subviews: subviews)
    for (index, frame) in result.frames.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading,
        proposal: ProposedViewSize(width: frame.width, height: frame.height)
      )
    }
  }

  private func layout(proposalWidth: CGFloat?, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
    let availableWidth = proposalWidth ?? .greatestFiniteMagnitude
    var frames: [CGRect] = []
    frames.reserveCapacity(subviews.count)
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var contentWidth: CGFloat = 0

    for subview in subviews {
      var size = subview.sizeThatFits(.unspecified)
      if size.width > availableWidth {
        size = subview.sizeThatFits(ProposedViewSize(width: availableWidth, height: nil))
      }

      if x > 0, x + size.width > availableWidth {
        y += rowHeight + spacing
        x = 0
        rowHeight = 0
      }

      frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
      contentWidth = max(contentWidth, max(0, x - spacing))
    }

    return (frames, CGSize(width: proposalWidth ?? contentWidth, height: y + rowHeight))
  }
}

private struct SplitInlineLineView: View {
  let line: SplitLine
  let onCopy: (String) -> Void

  private var segments: [SplitInlineSegment] {
    let visibleLength = (line.displayValue as NSString).length
    let orderedElements = line.elements
      .filter { $0.range.location >= 0 && NSMaxRange($0.range) <= visibleLength }
      .sorted { $0.range.location < $1.range.location }

    var segments: [SplitInlineSegment] = []
    var cursor = 0

    for element in orderedElements {
      guard element.range.location >= cursor else { continue }
      if element.range.location > cursor {
        let plainRange = NSRange(location: cursor, length: element.range.location - cursor)
        segments.append(
          SplitInlineSegment(
            id: "plain-\(plainRange.location)",
            text: (line.displayValue as NSString).substring(with: plainRange),
            element: nil
          )
        )
      }

      let visibleElementValue = (line.displayValue as NSString).substring(with: element.range)
      segments.append(
        SplitInlineSegment(
          id: element.id,
          text: visibleElementValue,
          element: element
        )
      )
      cursor = NSMaxRange(element.range)
    }

    if cursor < visibleLength {
      let plainRange = NSRange(location: cursor, length: visibleLength - cursor)
      segments.append(
        SplitInlineSegment(
          id: "plain-\(plainRange.location)",
          text: (line.displayValue as NSString).substring(with: plainRange),
          element: nil
        )
      )
    }

    return segments.isEmpty
      ? [SplitInlineSegment(id: "plain-0", text: line.displayValue, element: nil)]
      : segments
  }

  var body: some View {
    InlineFlowLayout(spacing: 4) {
      ForEach(segments) { segment in
        if let element = segment.element {
          Button {
            onCopy(element.value)
          } label: {
            Text(segment.text)
              .font(.caption2)
              .lineLimit(1)
              .padding(.horizontal, 7)
              .padding(.vertical, 2)
              .background(Color.accentColor.opacity(0.12), in: Capsule())
          }
          .buttonStyle(.plain)
          .foregroundStyle(.primary)
          .help(String(format: NSLocalizedString("split_copy_element", comment: "Copy a split element"), element.kind.localizedName, element.value))
          .accessibilityLabel(Text(String(format: NSLocalizedString("split_copy_element", comment: "Copy a split element"), element.kind.localizedName, element.value)))
        } else {
          Text(segment.text)
            .font(.caption)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct SplitDetailView: View {
  let item: HistoryItemDecorator
  let onClose: () -> Void

  @Environment(AppState.self) private var appState
  @State private var parsedLines: [SplitLine] = []
  @State private var isParsing = true
  @State private var wasTruncated = false

  private func copy(_ value: String) {
    Clipboard.shared.copyInMaccy(value, recordInHistory: false)
    onClose()
    // Close after the pasteboard write and SwiftUI state update have completed.
    // Doing it in the same event turn can be undone by the popup's selection update.
    DispatchQueue.main.async {
      appState.popup.close()
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "text.badge.plus")
          .foregroundStyle(.secondary)
        Text("split_results")
          .font(.caption.weight(.semibold))
        Text("split_results_hint")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Button("split_collapse", action: onClose)
          .buttonStyle(.plain)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if isParsing {
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.small)
            Text("split_parsing")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      } else if parsedLines.isEmpty {
        Text("split_no_text")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.vertical, 4)
      } else {
        if wasTruncated {
          Text(String(format: NSLocalizedString("split_truncated", comment: "Truncated split result"), parsedLines.count))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        ScrollView(.vertical) {
          LazyVStack(alignment: .leading, spacing: 5) {
            ForEach(parsedLines) { line in
              VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                  Text("\(line.id + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)

                  SplitInlineLineView(line: line, onCopy: copy)

                  Button {
                    copy(line.value)
                  } label: {
                    Image(systemName: "doc.on.doc")
                      .font(.caption)
                  }
                  .buttonStyle(.plain)
                  .foregroundStyle(.secondary)
                  .help(NSLocalizedString("split_copy_whole_line", comment: "Copy a whole split line"))
                  .accessibilityLabel(Text(String(format: NSLocalizedString("split_copy_line", comment: "Copy a split line"), line.id + 1)))
                }

                if line.elementAnalysisSkipped {
                  Text("split_long_line")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
                }
              }
              .padding(.horizontal, 7)
              .padding(.vertical, 5)
              .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 6))
            }
          }
        }
        .frame(maxHeight: .infinity)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .task(id: item.id) {
      isParsing = true
      parsedLines = []
      wasTruncated = false

      let text = item.previewText
      let result = await Task.detached(priority: .userInitiated) {
        SplitParser.parse(text)
      }.value

      guard !Task.isCancelled else { return }
      parsedLines = result.lines
      wasTruncated = result.wasTruncated
      isParsing = false
    }
    .transition(.opacity.combined(with: .move(edge: .top)))
  }
}

struct SlideoutContentView: View {
  @Environment(AppState.self) var appState

  var body: some View {
    VStack {
      ToolbarView()

      if let splitItem = appState.preview.splitItem {
        SplitDetailView(item: splitItem) {
          appState.preview.closeSplit()
        }
      } else if let item = appState.navigator.leadHistoryItem {
        PreviewItemView(item: item)
      } else if let pasteStack = appState.history.pasteStack,
        appState.navigator.pasteStackSelected {
        PasteStackPreviewView(pasteStack: pasteStack)
      } else {
        EmptyView()
      }
    }
    .padding(.horizontal)
    .padding(.bottom)
    .padding(.top, Popup.verticalPadding)
  }
}
