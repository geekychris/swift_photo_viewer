import Foundation

/// Security-scoped access to a sandboxed root directory, resolved once from its bookmark.
/// Every file operation under a root must run inside `withAccess`.
enum SecurityScope {
    static func withAccess<T>(_ root: RootDirectory, _ body: () throws -> T) rethrows -> T {
        let url = startAccess(root)
        defer { url?.stopAccessingSecurityScopedResource() }
        return try body()
    }

    static func withAccess<T>(_ root: RootDirectory, _ body: () async throws -> T) async rethrows -> T {
        let url = startAccess(root)
        defer { url?.stopAccessingSecurityScopedResource() }
        return try await body()
    }

    /// Starts access to several roots at once (e.g. a plan that copies from many sources).
    static func withAccess<T>(_ roots: [RootDirectory], _ body: () async throws -> T) async rethrows -> T {
        let urls = roots.compactMap(startAccess)
        defer { urls.forEach { $0.stopAccessingSecurityScopedResource() } }
        return try await body()
    }

    private static func startAccess(_ root: RootDirectory) -> URL? {
        guard let bookmark = root.bookmarkData else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }
}
