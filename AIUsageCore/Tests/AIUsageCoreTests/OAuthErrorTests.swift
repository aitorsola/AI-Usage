//
//  OAuthErrorTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class OAuthErrorTests: XCTestCase {
    func testAuthFailuresNeedReLogin() {
        // A rejected refresh token → real re-login.
        XCTAssertTrue(OAuthError.isAuthFailure("HTTP 400 {\"error\":\"invalid_grant\"}"))
        XCTAssertTrue(OAuthError.isAuthFailure("HTTP 401 Unauthorized"))
        XCTAssertTrue(OAuthError.isAuthFailure("HTTP 403 forbidden"))
        XCTAssertTrue(OAuthError.isAuthFailure("the refresh token is invalid_grant"))
    }

    func testTransientFailuresKeepTheSession() {
        // Network / server hiccups must NOT log the user out.
        XCTAssertFalse(OAuthError.isAuthFailure("The request timed out."))
        XCTAssertFalse(OAuthError.isAuthFailure("The Internet connection appears to be offline."))
        XCTAssertFalse(OAuthError.isAuthFailure("HTTP 500 Internal Server Error"))
        XCTAssertFalse(OAuthError.isAuthFailure("HTTP 502 Bad Gateway"))
        XCTAssertFalse(OAuthError.isAuthFailure("HTTP 429 Too Many Requests"))
        XCTAssertFalse(OAuthError.isAuthFailure(nil))
        XCTAssertFalse(OAuthError.isAuthFailure(""))
    }
}
