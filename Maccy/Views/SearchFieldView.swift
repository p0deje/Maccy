import Defaults
import SwiftUI

/// A plain-styled search field with a leading search-mode button and a trailing clear button.
///
/// The leading control cycles the configured search mode
/// (`exact → fuzzy → regexp → mixed → exact`) on click and shares its
/// `Defaults[.searchMode]` binding with the Settings picker, so the two stay
/// in sync. The current mode is shown as a short glyph (`EX`/`FZ`/`RE`/`MX`)
/// with the full localized name as its tooltip.
struct SearchFieldView: View {
  var placeholder: LocalizedStringKey
  @Binding var query: String

  @Environment(AppState.self) private var appState
  @Default(.searchMode) private var searchMode

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Popup.cornerRadius, style: .continuous)
        .fill(Color.secondary)
        .opacity(0.1)
        .frame(height: 23)

      HStack {
        Button {
          searchMode = searchMode.next
        } label: {
          Text(searchMode.abbreviation)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .frame(width: 16, height: 11)
            .padding(.leading, 5)
            .opacity(0.8)
        }
        .buttonStyle(.plain)
        .help(Text(searchMode.description))
        .accessibilityLabel(Text(searchMode.description))

        TextField(placeholder, text: $query)
          .disableAutocorrection(true)
          .lineLimit(1)
          .textFieldStyle(.plain)
          .onSubmit {
            appState.select()
          }

        if !query.isEmpty {
          Button {
            query = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .frame(width: 11, height: 11)
              .padding(.trailing, 5)
          }
          .buttonStyle(.plain)
          .opacity(0.9)
        }
      }
    }
  }
}

#Preview {
  return List {
    SearchFieldView(placeholder: "search_placeholder", query: .constant(""))
    SearchFieldView(placeholder: "search_placeholder", query: .constant("search"))
  }
  .frame(width: 300)
  .environment(\.locale, .init(identifier: "en"))
}
