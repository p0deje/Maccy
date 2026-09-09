extension String {
  func shortened(to maxLength: Int) -> String {
    String(prefix(maxLength))
  }
}
