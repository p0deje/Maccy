import SwiftUI

//extension View {
//
//    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
//        if (condition) {
//            transform(self)
//        } else {
//            self
//        }
//    }
//
//    @ViewBuilder func `ifInline`<Content: View>(_ condition: @autoclosure () -> Bool, transform: (Self) -> Content) -> some View {
//        if condition() {
//            transform(self)
//        } else {
//            self
//        }
//    }
//}
//
//
//
//struct MenuItemView: View {
//  var title: String
//  var keyboardCharacter: Character?
//  var select: () -> Void
//
//  @FocusState var isFocused: Bool
//  @Binding var isHovered: Bool?
//
//  var body: some View {
//    Button {
//      isFocused = true
//      isHovered = true
//      select()
//      Task {
//        try await Task.sleep(for: .milliseconds(100))
//        self.isFocused = false
//        self.isHovered = false
//      }
//    } label: {
//      HStack {
//        Text(title)
//          .frame(maxWidth: .infinity, alignment: .leading)
//          .lineLimit(1)
//          .truncationMode(.middle)
//          .focusable()
//          .onKeyPress { press in
//            
//            print("Pressed \(press.key.character)")
//            return .handled
//          }
//        Spacer()
//        if let keyboardCharacter {
//          Text("⌘ \(keyboardCharacter)")
//            .frame(width: 30, alignment: .leading)
//            .foregroundStyle((isHovered ?? false) ? .white : .secondary)
//            .fontWeight(.light)
//        }
//      }
//      .padding(.init(top: 3, leading: 10, bottom: 3, trailing: 10))
//    }
//    .buttonStyle(.borderless)
//    .onHover(perform: { hovering in
//      isHovered = hovering
//      isFocused = hovering
//    })
//    .if(keyboardCharacter != nil) { view in
//      view.keyboardShortcut(
//        KeyEquivalent(keyboardCharacter!),
//        modifiers: .command
//      )
//    }
//    .background(
//        RoundedRectangle(cornerRadius: 4, style: .continuous)
//          .trim(from: (isHovered ?? false) ? 0 : 1, to: 1)
//          .fill(Color.accentColor)
//    )
//    .foregroundStyle((isHovered ?? false) ? .white : .primary)
//    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
//  }
//}
//
//struct HistoryItemView: View {
//  var historyItem: HistoryItem
//  var index: Int?
//
//  @Binding var searchText: String
//  @Binding var selection: HistoryItem?
//  @Binding var selectionIndex: Int?
//
//  var body: some View {
//    MenuItemView(
//      title: historyItem.title,
//      keyboardCharacter: (index != nil && index! < 9) ? Character("\(index! + 1)") : nil,
//      select: { select() },
//      isHovered: Binding(get: { selectionIndex == index }, set: {_ in})
//    )
//    .onHover(perform: { hovering in
//      if hovering {
//        selection = historyItem
//        selectionIndex = index
//      } else {
//        selection = nil
//        selectionIndex = nil
//      }
//    })
//    .onChange(of: selectionIndex) {
//      if selectionIndex == index {
//        print("Focus \(index)")
//      }
//    }
//
////
////    Button {
////      isFocused = true
////      isHovered = true
////      select()
////      Task {
////        try await Task.sleep(for: .milliseconds(100))
////        NSApp.hide(self)
////        self.isFocused = false
////        self.isHovered = false
////      }
////    } label: {
////      HStack {
////        Text(historyItem.title)
////
////
////          .frame(maxWidth: .infinity, alignment: .leading)
////          .lineLimit(1)
////          .truncationMode(.middle)
////          .focusable()
////          .onKeyPress { press in
////            print("Pressed \(press.key.character)")
////            return .handled
////          }
////        Spacer()
////        if (index != nil && index! <= 8) {
////          Text("⌘ \(index! + 1)")
////            .frame(width: 30, alignment: .leading)
////            .foregroundStyle(isHovered ? .white : .secondary)
////            .fontWeight(.light)
////        }
////      }
////      .padding(.init(top: 3, leading: 10, bottom: 3, trailing: 10))
////    }
////    .buttonStyle(.borderless)
//////    .background(.ultraThinMaterial) //Change Background Color
////
//////    }
////    .onHover(perform: { hovering in
////      isHovered = hovering
////      isFocused = hovering
////    })
////    .if(index != nil && index! <= 8) { view in
////      view.keyboardShortcut(
////        KeyEquivalent(
////          Character("\(index! + 1)")),
////          modifiers: .command
////
////      )
////    }
////    .background(
////        RoundedRectangle(cornerRadius: 4, style: .continuous)
////          .trim(from: isHovered ? 0 : 1, to: 1)
////          .fill(Color.accentColor)
////    )
////    .foregroundStyle(isHovered ? .white : .primary)
//  }
//
//  private func select() {
//    Clipboard.shared.copy(historyItem)
//  }
//}

//#Preview {
//  let item = HistoryItem(
//    firstCopiedAt: Date.now,
//    lastCopiedAt: Date.now
//  )
//  item.title = "An example string"
//
//  return HistoryItemView(
//    historyItem: item,
//    index: 8,
//    searchText: Binding(get: { "hello" }, set: {_ in }),
//    selection: Binding(get: { nil }, set: {_ in })
//  ).environment(\.locale, .init(identifier: "en"))
//}
