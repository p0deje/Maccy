import KeyboardShortcuts
import SwiftUI
import Vision

struct PreviewItemView: View {
  var item: HistoryItemDecorator
  @State private var isExtracting = false
  @State private var showAlert = false
  @State private var alertMessage = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let image = item.previewImage {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .clipShape(.rect(cornerRadius: 5))
        // Extract Text Button and Shortcut
        HStack {
          Spacer()
          Button(action: {
            extractText(from: image)
          }) {
            if isExtracting {
              ProgressView()
            } else {
              Label("Extract Text", systemImage: "text.viewfinder")
            }
          }
          .help("Extract text from this image and copy to clipboard")
          .padding(.top, 8)
          .disabled(isExtracting)
        }
      } else {
        ScrollView {
          WrappingTextView {
            Text(item.text)
              .font(.body)
          }
        }
      }

      Divider()
        .padding(.vertical)

      if let application = item.application {
        HStack(spacing: 3) {
          Text("Application", tableName: "PreviewItemView")
          Image(nsImage: item.applicationImage.nsImage)
            .resizable()
            .frame(width: 11, height: 11)
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
      .padding(.bottom)

      if let pinKey = KeyboardShortcuts.Shortcut(name: .pin) {
        Text(
          NSLocalizedString("PinKey", tableName: "PreviewItemView", comment: "")
            .replacingOccurrences(of: "{pinKey}", with: pinKey.description)
        )
      }

      if let deleteKey = KeyboardShortcuts.Shortcut(name: .delete) {
        Text(
          NSLocalizedString("DeleteKey", tableName: "PreviewItemView", comment: "")
            .replacingOccurrences(of: "{deleteKey}", with: deleteKey.description)
        )
      }
    }
    .controlSize(.small)
    .padding()
    .alert(alertMessage, isPresented: $showAlert) {
      Button("OK", role: .cancel) { }
    }
  }

  private func extractText(from image: NSImage) {
    isExtracting = true
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      isExtracting = false
      return
    }
    let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let request = VNRecognizeTextRequest { request, error in
      DispatchQueue.main.async {
        isExtracting = false
        if let results = request.results as? [VNRecognizedTextObservation] {
          let recognizedStrings = results.compactMap { $0.topCandidates(1).first?.string }
          let extractedText = recognizedStrings.joined(separator: "\n")
          if !extractedText.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(extractedText, forType: .string)
          }
        }
      }
    }
    request.recognitionLevel = .accurate
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try requestHandler.perform([request])
      } catch {
        DispatchQueue.main.async {
          isExtracting = false
        }
      }
    }
  }
}
