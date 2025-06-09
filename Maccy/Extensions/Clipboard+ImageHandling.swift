import Foundation

// MARK: - Image File Handling Extensions
extension Clipboard {
    func isImageFile(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return imageFileExtensions.contains(fileExtension)
    }

    func loadImageDataFromFileURL(_ url: URL) -> Data? {
        guard isImageFile(url), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return try? Data(contentsOf: url)
    }

    func addImageDataFromFileURLs(_ contents: inout [HistoryItemContent]) {
        // Find file URL contents
        let fileURLContents = contents.filter { NSPasteboard.PasteboardType($0.type) == .fileURL }

        for fileURLContent in fileURLContents {
            guard let urlData = fileURLContent.value,
                  let url = URL(dataRepresentation: urlData, relativeTo: nil, isAbsolute: true),
                  let imageData = loadImageDataFromFileURL(url) else {
                continue
            }

            // Determine the appropriate pasteboard type based on file extension
            let fileExtension = url.pathExtension.lowercased()
            let pasteboardType: NSPasteboard.PasteboardType

            switch fileExtension {
            case "jpg", "jpeg":
                pasteboardType = .jpeg
            case "png":
                pasteboardType = .png
            case "tif", "tiff":
                pasteboardType = .tiff
            case "heic", "heif":
                pasteboardType = .heic
            default:
                // For other image types, convert to TIFF as a fallback
                if let nsImage = NSImage(data: imageData) {
                    if let tiffData = nsImage.tiffRepresentation {
                        contents.append(HistoryItemContent(
                          type: NSPasteboard.PasteboardType.tiff.rawValue,
                          value: tiffData
                        ))
                    }
                }
                continue
            }

            // Add the image data as the appropriate type
            contents.append(HistoryItemContent(type: pasteboardType.rawValue, value: imageData))
        }
    }
}
