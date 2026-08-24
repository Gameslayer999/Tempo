import AppKit
import UniformTypeIdentifiers

/// One file parked on the notch shelf.
struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let name: String
    /// Where Tempo stored its copy.
    let storedAt: URL
    let size: Int64
    let addedAt: Date
    /// SF Symbol for the file type.
    let symbolName: String
}

/// Holds the files dropped on the notch until the user drags them back out.
///
/// Dropped files are **copied** into Tempo's own Application Support directory
/// rather than referenced: a shelf that broke because the user moved, renamed
/// or trashed the original would be a lying signal (UI Principle #4), and a
/// bookmark to a file elsewhere would also make the shelf a second handle on
/// data Tempo does not own.
///
/// Every filesystem operation fails silent (Agent Guideline #3) and nothing
/// here ever logs a file name or path (Agent Guideline #5).
@MainActor
final class ShelfService: ObservableObject {

    @Published private(set) var items: [ShelfItem] = []

    /// Skipped rather than truncated above this size. The shelf is a scratch
    /// surface for handing a file from one app to another, not a backup tool —
    /// silently duplicating a multi-gigabyte file into Application Support
    /// would be a surprise the user never asked for.
    private static let maxItemBytes: Int64 = 256 * 1024 * 1024

    private static var shelfDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tempo/Shelf", isDirectory: true)
    }

    private static var indexFile: URL {
        shelfDirectory.appendingPathComponent("index.json")
    }

    /// The on-disk record. It stores the stored copy's *file name*, not its
    /// full path, so the index stays valid if the home directory moves and so
    /// no absolute user path is written down.
    private struct Entry: Codable {
        let id: UUID
        let name: String
        let file: String
        let size: Int64
        let addedAt: Date
        let symbol: String
    }

    private struct Index: Codable {
        var version: Int
        var items: [Entry]
    }

    init() {}

    /// Reads the index, dropping any entry whose stored copy is gone.
    func load() {
        guard let data = try? Data(contentsOf: Self.indexFile),
              let index = try? JSONDecoder().decode(Index.self, from: data) else {
            items = []
            return
        }
        let dir = Self.shelfDirectory
        items = index.items.compactMap { entry in
            let url = dir.appendingPathComponent(entry.file)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ShelfItem(id: entry.id, name: entry.name, storedAt: url,
                             size: entry.size, addedAt: entry.addedAt, symbolName: entry.symbol)
        }
    }

    /// Copies each regular file in, newest first. Directories and anything over
    /// `maxItemBytes` are skipped, which is why the caller gets a count back
    /// instead of a bool — it is the only way the UI can tell "nothing landed".
    @discardableResult
    func add(urls: [URL]) -> Int {
        guard ensureDirectory() else { return 0 }

        var added: [ShelfItem] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize.map(Int64.init),
                  size <= Self.maxItemBytes else { continue }

            let destination = uniqueDestination(for: url.lastPathComponent)
            guard (try? FileManager.default.copyItem(at: url, to: destination)) != nil else { continue }

            added.append(ShelfItem(id: UUID(), name: url.lastPathComponent, storedAt: destination,
                                   size: size, addedAt: Date(), symbolName: Self.symbol(for: url)))
        }

        guard !added.isEmpty else { return 0 }
        items = added + items
        save()
        return added.count
    }

    func remove(_ item: ShelfItem) {
        try? FileManager.default.removeItem(at: item.storedAt)
        items.removeAll { $0.id == item.id }
        save()
    }

    func removeAll() {
        for item in items { try? FileManager.default.removeItem(at: item.storedAt) }
        items = []
        save()
    }

    /// For dragging an item back out to Finder/another app. Vends the stored
    /// copy, so dragging out never moves the shelf's own file.
    func itemProvider(for item: ShelfItem) -> NSItemProvider {
        NSItemProvider(contentsOf: item.storedAt) ?? NSItemProvider()
    }

    /// Reveal in Finder.
    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.storedAt])
    }

    // MARK: - Storage

    private func ensureDirectory() -> Bool {
        // Owner-only: these are copies of the user's own files, held in Tempo's
        // directory, and no other account has any business reading them.
        (try? FileManager.default.createDirectory(
            at: Self.shelfDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])) != nil
            || FileManager.default.fileExists(atPath: Self.shelfDirectory.path)
    }

    /// Two drops of "report.pdf" must not overwrite each other, so a collision
    /// gets a numeric suffix before the extension.
    private func uniqueDestination(for fileName: String) -> URL {
        let dir = Self.shelfDirectory
        let candidate = dir.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        for n in 2...999 {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let url = dir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return dir.appendingPathComponent("\(base)-\(UUID().uuidString)\(ext.isEmpty ? "" : ".\(ext)")")
    }

    private func save() {
        let index = Index(version: 1, items: items.map {
            Entry(id: $0.id, name: $0.name, file: $0.storedAt.lastPathComponent,
                  size: $0.size, addedAt: $0.addedAt, symbol: $0.symbolName)
        })
        guard ensureDirectory(), let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: Self.indexFile, options: [.atomic])
    }

    private static func symbol(for url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .audio) { return "music.note" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .sourceCode) { return "chevron.left.forwardslash.chevron.right" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}
