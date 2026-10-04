import AppKit
import KeyboardShortcuts
import SwiftUI

struct PreviewItemView: View {
  static var largeTextThreshold = 1_000

  var item: HistoryItemDecorator

  @State private var isEditingTitle = false
  @State private var editedTitle: String = ""
  @State private var isEditingText = false
  @State private var editedText: String = ""
  @State private var isAddingNew = false
  @State private var newItemText: String = ""

  @ViewBuilder
  func previewImage(content: () -> some View) -> some View {
    content()
      .aspectRatio(contentMode: .fit)
      .clipShape(.rect(cornerRadius: 5))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if isAddingNew {
        VStack {
          TextEditor(text: $newItemText)
            .font(.body)
            .border(Color.secondary.opacity(0.5))
            .frame(minHeight: 100)
          HStack {
            Button("Save New") {
              let newContent = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: newItemText.data(using: .utf8))
              let newHistoryItem = HistoryItem(contents: [newContent])
              History.shared.add(newHistoryItem)
              isAddingNew = false
            }
            Button("Cancel") {
              isAddingNew = false
            }
          }
        }
      } else {
        if item.hasImage {
          AsyncView<NSImage?, _, _>(id: item.id) {
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
        } else {
          if isEditingText {
            VStack {
              TextEditor(text: $editedText)
                .font(.body)
                .border(Color.secondary.opacity(0.5))
                .frame(minHeight: 100)
              HStack {
                Button("Save") {
                  item.updateText(editedText)
                  try? Storage.shared.context.save()
                  isEditingText = false
                }
                Button("Cancel") {
                  isEditingText = false
                }
              }
            }
          } else {
            ZStack(alignment: .topTrailing) {
              let text = item.previewText
              if text.count >= Self.largeTextThreshold {
                LargeTextPreviewView(text: text)
                  .id("textpreview-\(item.id)")
              } else {
                ScrollView {
                  Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
              }
              
              Button(action: {
                editedText = item.previewText
                isEditingText = true
              }) {
                Image(systemName: "pencil.circle.fill")
                  .font(.title2)
                  .foregroundColor(.accentColor)
              }
              .buttonStyle(.plain)
              .padding(4)
            }
          }
        }

        Spacer(minLength: 0)

        Divider()
          .padding(.bottom)

        HStack(spacing: 3) {
          if isEditingTitle {
            TextField("Title", text: $editedTitle)
              .textFieldStyle(.roundedBorder)
              .onSubmit {
                item.item.title = editedTitle
                try? Storage.shared.context.save()
                isEditingTitle = false
              }
          } else {
            Button(action: {
              editedTitle = item.item.title
              isEditingTitle = true
            }) {
              Text(item.item.title.isEmpty ? "Add Title" : "Edit Title")
            }
            .buttonStyle(.link)
            .foregroundColor(.accentColor)
          }

          Spacer()

          Button(action: {
            newItemText = ""
            isAddingNew = true
          }) {
            Image(systemName: "plus.circle.fill")
            Text("Add New")
          }
          .buttonStyle(.plain)
          .foregroundColor(.accentColor)
        }

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

      if item.hasImage, let image = item.item.image {
        HStack(spacing: 3) {
          Text("Dimensions", tableName: "PreviewItemView")
          Text("\(Int(image.pixelSize.width))×\(Int(image.pixelSize.height))")
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

struct LargeTextPreviewView: NSViewRepresentable {
  let text: String

  func makeNSView(context: Context) -> NSScrollView {
    return Self.makeScrollView(text: text)
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView, textView.string != text else {
      return
    }

    textView.string = text
  }

  static func makeScrollView(text: String) -> NSScrollView {
    let textView = NSTextView(usingTextLayoutManager: true)
    textView.isEditable = false
    textView.isSelectable = false
    textView.isRichText = false
    textView.drawsBackground = false
    textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    textView.textColor = .labelColor
    textView.textContainerInset = .zero
    textView.minSize = .zero
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.string = text

    let scrollView = NSScrollView()
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    return scrollView
  }
}
