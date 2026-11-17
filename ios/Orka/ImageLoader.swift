import SwiftUI
import UIKit

/// Keeps channel and team logos in memory so scrolling back to them is instant (AsyncImage
/// reloads every time a row reappears). Images are downloaded and decoded off the main thread.
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]
    private var failed = Set<URL>()

    private init() {
        cache.countLimit = 800
    }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        if failed.contains(url) { return nil }
        if let running = inflight[url] { return await running.value }
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let image = UIImage(data: data) else { return nil }
            return image.preparingForDisplay() ?? image
        }
        inflight[url] = task
        let image = await task.value
        inflight[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL)
        } else {
            failed.insert(url) // a broken logo link isn't retried while the app is open
        }
        return image
    }
}

/// A remote image with a placeholder, backed by ImageLoader.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var loaded: UIImage?

    var body: some View {
        let image = loaded ?? url.flatMap { ImageLoader.shared.cached($0) }
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url, loaded == nil else { return }
            loaded = await ImageLoader.shared.load(url)
        }
    }
}
