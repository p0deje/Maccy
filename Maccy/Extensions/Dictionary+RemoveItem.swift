extension Dictionary {
  /// Removes every key-value pair whose value satisfies `shouldRemove`.
  mutating func removeValues(where shouldRemove: (Value) -> Bool) {
    let keysToRemove = compactMap { key, value in
      shouldRemove(value) ? key : nil
    }

    for key in keysToRemove {
      removeValue(forKey: key)
    }
  }
}
