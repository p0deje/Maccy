import Defaults
import SwiftUI

struct HeaderView: View {
  @Environment(\.scenePhase) private var scenePhase

  @FocusState.Binding var searchFocused: Bool
  @Binding var searchQuery: String

  @Default(.showTitle) private var showTitle

  var body: some View {
    HStack {
      if showTitle {
        Text("Maccy")
          .foregroundStyle(.secondary)
      }

      SearchFieldView(placeholder: "search_placeholder", query: $searchQuery)
        .focused($searchFocused)
        .frame(maxWidth: .infinity)
        .onChange(of: scenePhase) {
          if scenePhase == .background && !searchQuery.isEmpty {
            searchQuery = ""
          }
        }
    }
    .padding(.horizontal, 10)
    .padding(.top, 10)
  }
}
