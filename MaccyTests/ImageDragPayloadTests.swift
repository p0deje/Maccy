import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Maccy

final class ImageDragPayloadTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: directory)
  }

  func testPNGPreservesOriginalBytesAndResolution() throws {
    let original = try imageData(.png)
    XCTAssertEqual(try ImageDragPayload.pngData(from: original), original)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: ImageDragPayload.pngData(from: original)))
    XCTAssertEqual(bitmap.pixelsWide, 640)
    XCTAssertEqual(bitmap.pixelsHigh, 480)
    XCTAssertTrue(bitmap.hasAlpha)
    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.5, accuracy: 0.01)
  }

  func testTIFFAndJPEGExportAsPNG() throws {
    for type: NSBitmapImageRep.FileType in [.tiff, .jpeg] {
      let png = try ImageDragPayload.pngData(from: imageData(type))
      XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
      let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
      XCTAssertEqual(bitmap.pixelsWide, 640)
      XCTAssertEqual(bitmap.pixelsHigh, 480)
    }
  }

  func testInvalidImageReportsError() async {
    let provider = ImageDragPayload(data: Data("not an image".utf8), directory: directory).itemProvider()
    do {
      _ = try await provider.dragData(for: .png)
      XCTFail("Invalid images must not export a file")
    } catch {
      XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true)
    }
  }

  func testPhotoOrientationIsAppliedWithoutDownsampling() throws {
    let sourceData = try imageData(.jpeg)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(sourceData as CFData, nil))
    let rotated = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(rotated, UTType.jpeg.identifier as CFString, 1, nil)
    )
    CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImagePropertyOrientation: 6] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let png = try ImageDragPayload.pngData(from: rotated as Data)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
    XCTAssertEqual(bitmap.pixelsWide, 480)
    XCTAssertEqual(bitmap.pixelsHigh, 640)
  }

  func testProviderOwnsSnapshotAndOffersFileAndImage() async throws {
    var original = try imageData(.png)
    let expected = original
    let provider = ImageDragPayload(data: original, directory: directory).itemProvider()
    original.removeAll()

    XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
    XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.image.identifier))
    let image = try await provider.dragData(for: .png)
    XCTAssertEqual(image, expected)
    let urlData = try await provider.dragData(for: .fileURL)
    let url = try XCTUnwrap(URL(dataRepresentation: urlData, relativeTo: nil))
    XCTAssertTrue(url.isFileURL)
    XCTAssertEqual(url.lastPathComponent, provider.suggestedName)
    XCTAssertEqual(try Data(contentsOf: url), expected)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
  }

  func testFileRepresentationDeliversReadablePNG() async throws {
    let expected = try imageData(.png)
    let provider = ImageDragPayload(data: expected, directory: directory).itemProvider()
    // The receiver must read/copy the supplied URL inside the completion handler.
    let received: Data = try await withCheckedThrowingContinuation { continuation in
      provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, error in
        do {
          if let error { throw error }
          continuation.resume(returning: try Data(contentsOf: XCTUnwrap(url)))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
    XCTAssertEqual(received, expected)
  }

  func testConcurrentRequestsShareOneFile() async throws {
    let provider = ImageDragPayload(data: try imageData(.png), directory: directory).itemProvider()
    try await withThrowingTaskGroup(of: Data.self) { group in
      for _ in 0..<10 {
        group.addTask {
          try await provider.dragData(for: .fileURL)
        }
      }
      var urls = Set<Data>()
      for try await url in group { urls.insert(url) }
      XCTAssertEqual(urls.count, 1)
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
  }

  func testSeparateDragsReuseCachedFile() async throws {
    let data = try imageData(.png)
    let first = ImageDragPayload(data: data, directory: directory).itemProvider()
    let second = ImageDragPayload(data: data, directory: directory).itemProvider()
    let firstURL = try await first.dragData(for: .fileURL)
    let secondURL = try await second.dragData(for: .fileURL)
    XCTAssertEqual(firstURL, secondURL)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
  }

  func testCleanupKeepsRecentExportsAndUnrelatedFiles() throws {
    let old = directory.appendingPathComponent("Image-old.png")
    let recent = directory.appendingPathComponent("Image-recent.png")
    let unrelated = directory.appendingPathComponent("unrelated.png")
    for url in [old, recent, unrelated] { try Data().write(to: url) }
    let yesterday = Date().addingTimeInterval(-ImageDragPayload.retentionInterval - 60)
    for url in [old, unrelated] {
      try FileManager.default.setAttributes([.modificationDate: yesterday], ofItemAtPath: url.path)
    }
    ImageDragPayload.cleanup(in: directory)
    XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
  }

  func testDifferentImagesHaveSeparateExports() async throws {
    let first = ImageDragPayload(data: try imageData(.png), directory: directory).itemProvider()
    let second = ImageDragPayload(data: try imageData(.jpeg), directory: directory).itemProvider()
    let firstURL = try await first.dragData(for: .fileURL)
    let secondURL = try await second.dragData(for: .fileURL)
    XCTAssertNotEqual(firstURL, secondURL)
  }

  func testReuseRefreshesExpiryWithoutRewritingFile() async throws {
    let data = try imageData(.png)
    let first = ImageDragPayload(data: data, directory: directory).itemProvider()
    let urlData = try await first.dragData(for: .fileURL)
    let url = try XCTUnwrap(URL(dataRepresentation: urlData, relativeTo: nil))
    let before = try FileManager.default.attributesOfItem(atPath: url.path)
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(-ImageDragPayload.retentionInterval - 60)], ofItemAtPath: url.path
    )
    let second = ImageDragPayload(data: data, directory: directory).itemProvider()
    let reused = try await second.dragData(for: .fileURL)
    XCTAssertEqual(reused, urlData)
    let after = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual(before[.systemFileNumber] as? NSNumber, after[.systemFileNumber] as? NSNumber)
    XCTAssertGreaterThan(try XCTUnwrap(after[.modificationDate] as? Date), Date().addingTimeInterval(-10))
    ImageDragPayload.cleanup(in: directory)
    XCTAssertEqual(try Data(contentsOf: url), data)
  }

  func testDeletedCacheIsRecreated() async throws {
    let data = try imageData(.png)
    let first = ImageDragPayload(data: data, directory: directory).itemProvider()
    let urlData = try await first.dragData(for: .fileURL)
    let url = try XCTUnwrap(URL(dataRepresentation: urlData, relativeTo: nil))
    try FileManager.default.removeItem(at: url)
    let second = ImageDragPayload(data: data, directory: directory).itemProvider()
    let recreated = try await second.dragData(for: .fileURL)
    XCTAssertEqual(recreated, urlData)
    XCTAssertEqual(try Data(contentsOf: url), data)
  }

  func testConcurrentSeparateDragsReuseOneFile() async throws {
    let data = try imageData(.png)
    let directory = try XCTUnwrap(directory)
    try await withThrowingTaskGroup(of: Data.self) { group in
      for _ in 0..<10 {
        group.addTask {
          let provider = ImageDragPayload(data: data, directory: directory).itemProvider()
          return try await provider.dragData(for: .fileURL)
        }
      }
      var urls = Set<Data>()
      for try await url in group { urls.insert(url) }
      XCTAssertEqual(urls.count, 1)
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
  }

  func testNativePasteboardExportsImageAndFileWithoutTheSourceView() throws {
    let data = try imageData(.png)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    // Neither the history row nor the original payload needs to stay alive.
    let item = ImageDragPayload(data: data, directory: directory).pasteboardItem()
    XCTAssertTrue(pasteboard.writeObjects([item]))
    let path = try XCTUnwrap(pasteboard.string(forType: .fileURL))
    let url = try XCTUnwrap(URL(string: path))
    XCTAssertTrue(url.isFileURL)
    XCTAssertEqual(try Data(contentsOf: url), data)
    XCTAssertEqual(pasteboard.data(forType: .png), data)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
  }

  func testNativePasteboardReusesTheSameCacheAsItemProvider() async throws {
    let data = try imageData(.png)
    let provider = ImageDragPayload(data: data, directory: directory).itemProvider()
    let urlData = try await provider.dragData(for: .fileURL)
    let expectedURL = try XCTUnwrap(URL(dataRepresentation: urlData, relativeTo: nil))
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let item = ImageDragPayload(data: data, directory: directory).pasteboardItem()
    XCTAssertTrue(pasteboard.writeObjects([item]))
    XCTAssertEqual(pasteboard.string(forType: .fileURL), expectedURL.absoluteString)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
  }

  private func imageData(_ type: NSBitmapImageRep.FileType) throws -> Data {
    let bitmap = try XCTUnwrap(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 480,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 0.5), atX: 0, y: 0)
    return try XCTUnwrap(bitmap.representation(using: type, properties: [:]))
  }
}

private extension NSItemProvider {
  func dragData(for type: UTType) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
        do {
          if let error { throw error }
          continuation.resume(returning: try XCTUnwrap(data))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
