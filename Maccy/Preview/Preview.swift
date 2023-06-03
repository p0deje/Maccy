import Cocoa

class Preview: NSViewController {
  @IBOutlet weak var textView: NSTextField!
  @IBOutlet weak var imageView: NSImageView!
  @IBOutlet weak var applicationValueLabel: NSTextField!
  @IBOutlet weak var firstCopyTimeValueLabel: NSTextField!
  @IBOutlet weak var lastCopyTimeValueLabel: NSTextField!
  @IBOutlet weak var numberOfCopiesValueLabel: NSTextField!

  private let maxTextSize = 1_500

  private var item: HistoryItem!

  convenience init(item: HistoryItem) {
    self.init()
    self.item = item
  }

  override func viewDidLoad() {
    if let image = item.image {
      textView.removeFromSuperview()
      imageView.image = image
      // Preserver image aspect ratio
      let aspect = image.size.height / image.size.width
      imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: aspect).isActive = true
    } else if let fileURL = item.fileURL,
              let string = fileURL.absoluteString.removingPercentEncoding {
      imageView.removeFromSuperview()
      textView.stringValue = string
    } else if let string = item.rtf?.string {
      imageView.removeFromSuperview()
      textView.stringValue = string
    } else if let string = item.html?.string {
      imageView.removeFromSuperview()
      textView.stringValue = string
    } else if let string = item.text {
      imageView.removeFromSuperview()
      textView.stringValue = string
    } else {
      imageView.removeFromSuperview()
      textView.stringValue = item.title ?? ""
    }

    if let bundle = item.application,
       let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
      applicationValueLabel.stringValue = url.deletingPathExtension().lastPathComponent
    } else {
      applicationValueLabel.removeFromSuperview()
    }

    if textView.stringValue.count > maxTextSize {
      textView.stringValue = textView.stringValue.shortened(to: maxTextSize)
    }

    firstCopyTimeValueLabel.stringValue = formatDate(item.firstCopiedAt)
    lastCopyTimeValueLabel.stringValue = formatDate(item.lastCopiedAt)
    numberOfCopiesValueLabel.stringValue = String(item.numberOfCopies)
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, H:mm:ss"
    formatter.timeZone = TimeZone.current
    return formatter.string(from: date)
  }
}
