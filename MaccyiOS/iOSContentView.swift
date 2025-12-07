import SwiftUI

struct iOSContentView: View {
  @State private var appState = AppState.shared
  @State private var showingSettings = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ContentView()
      }
      .navigationTitle("Maccy")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(
        text: $appState.history.searchQuery,
        prompt: Text("Search clipboard history")
      )
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            showingSettings = true
          } label: {
            Image(systemName: "gear")
          }
        }
      }
      .sheet(isPresented: $showingSettings) {
        NavigationStack {
          iOSSettingsView()
        }
      }
    }
    .environment(appState)
  }
}

#Preview {
  iOSContentView()
    .modelContainer(Storage.shared.container)
}
