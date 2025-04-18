import SwiftUI
import AppKit

struct SourceURLView: View {
    let url: String
    
    var body: some View {
        HStack {
            Image(systemName: "link")
                .font(.caption)
            
            Text(url)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
        .onTapGesture {
            guard let nsUrl = URL(string: url) else { return }
            NSWorkspace.shared.open(nsUrl)
        }
    }
} 