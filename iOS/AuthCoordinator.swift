//
//  AuthCoordinator.swift
//  AI Usage (iOS)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import UIKit
import Combine
import AIUsageCore
import AuthenticationServices

// Drives the shared OAuth flow on iOS. The proven loopback listener in
// LoginFlowController still catches the redirect (localhost:port); we only swap
// how the authorize URL is opened — an in-app ASWebAuthenticationSession so the
// app stays foregrounded and the listener keeps running.
//
// It is an ObservableObject so the UI can show progress and, crucially,
// FAILURES: before, a failed exchange or a closed sheet left the user with no
// feedback at all.
final class ProviderLogin: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    enum Phase: Equatable { case idle, waiting, exchanging, failed(String) }
    @Published var phase: Phase = .idle

    private let controller: LoginFlowController
    private let onSuccess: () -> Void
    private var session: ASWebAuthenticationSession?
    private var succeeded = false
    private var observer: AnyCancellable?

    init(_ config: OAuthFlowConfig, onSuccess: @escaping () -> Void) {
        controller = LoginFlowController(config: config)
        self.onSuccess = onSuccess
        super.init()
        controller.onSuccess = { [weak self] in
            guard let self else { return }
            self.succeeded = true
            self.session?.cancel()
            self.session = nil
            self.phase = .idle
            self.onSuccess()
        }
        controller.iosOpen = { [weak self] url in self?.present(url) }
        // Mirror the flow controller's stage (objectWillChange fires before the
        // change, so read it back on the next main-queue tick).
        observer = controller.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.syncPhase() }
        }
    }

    func begin() {
        succeeded = false
        phase = .waiting
        controller.begin()
    }

    private func syncPhase() {
        switch controller.stage {
        case .exchanging: phase = .exchanging
        case .failure(let message): phase = .failed(message)
        case .waitingBrowser: if phase != .exchanging { phase = .waiting }
        case .success, .idle: break
        }
    }

    private func present(_ url: URL) {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "aiusage") { [weak self] _, _ in
            guard let self, !self.succeeded else { return }
            // The sheet closed without us capturing a code: user cancelled or an
            // error. Unless the flow already reported a failure, return to idle.
            if case .failed = self.phase {} else { self.phase = .idle }
        }
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
