import Foundation

/// Local copies of company marks so repeat views need no network and offline views still show
/// the mark. Lives in the Caches directory and is cleared with the rest of local state.
struct CompanyMarkDiskCache: Sendable {
    private let directory: URL

    init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = base.appendingPathComponent("CompanyMarks", isDirectory: true)
    }

    func read(_ reference: CompanyMarkReference) async -> Data? {
        let url = fileURL(for: reference)
        return await Task.detached(priority: .utility) { () -> Data? in
            try? Data(contentsOf: url)
        }.value
    }

    func write(_ data: Data, for reference: CompanyMarkReference) async {
        let directory = self.directory
        let url = fileURL(for: reference)
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }.value
    }

    func removeAll() async {
        let directory = self.directory
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: directory)
        }.value
    }

    private func fileURL(for reference: CompanyMarkReference) -> URL {
        directory.appendingPathComponent("\(reference.key)-\(reference.version)", isDirectory: false)
    }
}
