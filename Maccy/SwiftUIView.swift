import SwiftUI
import SwiftData
import Sauce

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
//  @FocusState.Binding var isFocused: Bool
//  @Binding var isHovered: Bool
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
//            .foregroundStyle(isHovered ? .white : .secondary)
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
//
//
//struct SearchBar: View {
//  @Binding var text: String
//
//  @FocusState private var isFocused: Bool
//  @State private var isEditing = false
//
//
//    var body: some View {
//            TextField(
//                      text: $text,
//                      label: { Text("search")}
//            )
////                .padding(7)
////                .padding(.horizontal, 25)
////                .background(/*Color(.gray)*/)
//////                .cornerRadius(8)
////                .overlay(
////                    HStack {
////                        Image(systemName: "magnifyingglass")
////                            .foregroundColor(.gray)
////                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
////                            .padding(.leading, 40)
////
////                        if isFocused {
////                            Button(action: {
////                                self.text = ""
////                            }) {
////                                Image(systemName: "multiply.circle.fill")
//////                                    .foregroundColor(.gray)
////                                    .padding(.trailing, 15)
////                                    .onTapGesture {
////                                      self.text = ""
////                                    }
////                            }
////                        }
////                    }
////                )
////                .padding(.horizontal, 10)
////                .focused($isFocused)
////
////                .onTapGesture {
////                    self.isEditing = true
////                }
//
////            if isEditing {
////                Button(action: {
////                    self.isEditing = false
////                    self.text = ""
////
////                }) {
////                    Text("")
////                }
////                .padding(.trailing, 17)
////                .transition(.move(edge: .trailing))
//////                .animation(.default)
////            }
////        }
//    }
//}
//
//struct ContentView: View {
////  @EnvironmentObject var clipboard: Clipboard
//  @Environment(\.modelContext) var modelContext
//
////  @Environment(\.managedObjectContext) var coreDataContext
//  @Query(sort: \HistoryItem.lastCopiedAt) var historyItems: [HistoryItem]
//  var items: [HistoryItem] { filteredItems(products: historyItems, searchText: searchText) }
//
//  @State private var updateList: Bool = false
//  @State private var selection: HistoryItem?
//  @State private var selectionIndex: Int?
//  @State var searchText: String = ""
//  @State private var isPresented = true
////  @State private var sortOrder = SortDescriptor(\User.name)
//
//  var body: some View {
//    SearchBar(text: $searchText)
//      .onKeyPress(.return) {
//        print(
//          "Pressed return",
//          selection?.title.shortened(to: 20),
//          selectionIndex
//        )
//        return .ignored
//      }
//      .onKeyPress(.downArrow) {
//        if selectionIndex != nil {
//          selectionIndex! += 1
//        } else {
//          selectionIndex = 0
//        }
//        return .handled
//      }
//      .onChange(of: searchText) {
//        selectionIndex = 0
//      }
////      .padding(.top, -20)
//    List(selection: $selection) {
//      ForEach(Array(items.enumerated()), id: \.element) { index, item in
//          HistoryItemView(
//            historyItem: item,
//            index: index,
//            searchText: $searchText,
//            selection: $selection,
//            selectionIndex: $selectionIndex
//          )
//      }
//      Divider()
//      MenuItemView(title: "Clear") {
////        history.clearUnpinned()
//        Clipboard.shared.clear()
//      }
//      MenuItemView(title: "Preferences…", keyboardCharacter: ",") {
////        history.clearUnpinned()
//      }
//      MenuItemView(title: "About") {
//        About().openAbout(nil)
//      }
//      MenuItemView(title: "Quit", keyboardCharacter: "Q") {
//        NSApp.terminate(self)
//      }
//    }
////    .searchable(text: $searchText, isPresented: $isPresented)
////    .scrollIndicators(.never)
////    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 0)) // EdgeInsets
////     .listRowBackground(Color.clear) // Change Row Color
//      //hide Seprator
////     .listStyle(.plain) //Change ListStyle
//    .scrollContentBackground(.hidden)
//    .background(.ultraThinMaterial) //Change Background Color
//    .environment(\.defaultMinListRowHeight, 0)
//    .onKeyPress(.delete) {
//      let _ = searchText.dropLast()
//      return .handled
//    }
//    .onKeyPress { press in
//      print(press.key, press.modifiers)
//
//      let modifierFlags = press.modifiers.subtracting(.capsLock)
//      let chars = press.characters
//
//      print(press.key == .delete, press.modifiers == [.command])
//
//      searchText.append(chars)
//
//      if processKeyDownEvent(key: press.key, modifierFlags: modifierFlags, chars: chars) {
//        return .handled
//      } else {
//        return .ignored
//      }
//    }
//  }
//
//  func filteredItems(
//    products: [HistoryItem],
//    searchText: String
//  ) -> [HistoryItem] {
//    guard !searchText.isEmpty else { return historyItems }
//
//    return Search().search(string: searchText, within: products).map({ $0.object })
//  }
//
//  private func processKeyDownEvent(key: KeyEquivalent, modifierFlags: EventModifiers, chars: String?) -> Bool {
//    switch KeyChord(key, modifierFlags) {
//    case .clearSearch:
//      print("Clear search")
//      return true
//    case .deleteCurrentItem:
//      print("Delete item")
//      return true
////    case .clearHistory:
////      performMenuItemAction(MenuFooter.clear.rawValue)
////      return true
////    case .clearHistoryAll:
////      performMenuItemAction(MenuFooter.clearAll.rawValue)
////      return true
////    case .deleteOneCharFromSearch:
////      if !queryField.stringValue.isEmpty {
////        setQuery(String(queryField.stringValue.dropLast()))
////      }
////      return true
////    case .deleteLastWordFromSearch:
////      removeLastWordInSearchField()
////      return true
////    case .moveToNext:
////      customMenu?.selectNext()
////      return true
////    case .moveToPrevious:
////      customMenu?.selectPrevious()
////      return true
////    case .pinOrUnpin:
////      if let menu = customMenu, menu.pinOrUnpin() {
////        queryField.stringValue = "" // clear search field just in case
////        return true
////      }
////    case .hide:
////      customMenu?.cancelTracking()
////      return true
////    case .openPreferences:
////      performMenuItemAction(MenuFooter.preferences.rawValue)
////      return true
////    case .paste:
////      if HistoryItemL.pinned.contains(where: { $0.pin == key.rawValue }) {
////        return false
////      } else {
////        queryField.becomeFirstResponder()
////        queryField.currentEditor()?.paste(nil)
////        return true
////      }
////    case .selectCurrentItem:
////      customMenu?.select(queryField.stringValue)
////      return true
////    case .ignored:
////      return false
//    default:
//      ()
//    }
//
//    return true
////    return processSingleCharacter(chars)
//  }
//}
//
//#Preview {
//  let storeURL = CoreDataManager.shared.persistentContainer.persistentStoreDescriptions.first!.url!
////            print()
//  let config = ModelConfiguration(url: URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite"))
//  let container = try! ModelContainer(for: HistoryItem.self, configurations: config)
//
//  return ContentView()
//    .modelContainer(container)
//}
