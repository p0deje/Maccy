extension Dictionary {
  // Removes all key-value pairs where the value satisfies the given predicate.
  mutating func removeValues(where shouldRemove: (Value) -> Bool) {
    let keysToRemove = compactMap { key, value in
      shouldRemove(value) ? key : nil
    }

    for key in keysToRemove {
      removeValue(forKey: key)
    }
  }
}
