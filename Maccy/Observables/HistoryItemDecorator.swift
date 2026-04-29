import AppKit.NSWorkspace
import Defaults
import Foundation
import Observation
import Sauce

@Observable
class HistoryItemDecorator: Identifiable, Hashable, HasVisibility {
  private static let listTitleLimit = 160
  static let previewTextPageSize = 500

  static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  static var previewImageSize: NSSize { NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536) }
  static var thumbnailImageSize: NSSize { NSSize(width: 340, height: Defaults[.imageMaxHeight]) }

  let id = UUID()

  var title: String = ""
  var displayTitle: String = ""
  var attributedTitle: AttributedString?

  var isVisible: Bool = true
  var selectionIndex: Int = -1
  var isSelected: Bool {
    return selectionIndex != -1
  }
  var shortcuts: [KeyShortcut] = []

  var application: String? {
    if item.universalClipboard {
      return "iCloud"
    }

    guard let bundle = item.application,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
    else {
      return nil
    }

    return url.deletingPathExtension().lastPathComponent
  }

  // Type-only check. Do not touch `value` here; preview layout can be built
  // during hover/selection and blob hydration would block scrolling.
  var hasImage: Bool { item.hasImageDataType }

  var previewImageGenerationTask: Task<(), Error>?
  var thumbnailImageGenerationTask: Task<Void, Never>?
  var previewImage: NSImage?
  var thumbnailImage: NSImage?
  var applicationImage: ApplicationImage

  var dataSize: String {
    let bytes = item.contents.reduce(0) { total, content in
      total + (content.value?.count ?? 0)
    }
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }

  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }
  var shouldAutoOpenPreview: Bool {
    hasImage || item.title.count <= Self.previewTextPageSize
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(displayTitle)
    hasher.combine(attributedTitle)
  }

  private(set) var item: HistoryItem

  private var applicationImageRefreshed = false
  @ObservationIgnored
  private var debouncedSelectionLoadTask: Task<Void, Never>?
  // Observation handlers are heavy to register at scale (100 items per
  // pagination batch × 2 observers each). Defer setup until the row first
  // appears — most items in the loaded set never become visible at all.
  @ObservationIgnored
  private var observationStarted = false

  init(_ item: HistoryItem, shortcuts: [KeyShortcut] = []) {
    self.item = item
    self.shortcuts = shortcuts
    self.title = item.title
    self.displayTitle = Self.listTitle(from: item.title)
    self.applicationImage = ApplicationImageCache.shared.getImage(bundleIdentifier: item.application)
    // synchronizeItemPin / synchronizeItemTitle are deferred to first
    // .onAppear via `startObservationIfNeeded()` — they're observer setup,
    // not initial state, and registering them eagerly was the bulk of
    // pagination's per-page cost.
  }

  @MainActor
  func startObservationIfNeeded() {
    guard !observationStarted else { return }
    observationStarted = true
    synchronizeItemPin()
    synchronizeItemTitle()
  }

  @MainActor
  func cancelSelectionLoad() {
    debouncedSelectionLoadTask?.cancel()
    debouncedSelectionLoadTask = nil
  }

  @MainActor
  func refreshApplicationImageIfNeeded() {
    guard !applicationImageRefreshed else { return }
    applicationImageRefreshed = true
    let refreshed = ApplicationImageCache.shared.getImage(item: item)
    if refreshed !== applicationImage {
      applicationImage = refreshed
    }
  }

  @MainActor
  func previewText(upTo maxLength: Int) -> String {
    return item.previewableText(upTo: maxLength)
  }

  @MainActor
  func hasMorePreviewText(after maxLength: Int) -> Bool {
    return item.hasPreviewableText(after: maxLength)
  }

  // Fast path only. Reads the pre-rendered `thumbnailData` attribute and
  // decodes it off the scroll path so row appearance does not block input.
  // Treats an empty `Data()` as a "known to have no thumbnail" sentinel
  // (text/file items get marked this way during backfill).
  @MainActor
  func ensureThumbnailImage() {
    guard thumbnailImage == nil else { return }
    guard thumbnailImageGenerationTask == nil else { return }
    guard let thumbBytes = item.thumbnailData, !thumbBytes.isEmpty else { return }

    thumbnailImageGenerationTask = Task.detached(priority: .utility) { [weak self] in
      let image = NSImage(data: thumbBytes)
      guard !Task.isCancelled else { return }

      await MainActor.run {
        guard let self else { return }
        self.thumbnailImage = image
        self.thumbnailImageGenerationTask = nil
      }
    }
  }

  // Preview is the explicit "show me the data" path — always loads the full
  // blob. Opportunistically backfills `thumbnailData` while we have the
  // decoded source in hand, so future browse hits the fast path.
  @MainActor
  func ensurePreviewImage() {
    guard previewImage == nil else { return }
    guard previewImageGenerationTask == nil else { return }
    guard let data = item.imageData else { return }
    let targetSize = HistoryItemDecorator.previewImageSize
    let captureItem = item
    let needsThumbnailBackfill = item.thumbnailData == nil
    previewImageGenerationTask = Task.detached(priority: .userInitiated) { [weak self] in
      let resized = Self.rasterizedImage(from: data, targetSize: targetSize)
      let thumbBytes = needsThumbnailBackfill ? HistoryItem.makeThumbnailData(from: data) : nil
      let decodedThumb = thumbBytes.flatMap { NSImage(data: $0) }
      await MainActor.run {
        guard let self else { return }
        if let thumbBytes {
          captureItem.thumbnailData = thumbBytes
          try? Storage.shared.context.save()
        }
        self.previewImage = resized
        if self.thumbnailImage == nil, let decodedThumb {
          self.thumbnailImage = decodedThumb
        }
        self.previewImageGenerationTask = nil
      }
    }
  }

  // Decodes and rasterizes off-main. Returns a bitmap-backed NSImage so that
  // SwiftUI's render pass is a cheap blit, not a re-decode.
  nonisolated private static func rasterizedImage(
    from data: Data,
    targetSize: NSSize
  ) -> NSImage? {
    guard let source = NSImage(data: data) else { return nil }
    let sourceSize = source.size
    guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

    let ratio = min(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
    if ratio >= 1 {
      return source
    }
    let pixelSize = NSSize(
      width: max(1, (sourceSize.width * ratio).rounded()),
      height: max(1, (sourceSize.height * ratio).rounded())
    )

    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(pixelSize.width),
      pixelsHigh: Int(pixelSize.height),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bitmapFormat: [],
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else {
      return source
    }
    rep.size = pixelSize

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return source }
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    source.draw(in: NSRect(origin: .zero, size: pixelSize),
                from: .zero, operation: .copy, fraction: 1)

    let rasterized = NSImage(size: pixelSize)
    rasterized.addRepresentation(rep)
    return rasterized
  }

  @MainActor
  func asyncGetPreviewImage() async -> NSImage? {
    if let image = previewImage {
      return image
    }
    ensurePreviewImage()
    _ = await previewImageGenerationTask?.result
    return previewImage
  }

  @MainActor
  func cleanupImages() {
    thumbnailImageGenerationTask?.cancel()
    previewImageGenerationTask?.cancel()
    thumbnailImage?.recache()
    previewImage?.recache()
    thumbnailImage = nil
    previewImage = nil
    thumbnailImageGenerationTask = nil
    previewImageGenerationTask = nil
  }

  @MainActor
  func cleanupPreviewImage() {
    previewImageGenerationTask?.cancel()
    previewImage?.recache()
    previewImage = nil
    previewImageGenerationTask = nil
  }

  @MainActor
  private func generateThumbnailImage() {
    guard let image = item.image else {
      return
    }
    thumbnailImage = image.resized(to: HistoryItemDecorator.thumbnailImageSize)
  }

  @MainActor
  private func generatePreviewImage() {
    guard let image = item.image else {
      return
    }
    previewImage = image.resized(to: HistoryItemDecorator.previewImageSize)
  }

  @MainActor
  func sizeImages() {
    generatePreviewImage()
    generateThumbnailImage()
  }

  func highlight(_ query: String, _ ranges: [Range<String.Index>]) {
    guard !query.isEmpty, !title.isEmpty else {
      displayTitle = Self.listTitle(from: title)
      attributedTitle = nil
      return
    }

    let visibleRange = Self.visibleRange(in: title, around: ranges.first)
    displayTitle = Self.listTitle(from: title, range: visibleRange)
    var attributedString = AttributedString(displayTitle)
    for range in ranges {
      guard let clippedRange = Self.clippedRange(range, to: visibleRange) else { continue }
      let lowerOffset = title.distance(from: visibleRange.lowerBound, to: clippedRange.lowerBound)
      let upperOffset = title.distance(from: visibleRange.lowerBound, to: clippedRange.upperBound)
      let displayLower = displayTitle.index(displayTitle.startIndex, offsetBy: lowerOffset)
      let displayUpper = displayTitle.index(displayTitle.startIndex, offsetBy: upperOffset)

      if let lowerBound = AttributedString.Index(displayLower, within: attributedString),
         let upperBound = AttributedString.Index(displayUpper, within: attributedString) {
        switch Defaults[.highlightMatch] {
        case .bold:
          attributedString[lowerBound..<upperBound].font = .bold(.body)()
        case .italic:
          attributedString[lowerBound..<upperBound].font = .italic(.body)()
        case .underline:
          attributedString[lowerBound..<upperBound].underlineStyle = .single
        default:
          attributedString[lowerBound..<upperBound].backgroundColor = .findHighlightColor
          attributedString[lowerBound..<upperBound].foregroundColor = .black
        }
      }
    }

    attributedTitle = attributedString
  }

  private static func listTitle(from title: String) -> String {
    return listTitle(from: title, range: visibleRange(in: title, around: nil))
  }

  private static func listTitle(from title: String, range: Range<String.Index>) -> String {
    guard title.count > listTitleLimit else { return title }

    var excerpt = String(title[range])
    if range.lowerBound > title.startIndex {
      excerpt = "..." + excerpt
    }
    if range.upperBound < title.endIndex {
      excerpt += "..."
    }
    return excerpt
  }

  private static func visibleRange(
    in title: String,
    around matchRange: Range<String.Index>?
  ) -> Range<String.Index> {
    guard title.count > listTitleLimit else { return title.startIndex..<title.endIndex }
    guard let matchRange else {
      let end = title.index(title.startIndex, offsetBy: listTitleLimit)
      return title.startIndex..<end
    }

    let matchStartOffset = title.distance(from: title.startIndex, to: matchRange.lowerBound)
    let matchLength = title.distance(from: matchRange.lowerBound, to: matchRange.upperBound)
    let leadingContext = max(0, (listTitleLimit - matchLength) / 2)
    let startOffset = max(0, min(matchStartOffset - leadingContext, title.count - listTitleLimit))
    let start = title.index(title.startIndex, offsetBy: startOffset)
    let end = title.index(start, offsetBy: listTitleLimit, limitedBy: title.endIndex) ?? title.endIndex
    return start..<end
  }

  private static func clippedRange(
    _ range: Range<String.Index>,
    to visibleRange: Range<String.Index>
  ) -> Range<String.Index>? {
    let lower = max(range.lowerBound, visibleRange.lowerBound)
    let upper = min(range.upperBound, visibleRange.upperBound)
    guard lower < upper else { return nil }
    return lower..<upper
  }

  @MainActor
  func togglePin() {
    if item.pin != nil {
      item.pin = nil
    } else {
      let pin = HistoryItem.randomAvailablePin
      item.pin = pin
    }
  }

  private var pendingPinSync = false
  private var pendingTitleSync = false

  private func synchronizeItemPin() {
    guard !pendingPinSync else { return }
    pendingPinSync = true
    _ = withObservationTracking {
      item.pin
    } onChange: {
      DispatchQueue.main.async {
        self.pendingPinSync = false
        if let pin = self.item.pin {
          self.shortcuts = KeyShortcut.create(character: pin)
        }
        self.synchronizeItemPin()
      }
    }
  }

  private func synchronizeItemTitle() {
    guard !pendingTitleSync else { return }
    pendingTitleSync = true
    _ = withObservationTracking {
      item.title
    } onChange: {
      DispatchQueue.main.async {
        self.pendingTitleSync = false
        self.title = self.item.title
        self.displayTitle = Self.listTitle(from: self.item.title)
        self.synchronizeItemTitle()
      }
    }
  }
}
