import SwiftUI

/// Asynchronously loaded, cached QuickLook thumbnail.
struct ThumbnailView: View {
    let url: URL
    /// Changes when the file is rewritten, so edited screenshots get a fresh thumbnail.
    var version: Date = .distantPast
    var maxPixel: CGFloat = 320
    var contentMode: ContentMode = .fill

    @State private var image: NSImage?

    init(url: URL, version: Date = .distantPast, maxPixel: CGFloat = 320, contentMode: ContentMode = .fill) {
        self.url = url
        self.version = version
        self.maxPixel = maxPixel
        self.contentMode = contentMode
        // Cached thumbnails show on the first frame instead of flashing a spinner.
        _image = State(initialValue: ThumbnailCache.shared.cachedThumbnail(for: url, version: version, maxPixel: maxPixel))
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .clipped()
        .task(id: "\(url.path)#\(version.timeIntervalSince1970)") {
            if let cached = ThumbnailCache.shared.cachedThumbnail(for: url, version: version, maxPixel: maxPixel) {
                if image !== cached { image = cached }
                return
            }
            let loaded = await ThumbnailCache.shared.thumbnail(for: url, version: version, maxPixel: maxPixel)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
    }
}

struct DurationBadge: View {
    let url: URL
    /// Modification date; a new value reloads the duration (the file was trimmed in place).
    var version: Date = .distantPast
    @State private var duration: Double?

    var body: some View {
        Group {
            if let duration {
                Text(duration.durationString)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: .capsule)
                    .foregroundStyle(.white)
            }
        }
        .task(id: "\(url.path)#\(version.timeIntervalSince1970)") {
            duration = await ThumbnailCache.shared.duration(for: url)
        }
    }
}

struct ElapsedTimeText: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(context.date.timeIntervalSince(since).durationString)
                .monospacedDigit()
        }
    }
}
