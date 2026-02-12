import SwiftUI

struct AppImageView: View {
  let appImage: ApplicationImage
  let size: CGSize

  var body: some View {
    Image(nsImage: appImage.nsImage)
      .resizable()
      .frame(width: size.width, height: size.height)
  }
}
