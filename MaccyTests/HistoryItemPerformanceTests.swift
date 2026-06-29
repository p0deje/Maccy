import XCTest
@testable import Maccy

/// Benchmarks for `HistoryItemEngine` signature and dedup hot paths.
@MainActor
class HistoryItemPerformanceTests: XCTestCase {
  /// Benchmark for superset-containment checks over a single large text content.
  func testLargeTextSignatureSupersedesBenchmark() {
    let largeText = String(repeating: "abcdef\n", count: 20_000)
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: largeText.data(using: .utf8)
      )
    ]
    let signature = HistoryItemEngine.signature(contents: contents, ignoringTypes: [])

    measure {
      XCTAssertTrue(HistoryItemEngine.contains(contents: contents, signature: signature))
    }
  }

  /// Benchmark for the multi-item left-hand-side scan: N same-type, same-size,
  /// distinct-content items with a signature matching the last, forcing a full
  /// scan. After the xxh3 fingerprint swap and the persistent
  /// `HistoryItemContent.fingerprint` column, each left-hand-side blob reads its
  /// fingerprint from the column instead of re-hashing per comparison.
  func testMultiSameTypeLhsRehashBenchmark() {
    let itemCount = 20
    let blobSize = 20_000   // ≥ 16 KiB threshold → fingerprinted
    let type = NSPasteboard.PasteboardType.string.rawValue
    let historyContents = (0..<itemCount).map { index in
      HistoryItemContent(type: type, value: Self.distinctBlob(size: blobSize, marker: UInt8(index)))
    }
    let signature = HistoryItemEngine.signature(
      contents: [historyContents.last!],
      ignoringTypes: []
    )

    measure {
      XCTAssertTrue(HistoryItemEngine.contains(contents: historyContents, signature: signature))
    }
  }

  /// Benchmark for the xxh3 fingerprint throughput (1 MiB + 10 MiB blobs).
  /// Reported as throughput via `measure`'s clock.
  func testFingerprintThroughputBenchmark() {
    let oneMB = Data(count: 1 * 1024 * 1024)
    let tenMB = Data(count: 10 * 1024 * 1024)

    measure {
      _ = MaccyTextProcessor.fingerprint(for: oneMB)
      _ = MaccyTextProcessor.fingerprint(for: tenMB)
    }
  }

  /// Same `size`, distinct first byte → distinct content & fingerprint, so the
  /// multi-left-hand-side scan can't short-circuit on an early size/hash match.
  private static func distinctBlob(size: Int, marker: UInt8) -> Data {
    var bytes = [UInt8](repeating: 0x61, count: size)
    bytes[0] = marker
    return Data(bytes)
  }
}
