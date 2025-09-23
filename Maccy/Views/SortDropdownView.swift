import SwiftUI
import Defaults

public struct SortDropdownView: View {
    init(sortBy: Binding<Sorter.By>, excludePinKey: Bool = false, helpText: String? = nil) {
        self._sortBy = sortBy
        self.excludePinKey = excludePinKey
        self.helpText = helpText
    }
    @Binding var sortBy: Sorter.By
    var excludePinKey: Bool = false
    var helpText: String? = nil
    public var body: some View {
        Picker("", selection: $sortBy) {
            ForEach(Sorter.By.allCases.filter { excludePinKey ? $0 != .pinKey : true }) { mode in
                Text(mode.description)
            }
        }
        .labelsHidden()
        .frame(width: 160)
        .help(helpText != nil ? Text(helpText!) : Text(""))
    }
}
