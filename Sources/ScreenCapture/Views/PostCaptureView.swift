import SwiftUI

/// Floating card shown after a capture, with quick actions and a shortcut to the matching history.
struct PostCaptureView: View {
    let item: CaptureItem
    let openHistory: () -> Void
    let edit: (() -> Void)?
    let trim: (() -> Void)?
    let pin: (() -> Void)?
    /// Opens the capture (recordings open in the trim window).
    let open: () -> Void
    let close: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(item.kind == .recording ? "Recording saved" : "Screenshot saved")
                    .font(.headline)
                Spacer()
                if let pin {
                    Button(action: pin) {
                        Image(systemName: "pin")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .help("Pin to screen")
                }
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
            }

            ThumbnailView(url: item.url, version: item.modified, maxPixel: 480)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .bottomTrailing) {
                    if item.kind == .recording { DurationBadge(url: item.url, version: item.modified).padding(6) }
                }
                .onTapGesture(perform: open)
                .draggable(item.url)
                .help("Click to open · Drag to share")

            Text(item.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 6) {
                if let edit {
                    Button("Edit", systemImage: "pencil.and.scribble", action: edit)
                }
                if let trim {
                    Button("Trim", systemImage: "timeline.selection", action: trim)
                }
                Button("Open", systemImage: "arrow.up.forward.app", action: open)
                Button("Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    close()
                }
                Button("Copy", systemImage: "doc.on.doc") {
                    copy(item)
                    close()
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            Button(action: openHistory) {
                Label(item.kind == .recording ? "View Recording History" : "View Screenshot History",
                      systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.regular)
        }
        .padding(16)
        .frame(width: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        .onHover(perform: onHoverChange)
        // Transparent margin so the glass rim and shadow aren't clipped by the panel.
        .padding(Self.outerMargin)
    }

    static let outerMargin: CGFloat = 14
}

/// Small confirmation shown after a Quick Screenshot.
struct QuickCaptureToastView: View {
    let image: NSImage
    let title: String
    let subtitle: String
    let onClick: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 40)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
        .onTapGesture(perform: onClick)
        .onHover(perform: onHoverChange)
        .padding(8)
    }
}
