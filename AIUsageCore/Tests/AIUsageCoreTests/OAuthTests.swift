//
//  OAuthTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
import CryptoKit
@testable import AIUsageCore

final class OAuthTests: XCTestCase {
    // MARK: - PKCE (Anthropic)

    func testVerifierShapeAndUniqueness() {
        let v1 = AnthropicOAuth.makeVerifier()
        let v2 = AnthropicOAuth.makeVerifier()
        XCTAssertEqual(v1.count, 64, "48 bytes → 64 chars base64url sin padding")
        XCTAssertNotEqual(v1, v2)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(v1.unicodeScalars.allSatisfy(allowed.contains), "solo alfabeto base64url")
    }

    func testAuthorizeURLCarriesS256Challenge() throws {
        let verifier = "test-verifier-1234"
        let url = AnthropicOAuth.authorizeURL(verifier: verifier, redirect: AnthropicOAuth.localRedirect)
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        func query(_ name: String) -> String? {
            comps.queryItems?.first(where: { $0.name == name })?.value
        }

        let digest = SHA256.hash(data: Data(verifier.utf8))
        let expected = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        XCTAssertEqual(query("code_challenge"), expected)
        XCTAssertEqual(query("code_challenge_method"), "S256")
        XCTAssertEqual(query("client_id"), AnthropicOAuth.clientID)
        XCTAssertEqual(query("redirect_uri"), AnthropicOAuth.localRedirect)
        XCTAssertEqual(query("state"), verifier)
    }

    // MARK: - JWT (OpenAI)

    private func makeToken(_ claims: [String: Any]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        let b64 = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "e30.\(b64).sig"   // header "{}" · payload · firma dummy
    }

    func testJWTClaimsAndExpiry() {
        let token = makeToken(["exp": 1_900_000_000, "email": "x@y.z"])
        XCTAssertEqual(OpenAIOAuth.jwtClaims(token)?["email"] as? String, "x@y.z")
        XCTAssertEqual(OpenAIOAuth.jwtExpiry(token)?.timeIntervalSince1970 ?? 0,
                       1_900_000_000, accuracy: 1)
        XCTAssertNil(OpenAIOAuth.jwtClaims("not-a-jwt"))
    }

    func testAccountPlanAndEmailExtraction() {
        let token = makeToken([
            "https://api.openai.com/auth": ["chatgpt_account_id": "acc_1",
                                            "chatgpt_plan_type": "plus"],
            "https://api.openai.com/profile": ["email": "a@b.c"],
        ])
        XCTAssertEqual(OpenAIOAuth.accountID(idToken: nil, accessToken: token), "acc_1")
        XCTAssertEqual(OpenAIOAuth.planType(idToken: nil, accessToken: token), "plus")
        XCTAssertEqual(OpenAIOAuth.email(idToken: nil, accessToken: token), "a@b.c")
    }

    func testAccountIDFallsBackToOrganizations() {
        let token = makeToken(["organizations": [["id": "org_9"]]])
        XCTAssertEqual(OpenAIOAuth.accountID(idToken: nil, accessToken: token), "org_9")
    }

    func testOpenAIAuthorizeURLIncludesCodexFlowParams() throws {
        let url = OpenAIOAuth.authorizeURL(verifier: "v")
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let names = Set(comps.queryItems?.map(\.name) ?? [])
        XCTAssertTrue(names.isSuperset(of: ["response_type", "client_id", "redirect_uri",
                                            "code_challenge", "codex_cli_simplified_flow",
                                            "originator"]))
    }
}
