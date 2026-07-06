import AppKit
import Defaults
import SwiftUI

/// Detail pane for a single history item: a large image preview (or scrolling
/// text), followed by metadata (source application and copy timestamps).
struct PreviewItemView: View {
  var item: HistoryItemDecorator

  /// Wraps preview content with aspect-fit sizing and rounded corners.
  @ViewBuilder
  func previewImage(content: () -> some View) -> some View {
    content()
      .aspectRatio(contentMode: .fit)
      .clipShape(.rect(cornerRadius: 5))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if item.hasImage {
        AsyncView<NSImage?, _, _> {
          return await item.asyncGetPreviewImage()
        } content: { image in
          if let image = image {
            previewImage {
              Image(nsImage: image)
                .resizable()
            }
          } else {
            previewImage {
              ZStack {
                Color.gray.opacity(0.3)
                  .frame(
                    idealWidth: HistoryItemDecorator.previewImageSize.width,
                    idealHeight: HistoryItemDecorator.previewImageSize.height
                  )
                Image(systemName: "photo.badge.exclamationmark")
                  .symbolRenderingMode(.multicolor)
                  .frame(alignment: .center)
              }
            }
          }
        } placeholder: {
          previewImage {
            ZStack {
              Color.gray.opacity(0.3)
                .frame(
                  idealWidth: HistoryItemDecorator.previewImageSize.width,
                  idealHeight: HistoryItemDecorator.previewImageSize.height
                )
              ProgressView()
                .frame(alignment: .center)
            }
          }
        }
      } else if item.needsScrollablePreview {
        PreviewTextRep(
          text: item.item.searchText ?? item.text,
          query: item.previewBodyQuery,
          ranges: item.previewBodyRanges
        )
      } else {
        ScrollView {
          if let preview = item.previewAttributedText {
            Text(preview)
              .font(.body)
          } else {
            Text(item.text)
              .font(.body)
          }
        }
      }

      Spacer(minLength: 0)

      Divider()
        .padding(.vertical)

      if let application = item.application {
        HStack(spacing: 3) {
          Text("Application", tableName: "PreviewItemView")
          AppImageView(
            appImage: item.applicationImage,
            size: NSSize(width: 11, height: 11)
          )
          Text(application)
        }
      }

      HStack(spacing: 3) {
        Text("FirstCopyTime", tableName: "PreviewItemView")
        Text(item.item.firstCopiedAt, style: .date)
        Text(item.item.firstCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("LastCopyTime", tableName: "PreviewItemView")
        Text(item.item.lastCopiedAt, style: .date)
        Text(item.item.lastCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("NumberOfCopies", tableName: "PreviewItemView")
        Text(String(item.item.numberOfCopies))
      }
    }
    .controlSize(.small)
  }
}

/// Scrollable plain-text preview backed by `NSTextView`.
///
/// Unlike SwiftUI `Text`, which eagerly lays out the whole string (the reason
/// `textPreviewLimit` caps the preview window), `NSTextView`'s `NSLayoutManager`
/// lays out only the visible glyph range. The full search body can therefore be
/// held without an eager-layout memory spike, and a deep match — one past the
/// `Text` window — is visible and scrolled into view.
struct PreviewTextRep: NSViewRepresentable {
  /// Full body text to display (the item's `searchText`).
  let text: String
  /// The active search query (gates highlighting).
  let query: String
  /// Body-relative grapheme ranges to highlight.
  let ranges: [Range<Int>]

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    if let textView = scrollView.documentView as? NSTextView {
      configure(textView)
    }
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }
    configure(textView)
  }

  private func configure(_ textView: NSTextView) {
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.isRichText = true
    textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    textView.textStorage?.setAttributedString(buildAttributed())
    scrollToFirstHighlight(in: textView)
  }

  /// Builds the displayed attributed string: the full `text` with `ranges`
  /// styled per the user's highlight preference. Grapheme offsets are converted
  /// to UTF-16 `NSRange`s via `NSRange(_:in:)`, so highlights land correctly on
  /// emoji and combining marks (not just ASCII).
  func buildAttributed() -> NSAttributedString {
    let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let body = NSMutableAttributedString(string: text, attributes: [
      .font: baseFont,
      .foregroundColor: NSColor.labelColor
    ])
    guard !query.isEmpty else { return body }
    let style = Defaults[.highlightMatch]
    let textCount = text.count
    for range in ranges {
      let lower = range.lowerBound
      let upper = min(range.upperBound, textCount)
      guard lower < textCount, lower < upper else { continue }
      let lowerIdx = text.index(text.startIndex, offsetBy: lower)
      let upperIdx = text.index(text.startIndex, offsetBy: upper)
      let nsRange = NSRange(lowerIdx..<upperIdx, in: text)
      switch style {
      case .bold:
        body.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize), range: nsRange)
      case .italic:
        let italic = NSFontManager.shared.convert(baseFont, hasTrait: .italicFontMask) ?? baseFont
        body.addAttribute(.font, value: italic, range: nsRange)
      case .underline:
        body.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
      default:
        body.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: nsRange)
        body.addAttribute(.foregroundColor, value: NSColor.black, range: nsRange)
      }
    }
    return body
  }

  private func scrollToFirstHighlight(in textView: NSTextView) {
    guard !query.isEmpty, let first = ranges.first, first.lowerBound < text.count else { return }
    let idx = text.index(text.startIndex, offsetBy: first.lowerBound)
    textView.scrollRangeToVisible(NSRange(idx..<idx, in: text))
  }
}
