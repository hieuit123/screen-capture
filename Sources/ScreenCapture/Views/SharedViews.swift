import SwiftUI

/// Asynchronously loaded, cached QuickLook thumbnail.
struct ThumbnailView: View {
    let url: URL
    /// Changes when the file is rewritten, so edited screenshots get a fresh thumbnail.
    var version: Date = .distantPast
    var maxPixel: CGFloat = 320
    var contentMode: ContentMode = .fill

    @State private var image: NSImage?

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
                image = cached
                return
            }
            let loaded = await ThumbnailCache.shared.thumbnail(for: url, version: version, maxPixel: maxPixel)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
    }
}

struct DurationBadge: View {
    let url: URL
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
        .task(id: url) { duration = await ThumbnailCache.shared.duration(for: url) }
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
