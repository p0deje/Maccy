import KeyboardShortcuts
import SwiftUI
import Defaults

struct PreviewItemView: View {
    var item: HistoryItemDecorator

    // Add @Default properties to watch the settings
    @Default(.showDeleteButton) private var showDeleteButton
    @Default(.showPreviewButton) private var showPreviewButton

    @ViewBuilder
    private var previewContent: some View {
        // Content moved from the original body's VStack
        if let quickLookImage = item.quickLookThumbnail { // Prioritize QuickLook thumbnail
            Image(nsImage: quickLookImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 500, maxHeight: 650) // Set explicit size for better visibility
                .clipShape(.rect(cornerRadius: 5))
        } else if let image = item.previewImage { // Fallback to existing previewImage (for copied images)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 500, maxHeight: 650) // Set explicit size for consistency
                .clipShape(.rect(cornerRadius: 5))
        } else { // Text content
            ScrollView {
                Text(item.text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    // Padding for text inside ScrollView
            }
            .frame(maxWidth: 400, maxHeight: 300) // Constrain ScrollView for text previews
            .clipShape(.rect(cornerRadius: 5))   // Consistent corner radius
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

        if showPreviewButton, let pinKey = KeyboardShortcuts.Shortcut(name: .pin) {
            Text(
                NSLocalizedString("PinKey", tableName: "PreviewItemView", comment: "")
                    .replacingOccurrences(of: "{pinKey}", with: pinKey.description)
            )
        }

        if showDeleteButton, let deleteKey = KeyboardShortcuts.Shortcut(name: .delete) {
            Text(
                NSLocalizedString("DeleteKey", tableName: "PreviewItemView", comment: "")
                    .replacingOccurrences(of: "{deleteKey}", with: deleteKey.description)
            )
        }
        // End of moved content
    }

    var body: some View {
        let isNonTextPreview = item.quickLookThumbnail != nil || item.previewImage != nil

        let baseVStack = VStack(alignment: .leading, spacing: 0) {
            previewContent // Use the extracted content
        }
        .controlSize(.small)

        if isNonTextPreview {
            baseVStack
                .frame(maxWidth: 520, maxHeight: 750) // Apply fixed frame for images/QuickLook
                .padding()
        } else {
            baseVStack
                .padding()
        }
    }
}
