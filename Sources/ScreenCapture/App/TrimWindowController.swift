import AppKit
import AVKit

/// QuickTime-style trimming of a recording with AVKit's built-in trim bar.
@MainActor
final class TrimWindowController: NSWindowController, NSWindowDelegate {
    let url: URL
    /// Called after the trimmed video replaced the original.
    var onFinish: ((URL) -> Void)?
    var onClose: ((TrimWindowController) -> Void)?

    private let playerView = AVPlayerView()
    /// Re-enters trim mode after Cancel (the window then works as a player).
    private let trimButton = NSButton(title: "Trim", image: NSImage(systemSymbolName: "timeline.selection",
                                                                   accessibilityDescription: nil)!,
                                      target: nil, action: nil)
    private var isTrimming = false {
        didSet { trimButton.isHidden = isTrimming }
    }
    private let title: String

    init(url: URL) {
        self.url = url
        title = "Trim — \(url.deletingPathExtension().lastPathComponent)"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = title
        window.representedURL = url
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 520, height: 360)
        playerView.controlsStyle = .inline
        playerView.player = AVPlayer(url: url)

        let container = NSView()
        playerView.translatesAutoresizingMaskIntoConstraints = false
        trimButton.translatesAutoresizingMaskIntoConstraints = false
        trimButton.bezelStyle = .glass
        trimButton.controlSize = .large
        trimButton.keyEquivalent = "t"
        trimButton.keyEquivalentModifierMask = .command
        trimButton.toolTip = "Trim the recording (⌘T)"
        container.addSubview(playerView)
        container.addSubview(trimButton)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: container.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            trimButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            trimButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
        ])
        window.contentView = container
        window.center()
        super.init(window: window)
        window.delegate = self
        trimButton.target = self
        trimButton.action = #selector(trimPressed)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func trimPressed() { startTrimming() }

    func present() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.forceActivate()
        startTrimming()
    }

    private func startTrimming() {
        guard !isTrimming else { return }
        isTrimming = true
        Task {
            // The trim bar is only available once the player item is ready.
            for _ in 0..<100 where !playerView.canBeginTrimming {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard playerView.canBeginTrimming else {
                isTrimming = false
                showError(TrimError.unsupportedFile, retry: false)
                return
            }
            let result = await playerView.beginTrimming()
            trimmingEnded(result)
        }
    }

    private func trimmingEnded(_ result: AVPlayerViewTrimResult) {
        isTrimming = false
        // Cancel: keep the window as a player; the Trim button starts over.
        guard result == .okButton, let player = playerView.player, let item = player.currentItem else { return }
        let start = item.reversePlaybackEndTime.isNumeric ? item.reversePlaybackEndTime : .zero
        let end = item.forwardPlaybackEndTime.isNumeric ? item.forwardPlaybackEndTime : item.duration
        // Release the file before it's replaced.
        player.pause()
        player.replaceCurrentItem(with: nil)
        trimButton.isHidden = true
        window?.title = "Saving…"
        Task {
            do {
                try await VideoTrimmer.trim(url, to: CMTimeRange(start: start, end: end))
                onFinish?(url)
                close()
            } catch {
                window?.title = title
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                showError(error, retry: true)
            }
        }
    }

    private func showError(_ error: Error, retry: Bool) {
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window) { [weak self] _ in
            MainActor.assumeIsolated {
                if retry { self?.startTrimming() } else { self?.close() }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        playerView.player?.pause()
        playerView.player = nil
        onClose?(self)
    }
}
