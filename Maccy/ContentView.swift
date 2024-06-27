import SwiftUI
import SwiftData
import Sauce

extension View {

    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if (condition) {
            transform(self)
        } else {
            self
        }
    }

    @ViewBuilder func `ifInline`<Content: View>(_ condition: @autoclosure () -> Bool, transform: (Self) -> Content) -> some View {
        if condition() {
            transform(self)
        } else {
            self
        }
    }
}


struct MenuItem: Identifiable {
  var id = UUID().uuidString
  var title: String
  var keyboardCharacter: Character?
  var submit: () -> Void
}

struct MenuItemView: View {
//  var title: String
//  var keyboardCharacter: Character?
//  var submit: () -> Void

  var item: MenuItem

  @FocusState.Binding var focusedItem: Focusable?
  @FocusState var isFocused


  var body: some View {
    Button {
      focusedItem = .row(id: item.id)
      item.submit()
      Task {
        try await Task.sleep(for: .milliseconds(100))
//        isFocused = false
      }
    } label: {
      HStack {
        Text(item.title)
          .frame(maxWidth: .infinity, alignment: .leading)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer()
        if let keyboardCharacter = item.keyboardCharacter {
          Text("⌘ \(keyboardCharacter)")
            .frame(width: 30, alignment: .leading)
            .foregroundStyle(focusedItem == .row(id: item.id) ? .white : .secondary)
            .fontWeight(.light)
        }
      }
      .padding(.init(top: 3, leading: 10, bottom: 3, trailing: 10))
    }
//    .focusable()
    .buttonStyle(.borderless)
//    .onHover { hovering in
//      if hovering {
//        focusedItem = .row(id: item.id)
//      }
//    }
    .if(item.keyboardCharacter != nil) { view in
      view.keyboardShortcut(
        KeyEquivalent(item.keyboardCharacter!),
        modifiers: .command
      )
    }
    .background(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .trim(from: focusedItem == .row(id: item.id) ? 0 : 1, to: 1)
          .fill(Color.accentColor)
    )
    .foregroundStyle(focusedItem == .row(id: item.id) ? .white : .primary)
    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
    .background {
                    if isFocused {
                        Capsule()
                            .fill(.indigo)
                            .opacity(0.3)
                    }
                }

  }
}

//struct HistoryItemView: View {
//  @Bindable var historyItem: HistoryItem
//  var index: Int?
//
//  @FocusState.Binding var focusedItem: Focusable?
//  @Binding var searchText: String
////  @Binding var selection: HistoryItem?
////  @Binding var selectionIndex: Int?
//
//  var body: some View {
//    MenuItemView(
//      item: MenuItem(
//        title: historyItem.title,
//        keyboardCharacter: (index != nil && index! < 9) ? Character("\(index! + 1)") : nil,
//        submit: { select() }
//      ),
//      focusedItem: $focusedItem
//    )
////    .onHover(perform: { hovering in
////      if hovering {
////        selection = historyItem
////        selectionIndex = index
////      } else {
////        selection = nil
////        selectionIndex = nil
////      }
////    })
////    .onChange(of: selectionIndex) {
////      if selectionIndex == index {
////        print("Focus \(index)")
////      }
////    }
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
////    Clipboard.shared.copy(historyItem)
//  }
//}

struct SearchBar: View {
  @Binding var text: String

  @FocusState private var isFocused: Bool
  @State private var isEditing = false


    var body: some View {
            TextField(
                      text: $text,
                      label: { Text("search")}
            )
//                .padding(7)
//                .padding(.horizontal, 25)
//                .background(/*Color(.gray)*/)
////                .cornerRadius(8)
//                .overlay(
//                    HStack {
//                        Image(systemName: "magnifyingglass")
//                            .foregroundColor(.gray)
//                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
//                            .padding(.leading, 40)
//
//                        if isFocused {
//                            Button(action: {
//                                self.text = ""
//                            }) {
//                                Image(systemName: "multiply.circle.fill")
////                                    .foregroundColor(.gray)
//                                    .padding(.trailing, 15)
//                                    .onTapGesture {
//                                      self.text = ""
//                                    }
//                            }
//                        }
//                    }
//                )
//                .padding(.horizontal, 10)
//                .focused($isFocused)
//
//                .onTapGesture {
//                    self.isEditing = true
//                }

//            if isEditing {
//                Button(action: {
//                    self.isEditing = false
//                    self.text = ""
//
//                }) {
//                    Text("")
//                }
//                .padding(.trailing, 17)
//                .transition(.move(edge: .trailing))
////                .animation(.default)
//            }
//        }
    }
}


enum Focusable: Hashable {
  case none
  case row(id: String)
}


struct ContentView: View {
  @Environment(\.modelContext) var modelContext

//  @FetchRequest var languages: FetchedResults<HistoryItem>
  @Query(sort: \HistoryItem.lastCopiedAt, order: .reverse) var historyItems: [HistoryItem]
  var items: [HistoryItem] { filteredItems(products: historyItems, searchText: searchText) }

  @FocusState private var focusedItem: Focusable?

  @State private var updateList: Bool = false
  @State private var selection: HistoryItem?
  @State private var selectionIndex: Int?
  @State var searchText: String = ""
  @State private var isPresented = true
//  @State private var sortOrder = SortDescriptor(\User.name)
  var body: some View {
//    items.first!.id
    SearchBar(text: $searchText)
      .onKeyPress(.return) {
        print(
          "Pressed return",
          selection?.title.shortened(to: 20),
          selectionIndex
        )
        return .ignored
      }
      .onKeyPress(.downArrow) {
        print(NSApp.windows)
        if selectionIndex != nil {
          selectionIndex! += 1
        } else {
          selectionIndex = 0
        }
        return .ignored
      }
      .onChange(of: searchText) {
        selectionIndex = 0
      }
//      .padding(.top, -20)
    ScrollView(showsIndicators: false) {
      VStack {
        ForEach(historyItems, id: \.self) { item in
          let menuItem = MenuItem(
            title: item.title,
            keyboardCharacter: (0 < 9) ? Character("\(0 + 1)") : nil,
            submit: { Clipboard.shared.copy(item) }
          )
          MenuItemView(
            item: menuItem,
            focusedItem: $focusedItem
          )
          .focusable()
          //          HistoryItemView(
          //            historyItem: item,
          //            index: index,
          //            focusedItem: $focusedItem,
          //            searchText: $searchText
          ////            selection: $selection
          ////            selectionIndex: $selectionIndex
          //          )
//          .focused($focusedItem, equals: .row(id: menuItem.id))
        }
        Divider()
        MenuItemView(item: MenuItem(
          title: "Clear",
          submit: { Clipboard.shared.clear() }),
                     focusedItem: $focusedItem
        )
        MenuItemView(item: MenuItem(
          title: "Preferences…",
          submit: {  }),
                     focusedItem: $focusedItem
        )
        MenuItemView(item: MenuItem(
          title: "About",
          submit: { About().openAbout(nil) }),
                     focusedItem: $focusedItem
        )
        MenuItemView(item: MenuItem(
          title: "Quit",
          submit: { NSApp.terminate(self) }
        ),
                     focusedItem: $focusedItem
        )
      }
      //    .searchable(text: $searchText, isPresented: $isPresented)
      //    .scrollIndicators(.never)
      //    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 0)) // EdgeInsets
      //     .listRowBackground(Color.clear) // Change Row Color
      //hide Seprator
      //     .listStyle(.plain) //Change ListStyle
      .scrollContentBackground(.hidden)
      .background(.ultraThinMaterial) //Change Background Color
      .environment(\.defaultMinListRowHeight, 0)
      .onKeyPress(.delete) {
        let _ = searchText.dropLast()
        return .handled
      }
      .onKeyPress { press in
        print(press.key, press.modifiers)

        let modifierFlags = press.modifiers.subtracting(.capsLock)
        let chars = press.characters

        print(press.key == .delete, press.modifiers == [.command])

        searchText.append(chars)

        if processKeyDownEvent(key: press.key, modifierFlags: modifierFlags, chars: chars) {
          return .handled
        } else {
          return .ignored
        }
      }
      .onChange(of: focusedItem) {
        print(focusedItem)
      }}
  }

  func filteredItems(
    products: [HistoryItem],
    searchText: String
  ) -> [HistoryItem] {
    guard !searchText.isEmpty else { return historyItems }
    
    return Search().search(string: searchText, within: products).map({ $0.object })
  }

  private func processKeyDownEvent(key: KeyEquivalent, modifierFlags: EventModifiers, chars: String?) -> Bool {
    switch KeyChord(key, modifierFlags) {
    case .clearSearch:
      print("Clear search")
      return true
    case .deleteCurrentItem:
      print("Delete item")
      return true
//    case .clearHistory:
//      performMenuItemAction(MenuFooter.clear.rawValue)
//      return true
//    case .clearHistoryAll:
//      performMenuItemAction(MenuFooter.clearAll.rawValue)
//      return true
//    case .deleteOneCharFromSearch:
//      if !queryField.stringValue.isEmpty {
//        setQuery(String(queryField.stringValue.dropLast()))
//      }
//      return true
//    case .deleteLastWordFromSearch:
//      removeLastWordInSearchField()
//      return true
//    case .moveToNext:
//      customMenu?.selectNext()
//      return true
//    case .moveToPrevious:
//      customMenu?.selectPrevious()
//      return true
//    case .pinOrUnpin:
//      if let menu = customMenu, menu.pinOrUnpin() {
//        queryField.stringValue = "" // clear search field just in case
//        return true
//      }
//    case .hide:
//      customMenu?.cancelTracking()
//      return true
//    case .openPreferences:
//      performMenuItemAction(MenuFooter.preferences.rawValue)
//      return true
//    case .paste:
//      if HistoryItemL.pinned.contains(where: { $0.pin == key.rawValue }) {
//        return false
//      } else {
//        queryField.becomeFirstResponder()
//        queryField.currentEditor()?.paste(nil)
//        return true
//      }
//    case .selectCurrentItem:
//      customMenu?.select(queryField.stringValue)
//      return true
//    case .ignored:
//      return false
    default:
      ()
    }

    return true
//    return processSingleCharacter(chars)
  }
}

#Preview {
  let storeURL = CoreDataManager.shared.persistentContainer.persistentStoreDescriptions.first!.url!
//            print()
  let config = ModelConfiguration(url: URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite"))
  let container = try! ModelContainer(for: HistoryItem.self, configurations: config)

  return ContentView()
    .modelContainer(container)
}
