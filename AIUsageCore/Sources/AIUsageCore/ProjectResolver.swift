//
//  ProjectResolver.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// Resolves the working directory of an agent session to the project it belongs
// to: the repository root. Sessions report the cwd they were launched from,
// which is often a subdirectory (`repo/Sources/App`) — grouping by raw cwd
// would split one project across several entries.
public enum ProjectResolver {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    /// Repository root containing `cwd`, or `cwd` itself when it is not inside
    /// a repository. Returns "" for an empty input (usage with no local session,
    /// e.g. plan data fetched from a provider API).
    public static func root(for cwd: String) -> String {
        guard !cwd.isEmpty else { return "" }

        lock.lock()
        let hit = cache[cwd]
        lock.unlock()
        if let hit { return hit }

        let resolved = computeRoot(for: cwd)

        lock.lock()
        cache[cwd] = resolved
        lock.unlock()
        return resolved
    }

    private static func computeRoot(for cwd: String) -> String {
        let fm = FileManager.default
        var url = URL(fileURLWithPath: cwd).standardizedFileURL
        // Walk up to the filesystem root. `.git` is a directory in a normal
        // clone and a file in worktrees and submodules, so test for either.
        while url.path != "/" && !url.path.isEmpty {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return url.path
            }
            let parent = url.deletingLastPathComponent().standardizedFileURL
            if parent.path == url.path { break }
            url = parent
        }
        return cwd
    }

    /// Short label for a project path — the last path component.
    public static func displayName(for path: String) -> String {
        guard !path.isEmpty else { return L.t("no_project") }
        return (path as NSString).lastPathComponent
    }

    static func resetCacheForTesting() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
