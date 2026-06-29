/// Makes `String` conform to `Identifiable` by using its own value as the identity.
extension String: @retroactive Identifiable {
  public var id: Self { self }
}
