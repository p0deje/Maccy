import Sauce
import SwiftUI
import SwiftData


//@Observable
//class HistoryS {
//  var items: [HistoryItem] = []
//
//  func load() async throws {
//    items = try await SwiftDataManager.shared.container.mainContext.fetch(
//      FetchDescriptor(sortBy: [
//        SortDescriptor<HistoryItem>(\.pin),
//        SortDescriptor<HistoryItem>(\.lastCopiedAt, order: .reverse)
//      ])
//    )
//  }
//}
//
//
//struct ContentView: View {
//  
//
//  var body: some View {
//    /*@START_MENU_TOKEN@*//*@PLACEHOLDER=Hello, world!@*/Text("Hello, world!")/*@END_MENU_TOKEN@*/
//  }
//}


//#Preview {
//  let storeURL = CoreDataManager.shared.persistentContainer.persistentStoreDescriptions.first!.url!
////            print()
//  let config = ModelConfiguration(url: URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite"))
//  let container = try! ModelContainer(for: HistoryItem.self, configurations: config)
//
//  return ContentView()
//    .modelContainer(container)
//}
