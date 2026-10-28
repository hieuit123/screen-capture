import SwiftUI

/// Floating card shown after a capture, with quick actions and a shortcut to the matching history.
struct PostCaptureView: View {
    let item: CaptureItem
    let openHistory: () -> Void
    let edit: (() -> Void)?
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
                    if item.kind == .recording { DurationBadge(url: item.url).padding(6) }
                }
                .onTapGesture { NSWorkspace.shared.open(item.url) }
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
                Button("Open", systemImage: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(item.url)
                    close()
                }
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
        .padding(14)
        .frame(width: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .onHover(perform: onHoverChange)
    }
}

/// Small confirmation shown after a Quick Screenshot.
struct QuickCaptureToastView: View {
    let image: NSImage
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
                    Text("Copied to clipboard")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.callout.weight(.semibold))
                Text("Saved to ScreenCapture/images · Click to edit")
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
