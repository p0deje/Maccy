extension Dictionary {
    /// Removes all key-value pairs where the value satisfies the given predicate.
    mutating func removeValues(where shouldRemove: (Value) -> Bool) {
        for (key, value) in self {
            if shouldRemove(value) {
                self.removeValue(forKey: key)
            }
        }
    }
}
