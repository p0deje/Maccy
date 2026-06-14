import AppKit
import Foundation

/// Abstracts pasteboard reading so the ingest pipeline can run off the main thread
/// and so it can be unit-tested with `PasteboardSimulator`.
///
/// The production conformer (`NSPasteboardSource`) wraps `NSPasteboard.general`;
/// the test conformer (`PasteboardSimulator` in the test module) returns injected
/// snapshots. Either way the ingestor sees a uniform, `Sendable` API: a change
/// counter to detect new copies and a `snapshot()` that materializes the current
/// contents into plain value types. Because everything returned is already a
/// value type, the caller can hand the result to a background actor without
/// touching `NSPasteboard` again.
protocol PasteboardSource: Sendable {
  /// Monotonic counter that increments whenever the pasteboard changes.
  /// Mirrors `NSPasteboard.changeCount`; the ingestor compares it to its last
  /// seen value to decide whether to read.
  var changeCount: Int { get }

  /// Materializes every pasteboard item currently on the pasteboard into a
  /// Sendable snapshot. Returns an empty array when the pasteboard is empty.
  /// Filtering by supported type and capping by size is the ingestor's job,
  /// not the source's.
  func snapshot() -> [PasteboardItemSnapshot]
}

/// The raw, `Sendable`, already-materialized snapshot of a single pasteboard item:
/// a map of pasteboard type (`rawValue` string) to bytes.
///
/// This type deliberately performs NO filtering and NO size-capping — it records
/// exactly what was on the pasteboard. Type filtering and the `maxValueSize` cap
/// belong to the ingestor (see `Clipboard.contents(from:)`), which runs after a
/// snapshot is taken. Keeping the snapshot raw means it can be created on the main
/// thread (where `NSPasteboardItem` lives) and handed to a background actor for
/// the expensive filtering/hashing work.
struct PasteboardItemSnapshot: Sendable {
  let contents: [String: Data]

  init(contents: [String: Data]) {
    self.contents = contents
  }

  var types: Set<NSPasteboard.PasteboardType> {
    Set(contents.keys.map(NSPasteboard.PasteboardType.init(_:)))
  }

  func data(for type: NSPasteboard.PasteboardType) -> Data? {
    contents[type.rawValue]
  }
}

/// Production `PasteboardSource` over a real `NSPasteboard` (defaults to
/// `NSPasteboard.general`).
///
/// The snapshot is taken eagerly: `snapshot()` walks `pasteboardItems`, reads
/// each type's bytes, and returns plain `PasteboardItemSnapshot` values. After
/// that the caller no longer needs to touch `NSPasteboard`, which is what makes
/// off-main ingestion safe — the only main-thread work is the read itself.
///
/// `@unchecked Sendable` is required because `NSPasteboard` is itself not
/// `Sendable`. The wrapping struct is still safe to share across actors:
/// `NSPasteboard`'s pasteboard-reading APIs are thread-safe system APIs, and we
/// only ever invoke them through an immutable `let` reference.
struct NSPasteboardSource: @unchecked Sendable, PasteboardSource {
  let pasteboard: NSPasteboard

  init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  var changeCount: Int { pasteboard.changeCount }

  func snapshot() -> [PasteboardItemSnapshot] {
    guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
      return []
    }

    return items.map { item in
      var contents: [String: Data] = [:]
      for type in item.types {
        // `data(forType:)` may return nil for a declared-but-absent type; an
        // absent key in `contents` already means nil, so we only record keys
        // that actually carry data, preserving the existing semantics.
        if let data = item.data(forType: type) {
          contents[type.rawValue] = data
        }
      }
      return PasteboardItemSnapshot(contents: contents)
    }
  }
}
