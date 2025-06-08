import SwiftUI

struct ListItemTitleView<Title: View>: View {
    var attributedTitle: AttributedString?
    @ViewBuilder var title: () -> Title

    var body: some View {
        VStack(alignment: .leading) {
            Spacer(minLength: 0)
            if let attributedTitle {
                Text(attributedTitle)
                    .accessibilityIdentifier("copy-history-item")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                title()
                    .accessibilityIdentifier("copy-history-item")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }
}
