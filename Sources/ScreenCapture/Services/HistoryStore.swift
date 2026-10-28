import AppKit
import Observation

/// Lists the files in the videos/images folders and keeps them in sync with the file system.
@MainActor
@Observable
final class HistoryStore {
    private(set) var recordings: [CaptureItem] = []
    private(set) var screenshots: [CaptureItem] = []

    @ObservationIgnored private var watchers: [DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    func items(for kind: CaptureKind) -> [CaptureItem] {
        kind == .recording ? recordings : screenshots
    }

    func start() {
        try? StorageManager.ensureFolders()
        reload()
        guard watchers.isEmpty else { return }
        for kind in CaptureKind.allCases {
            let fd = open(StorageManager.folder(for: kind).path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleReload() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers.append(source)
        }
    }

    func reload() {
        reloadTask?.cancel()
        reloadTask = Task {
            let result = await Task.detached(priority: .utility) {
                (Self.scan(.recording), Self.scan(.screenshot))
            }.value
            guard !Task.isCancelled else { return }
            if result.0 != recordings { recordings = result.0 }
            if result.1 != screenshots { screenshots = result.1 }
        }
    }

    func delete(_ items: [CaptureItem]) {
        NSWorkspace.shared.recycle(items.map(\.url)) { [weak self] _, _ in
            Task { @MainActor in self?.reload() }
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    nonisolated private static func scan(_ kind: CaptureKind) -> [CaptureItem] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: StorageManager.folder(for: kind), includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        let allowed: Set<String> = kind == .recording ? ["mp4", "mov", "m4v"] : ["png", "jpg", "jpeg", "heic", "tiff"]

        return urls.compactMap { url -> CaptureItem? in
            guard allowed.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
            else { return nil }
            return CaptureItem(url: url, kind: kind, date: values.creationDate ?? .distantPast,
                               modified: values.contentModificationDate, size: Int64(values.fileSize ?? 0))
        }
        .sorted { $0.date > $1.date }
    }
}
