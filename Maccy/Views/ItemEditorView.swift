import AppKit
import SwiftUI

struct ItemEditorView: View {
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss

  let item: HistoryItemDecorator

  @State private var editableTitle: String
  @State private var editableContent: String
  @State private var selectedPin: String?
  @State private var availablePins: [String] = []
  @State private var isTextContent: Bool
  @State private var isRichText: Bool

  init(for item: HistoryItemDecorator) {
    self.item = item
    self._editableTitle = State(initialValue: item.item.title)
    self._editableContent = State(initialValue: item.item.previewableText)
    self._selectedPin = State(initialValue: item.item.pin)

    // Content can only be edited safely as plain text.
    self._isTextContent = State(
      initialValue: item.hasPlainText && !item.hasImage && !item.hasFileURLs
    )
    self._isRichText = State(
      initialValue: item.hasRichText && !item.hasImage && !item.hasFileURLs
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text("Alias", tableName: "PinsSettings")
            .frame(width: 80, alignment: .leading)

          TextField("", text: $editableTitle)
        }

        if item.isPinned {
          HStack(alignment: .firstTextBaseline) {
            Text("Key", tableName: "PinsSettings")
              .frame(width: 80, alignment: .leading)

            Picker("", selection: $selectedPin) {
              ForEach(uniquePins, id: \.self) { pin in
                Text(pin).tag(pin as String?)
              }
            }
            .labelsHidden()
            .frame(maxWidth: 220, alignment: .leading)
          }
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Content", tableName: "PinsSettings")
          .font(.headline)

        contentEditor
      }

      if isRichText {
        Label {
          Text("RichTextEditWarning", tableName: "PinsSettings")
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        }
        .font(.footnote)
      }

      HStack {
        Spacer()
        Button(Self.cancelButtonTitle, role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button(Self.doneButtonTitle) {
          applyChanges()
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .frame(minWidth: 540, minHeight: 360)
    .onAppear {
      availablePins = appState.history.availablePins
    }
  }

  private static var cancelButtonTitle: String {
    appKitString("Cancel")
  }

  private static var doneButtonTitle: String {
    appKitString("Done")
  }

  private static func appKitString(_ key: String) -> String {
    guard let bundle = Bundle(identifier: "com.apple.AppKit") else {
      return key
    }

    return NSLocalizedString(key, bundle: bundle, value: key, comment: "")
  }

  @ViewBuilder
  private var contentEditor: some View {
    Group {
      if isTextContent || isRichText {
        TextEditor(text: $editableContent)
          .font(.body)
          .scrollContentBackground(.hidden)
          .background(Color.clear)
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
      } else {
        Text("ContentIsNotText", tableName: "PinsSettings")
          .foregroundStyle(.secondary)
          .italic()
          .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
          )
          .padding(12)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 180)
    .background {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color(nsColor: .textBackgroundColor))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }

  private var uniquePins: [String] {
    Array(Set(availablePins + [item.item.pin, selectedPin].compactMap { $0 }))
      .sorted()
  }

  private func applyChanges() {
    item.item.title = editableTitle
    item.title = editableTitle

    if let selectedPin {
      appState.history.updatePin(item.item, to: selectedPin)
    }

    guard isTextContent || isRichText else { return }

    let historyItem = item.item
    let stringType = NSPasteboard.PasteboardType.string.rawValue
    historyItem.contents.removeAll { $0.type != stringType }

    if let index = historyItem.contents.firstIndex(where: {
      $0.type == stringType
    }) {
      if let data = editableContent.data(using: .utf8) {
        historyItem.contents[index].value = data
      }
    } else if let data = editableContent.data(using: .utf8) {
      historyItem.contents.append(
        HistoryItemContent(type: stringType, value: data)
      )
    }
  }
}
