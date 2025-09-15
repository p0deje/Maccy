import CachedAsyncImage
import Defaults
import FaviconFinder
import SwiftUI

private class FaviconCache {
  static let shared = FaviconCache()

  fileprivate var cache: [String: FaviconURL] = [:]
}

enum FaviconError: Error {
  case noUrlHost
}

struct AppImageView: View {
  let appImage: AppImage?
  let showFavicon: Bool
  let size: CGSize

  private func fetchFaviconUrl(url: URL) async throws -> URL {
    guard let cacheKey = url.plainHost else { throw FaviconError.noUrlHost }

    if let faviconUrl = FaviconCache.shared.cache[cacheKey] {
      return faviconUrl.source
    }

    let faviconUrl = try await FaviconFinder(
      url: url,
      configuration: .init(
        preferredSource: .html,
        preferences: [
          .html: FaviconFormatType.appleTouchIcon.rawValue,
          .ico: "favicon.ico",
          .webApplicationManifestFile: FaviconFormatType.launcherIcon4x
            .rawValue,
        ]
      )
    )
    .fetchFaviconURLs()
    .largest()

    FaviconCache.shared.cache[cacheKey] = faviconUrl

    return faviconUrl.source
  }

  @ViewBuilder func appImage(image: NSImage) -> some View {
    Image(nsImage: image)
      .resizable()
      .frame(width: size.width, height: size.height)
  }

  var body: some View {
    let imageOrFallback = appImage ?? ApplicationImageCache.fallback
    let nsImage = imageOrFallback.nsImage
    if showFavicon, let remoteUrl = imageOrFallback.remoteUrl {
      AsyncView {
        try await fetchFaviconUrl(url: remoteUrl)
      } content: { imageUrl in
        CachedAsyncImage(url: imageUrl) { image in
          let padding = size.width * 0.1
          let imgWidth = size.width - 2*padding
          let imgHeight = size.height-2*padding
          image
            .resizable()
            .frame(width: imgWidth, height: imgHeight)
            .background(.white)
            .cornerRadius(imgWidth * 185.4 / 824)
            .padding(padding)
        } placeholder: {
          appImage(image: nsImage)
        }
      } placeholder: {
        appImage(image: nsImage)
      }
    } else {
      appImage(image: nsImage)
    }
  }
}
