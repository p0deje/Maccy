import Defaults
import SwiftUI
import AppKit

struct FooterView: View {
  @Bindable var footer: Footer

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Default(.showFooter) private var showFooter
  @State private var clearOpacity: Double = 1
  @State private var clearAllOpacity: Double = 0

  var clearAllModifiersPressed: Bool {
    let clearModifiers = footer.items[0].shortcuts.first?.modifierFlags ?? []
    let clearAllModifiers = footer.items[1].shortcuts.first?.modifierFlags ?? []
    return !modifierFlags.flags.isEmpty
      && !modifierFlags.flags.isSubset(of: clearModifiers)
      && modifierFlags.flags.isSubset(of: clearAllModifiers)
  }

  var body: some View {
    VStack(spacing: 0) {
      Divider()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)

      ZStack {
        FooterItemView(item: footer.items[0])
          .opacity(clearOpacity)
        FooterItemView(item: footer.items[1])
          .opacity(clearAllOpacity)
      }
      .onChange(of: modifierFlags.flags) {
        if clearAllModifiersPressed {
          clearOpacity = 0
          clearAllOpacity = 1
          footer.items[0].isVisible = false
          footer.items[1].isVisible = true
          if appState.footer.selectedItem == footer.items[0] {
            appState.selection = footer.items[1].id
          }
        } else {
          clearOpacity = 1
          clearAllOpacity = 0
          footer.items[0].isVisible = true
          footer.items[1].isVisible = false
          if appState.footer.selectedItem == footer.items[1] {
            appState.selection = footer.items[0].id
          }
        }
      }

      ForEach(footer.items.suffix(from: 2)) { item in
        FooterItemView(item: item)
      }
      
      // Display source URL if available
      if let selectedItem = appState.history.selectedItem, 
         let sourceURL = selectedItem.sourceURL, 
         !sourceURL.isEmpty {
        Divider()
          .padding(.horizontal, 10)
          .padding(.vertical, 2)
        
        HStack {
            Image(systemName: "link")
                .font(.caption)
            
            Text(sourceURL)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
        .padding(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
        .onTapGesture {
            guard let nsUrl = URL(string: sourceURL) else { return }
            NSWorkspace.shared.open(nsUrl)
        }
      }
    }
    .background {
      GeometryReader { geo in
        Color.clear
          .task(id: geo.size.height) {
            appState.popup.footerHeight = geo.size.height
          }
      }
    }
    .opacity(showFooter ? 1 : 0)
    .frame(maxHeight: showFooter ? nil : 0)
  }
}
