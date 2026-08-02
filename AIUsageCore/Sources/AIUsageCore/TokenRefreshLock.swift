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
// mutex spanning those processes. The caller MUST re-read the token after
// acquiring: another process may have refreshed it while this one waited, in
// which case no second refresh should happen.
enum TokenRefreshLock {
    /// How long to wait for the peer before giving up and refreshing anyway.
    /// Comfortably longer than a refresh round trip (15 s request timeout is
    /// the worst case for the holder to finish), short enough that no caller
    /// ever appears to hang.
    private static let waitLimit: TimeInterval = 20

    /// Waits (bounded) for the named lock; returns a file descriptor to pass
    /// back to `release`, or -1 if the lock could not be taken in time — the
    /// caller then proceeds unlocked, degraded but never blocked.
    static func acquire(_ name: String) -> Int32 {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("locks", isDirectory: true) else { return -1 }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = String(name.map { ($0.isLetter || $0.isNumber) ? $0 : "-" })
        let path = dir.appendingPathComponent("\(safe).lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return -1 }
        // NEVER a blocking LOCK_EX. The widget/complication extension holds this
        // lock across an async network refresh, and iOS/watchOS suspend an
        // extension mid-flight without closing its descriptors — so the lock is
        // not released and the waiter never returns. That is what pinned the
        // host app's `refreshing` flag for the rest of the process lifetime:
        // every later refresh returned instantly, the snapshot stopped moving,
        // and the complication froze until the app was force-quit. Two
        // simultaneous refreshes are a rare, recoverable race; a deadlock is
        // permanent, so bound the wait and take the race.
        let deadline = Date().addingTimeInterval(waitLimit)
        while true {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
            guard errno == EWOULDBLOCK, Date() < deadline else { close(fd); return -1 }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    static func release(_ fd: Int32) {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
    }
}
