import Defaults
import SwiftUI

struct TagChipView: View {
  var tag: String

  var body: some View {
    HStack(spacing: 2) {
      Circle()
        .fill((Defaults[.tagColors][tag] ?? .gray).color)
        .frame(width: 8, height: 8)
      Text("#\(tag)")
        .font(.system(size: 12))
    }
  }
}
