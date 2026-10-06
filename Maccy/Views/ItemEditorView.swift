import AppKit
import SwiftUI

struct ItemEditorView: View {
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss

  let item: HistoryItemDecorator

  @State private var editableTitle: String
  @State private var editableContent: LargeTextView.EditorState
  @State private var selectedPin: String?
  @State private var availablePins: [String] = []
  @State private var isTextContent: Bool
  @State private var isRichText: Bool
  @State private var isContentTooLarge: Bool

  private var hasWarning: Bool {
    isContentTooLarge || (isRichText && editableContent.hasChanges)
  }

  private enum Field: Hashable {
    case title
    case pin
  }

  @FocusState private var focusedField: Field?

  init(for item: HistoryItemDecorator) {
    self.item = item
    self._editableTitle = State(initialValue: item.item.title)
    self._editableContent = State(initialValue: LargeTextView.EditorState(text: item.previewText.string))
    self._selectedPin = State(initialValue: item.item.pin)

    self._isContentTooLarge = State(initialValue: item.previewText.isTruncated)

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
            .accessibilityLabel(Text("Alias", tableName: "PinsSettings"))
            .disabled(item.hasImage)
            .focused($focusedField, equals: .title)
            .onSubmit(saveChanges)
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
            .accessibilityLabel(Text("Key", tableName: "PinsSettings"))
            .focused($focusedField, equals: .pin)
            .frame(maxWidth: 220, alignment: .leading)
          }
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Text("Content", tableName: "PinsSettings")
            .font(.headline)

          if hasWarning {
            Label {
              if isContentTooLarge {
                Text(NSLocalizedString(
                  "ParagraphsTooLongToEdit",
                  tableName: "PinsSettings",
                  value: "Text contains paragraphs that are too long to edit.",
                  comment: ""
                ))
              } else {
                Text("RichTextEditWarning", tableName: "PinsSettings")
              }
            } icon: {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            }
          }
        }

        contentEditor
      }

      HStack {
        Spacer()
        Button(Self.cancelButtonTitle, role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button(Self.doneButtonTitle, action: saveChanges)
          .keyboardShortcut(.return, modifiers: .command)
          .disabled(!hasChangesToApply)
      }
    }
    .padding(16)
    .frame(minWidth: 540, minHeight: 360)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text("EditItem", tableName: "PreviewItemView"))
    .onAppear {
      availablePins = appState.history.availablePins
      focusedField = item.hasImage ? .pin : .title
    }
    .onExitCommand { dismiss() }
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
        LargeTextView(
          editorState: editableContent,
          isEditable: !isContentTooLarge,
          accessibilityLabel: NSLocalizedString("Content", tableName: "PinsSettings", comment: ""),
          onCancel: { dismiss() }
        )
          .disabled(isContentTooLarge)
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
      } else {
        Text("ContentIsNotText", tableName: "PinsSettings")
          .foregroundStyle(.secondary)
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

  private var hasChangesToApply: Bool {
    let titleChanged = !item.hasImage && editableTitle != item.item.title
    let pinChanged = selectedPin != nil && selectedPin != item.item.pin
    let contentChanged = (isTextContent || isRichText) && editableContent.hasChanges
    return titleChanged || pinChanged || contentChanged
  }

  private func applyChanges() {
    if !item.hasImage && editableTitle != item.item.title {
      item.item.title = editableTitle
      item.title = editableTitle
    }

    if let selectedPin {
      appState.history.updatePin(item.item, to: selectedPin)
    }

    guard isTextContent || isRichText else { return }
    guard editableContent.hasChanges,
          let data = editableContent.text.data(using: .utf8) else { return }

    let historyItem = item.item
    let stringType = NSPasteboard.PasteboardType.string.rawValue
    historyItem.contents.removeAll { $0.type != stringType }

    if let index = historyItem.contents.firstIndex(where: {
      $0.type == stringType
    }) {
      historyItem.contents[index].value = data
    } else {
      historyItem.contents.append(
        HistoryItemContent(type: stringType, value: data)
      )
    }
  }

  private func saveChanges() {
    guard hasChangesToApply else { return }
    applyChanges()
    dismiss()
  }
}
