import Foundation

/// Reads and writes `library.json`.
public struct LibraryStore: Sendable {
    public let paths: LumenPaths

    public init(paths: LumenPaths) {
        self.paths = paths
    }

    /// Returns the saved library, or `.empty` when the file is missing.
    /// An unreadable file is renamed to `library.corrupt-<timestamp>.json` so it is never lost.
    /// An existing file that cannot be read is renamed to `library.unreadable-<timestamp>.json`,
    /// so the next save never overwrites it.
    public func load() -> Library {
        let url = paths.libraryFile
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        guard let data = try? Data(contentsOf: url) else {
            setAside(prefix: "library.unreadable")
            return .empty
        }
        do {
            return try Self.decoder.decode(Library.self, from: data)
        } catch {
            setAside(prefix: "library.corrupt")
            return .empty
        }
    }

    private func setAside(prefix: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let aside = paths.root.appendingPathComponent("\(prefix)-\(formatter.string(from: Date())).json")
        try? FileManager.default.moveItem(at: paths.libraryFile, to: aside)
    }

    public func save(_ library: Library) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(library)
        try data.write(to: paths.libraryFile, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
