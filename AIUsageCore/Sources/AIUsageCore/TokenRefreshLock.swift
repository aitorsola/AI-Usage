//
//  TokenRefreshLock.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import Foundation

// Serializes OAuth token refresh across the app AND its widget/complication
// extensions. They share one refresh token through the keychain access group,
// and two concurrent refreshes can make the provider reject one and invalidate
// the whole token family — silently logging the user out every few minutes.
//
// A POSIX flock on a file in the shared App Group container is an OS-level
// mutex spanning those processes (and it's released automatically if a process
// dies, so it never gets stuck). The caller MUST re-read the token after
// acquiring: another process may have refreshed it while this one waited, in
// which case no second refresh should happen.
enum TokenRefreshLock {
    /// Blocks until the named lock is held; returns a file descriptor to pass
    /// back to `release`, or -1 if locking is unavailable (then proceed
    /// unlocked — degraded, but never worse than before).
    static func acquire(_ name: String) -> Int32 {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("locks", isDirectory: true) else { return -1 }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = String(name.map { ($0.isLetter || $0.isNumber) ? $0 : "-" })
        let path = dir.appendingPathComponent("\(safe).lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return -1 }
        if flock(fd, LOCK_EX) != 0 { close(fd); return -1 }
        return fd
    }

    static func release(_ fd: Int32) {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
    }
}
