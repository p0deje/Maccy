import SwiftUI

struct TodosTabBarView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    Picker("", selection: Binding(
      get: { appState.activeTab },
      set: { appState.setActiveTab($0) }
    )) {
      ForEach(AppTab.allCases) { tab in
        Text(tab.title).tag(tab)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .padding(.horizontal, Popup.horizontalPadding)
    .padding(.top, Popup.verticalPadding)
  }
}
