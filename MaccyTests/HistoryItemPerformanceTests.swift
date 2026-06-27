import XCTest
@testable import Maccy

@MainActor
class HistoryItemPerformanceTests: XCTestCase {
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

  // 8.1 (BS-8 baseline): N same-type, same-size, distinct-content lhs items, and
  // a signature matching the LAST one. `ContentIndex.contains` currently passes
  // `rhsFingerprint` only — `dataLikelyEqual`'s `lhsFingerprint` defaults to nil,
  // so every lhs blob is RE-HASHED per comparison (08-F-001). Matching the last
  // item forces a full scan → N lhs re-hashes per `contains`. Baseline is the
  // FNV + no-persistent-column world; 8.8 re-baselines after the xxh3 swap +
  // persistent `HistoryItemContent.fingerprint` column (lhs reads the column →
  // 0 re-hash) and asserts the drop. No baseline set this step (algorithm not
  // swapped yet); 8.8 sets `measureMetrics` `.baseline` + relative tolerance.
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

  // 8.1 (BS-8 baseline): fingerprint throughput, FNV pre-swap. Records GB/s via
  // `measure`'s clock (no assertion this step — pre-swap baseline). 8.8
  // re-baselines against xxh3 and asserts ≥ 3× over this FNV number. `_ =`
  // discards the result so the test survives the 8.3 bridge change
  // (UInt64 → MaccyFingerprintStruct) without modification.
  func testFingerprintThroughputBenchmark() {
    let oneMB = Data(count: 1 * 1024 * 1024)
    let tenMB = Data(count: 10 * 1024 * 1024)

    measure {
      _ = MaccyTextProcessor.fingerprint(for: oneMB)
      _ = MaccyTextProcessor.fingerprint(for: tenMB)
    }
  }

  /// Same `size`, distinct first byte → distinct content & fingerprint, so the
  /// multi-lhs scan can't short-circuit on an early size/hash match.
  private static func distinctBlob(size: Int, marker: UInt8) -> Data {
    var bytes = [UInt8](repeating: 0x61, count: size)
    bytes[0] = marker
    return Data(bytes)
  }
}
