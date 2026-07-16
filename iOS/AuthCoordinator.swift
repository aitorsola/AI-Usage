//
//  AuthCoordinator.swift
//  AI Usage (iOS)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import UIKit
import AuthenticationServices

// Drives the shared OAuth flow on iOS. The proven loopback listener in
// LoginFlowController still catches the redirect (localhost:port); we only
// swap how the authorize URL is opened — an in-app ASWebAuthenticationSession
// so the app stays foregrounded and the listener keeps running.
//
// NOTE: the localhost redirect does not match a custom callback scheme, so the
// session is dismissed manually once the listener reports success. This path is
// wired end-to-end but still needs on-device validation with a real account.
final class ProviderLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let controller: LoginFlowController
    private var session: ASWebAuthenticationSession?

    init(_ config: OAuthFlowConfig, onSuccess: @escaping () -> Void) {
        controller = LoginFlowController(config: config)
        super.init()
        controller.onSuccess = { [weak self] in
            self?.session?.cancel()
            self?.session = nil
            onSuccess()
        }
        controller.iosOpen = { [weak self] url in self?.present(url) }
    }

    func begin() { controller.begin() }

    private func present(_ url: URL) {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "aiusage") { _, _ in }
        session.presentationContextProvider = self
        self.session = session
        session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
