import Cocoa

class PinComboBoxCell: NSComboBoxCell {
  required init(coder: NSCoder) {
    super.init(coder: coder)
    self.isButtonBordered = false
    self.numberOfVisibleItems = HistoryItem.availablePins.count
    HistoryItem.availablePins.sorted().forEach { pin in
      addItem(withObjectValue: pin)
    }
  }
}
