import Foundation
import Observation

/// The image currently on screen is independent of an outstanding replacement.
/// A stable owner (for example a subject ID) may keep its old cover while a new
/// URL loads; a different owner must never display that cover.
@MainActor
@Observable
final class ImagePresentation {
    struct Request: Equatable {
        let url: URL?
        let maxPixel: Int
        let identity: String?

        init(url: URL?, maxPixel: Int, identity: String? = nil) {
            self.url = url.map { MirrorRouting.shared.canonicalURL(for: $0) }
            self.maxPixel = maxPixel
            self.identity = self.url.map { identity ?? $0.absoluteString }
        }
    }

    private var displayedImage: SendableImage?
    private var displayedIdentity: String?
    private var displayedURL: URL?
    private var generation = 0
    private(set) var replacementVersion = 0

    func image(for request: Request) -> SendableImage? {
        guard request.url != nil, displayedIdentity == request.identity else { return nil }
        return displayedImage
    }

    func load(_ request: Request, using loader: ImageLoader = .shared) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let current = generation
        if displayedIdentity != request.identity || request.url == nil {
            displayedImage = nil
            displayedURL = nil
            displayedIdentity = request.identity
        }
        guard let url = request.url, request.maxPixel > 0 else { return }
        let loaded = await loader.image(for: url, maxPixel: request.maxPixel)
        guard !Task.isCancelled, generation == current, let loaded else { return }
        // Changing resolution alone must not fade an already visible cover.
        if displayedURL != url { replacementVersion += 1 }
        displayedImage = loaded
        displayedURL = url
    }
}
