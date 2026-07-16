import Foundation
import AppKit
import CryptoKit
import Network
import Security

enum AnthropicOAuth {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let localRedirect = "http://localhost:54545/callback"
    static let manualRedirect = "https://console.anthropic.com/oauth/code/callback"
    static let tokenEndpoint = "https://console.anthropic.com/v1/oauth/token"
    static let scopes = "org:create_api_key user:profile user:inference"

    struct OwnCredentials {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
    }

    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64url(Data(bytes))
    }

    static func authorizeURL(verifier: String, redirect: String) -> URL {
        let challenge = base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        var comps = URLComponents(string: "https://claude.ai/oauth/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: verifier),
        ]
        return comps.url!
    }

    static func exchange(code: String, state: String?, redirect: String, verifier: String,
                         completion: @escaping (OwnCredentials?, String?) -> Void) {
        var body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirect,
            "code_verifier": verifier,
        ]
        if let state, !state.isEmpty { body["state"] = state }
        post(body: body, completion: completion)
    }

    static func refresh(refreshToken: String, completion: @escaping (OwnCredentials?, String?) -> Void) {
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        post(body: body) { creds, error in
            if let creds, creds.refreshToken == nil {
                let kept = OwnCredentials(accessToken: creds.accessToken,
                                          refreshToken: refreshToken,
                                          expiresAt: creds.expiresAt)
                AnthropicTokenStore.save(kept)
                completion(kept, nil)
            } else {
                completion(creds, error)
            }
        }
    }

    private static func post(body: [String: Any],
                             completion: @escaping (OwnCredentials?, String?) -> Void) {
        var req = URLRequest(url: URL(string: tokenEndpoint)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { completion(nil, err.localizedDescription); return }
            guard let http = resp as? HTTPURLResponse, let data else {
                completion(nil, "respuesta no válida"); return
            }
            guard http.statusCode == 200,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let access = obj["access_token"] as? String
            else {
                let detail = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                completion(nil, "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0) \(detail)")
                return
            }
            let refresh = obj["refresh_token"] as? String
            let expires = (obj["expires_in"] as? NSNumber).map {
                Date().addingTimeInterval($0.doubleValue)
            }
            let creds = OwnCredentials(accessToken: access, refreshToken: refresh, expiresAt: expires)
            AnthropicTokenStore.save(creds)
            completion(creds, nil)
        }.resume()
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum AnthropicTokenStore {
    static let service = "AI Usage-credentials"

    static func load() -> AnthropicOAuth.OwnCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let token = obj["accessToken"] as? String, !token.isEmpty
        else { return nil }
        let expires = (obj["expiresAt"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / 1000)
        }
        return AnthropicOAuth.OwnCredentials(accessToken: token,
                                             refreshToken: obj["refreshToken"] as? String,
                                             expiresAt: expires)
    }

    static func save(_ creds: AnthropicOAuth.OwnCredentials) {
        var payload: [String: Any] = ["accessToken": creds.accessToken]
        if let r = creds.refreshToken { payload["refreshToken"] = r }
        if let e = creds.expiresAt { payload["expiresAt"] = e.timeIntervalSince1970 * 1000 }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        delete()
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: NSUserName(),
            kSecValueData as String: data,
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct OAuthFlowConfig {
    let kind: ProviderKind
    let port: UInt16
    let callbackPath: String
    let localRedirect: String
    let manualRedirect: String?
    let makeAuthorizeURL: (_ verifier: String, _ redirect: String) -> URL
    let exchange: (_ code: String, _ state: String?, _ redirect: String, _ verifier: String,
                   _ completion: @escaping (Bool, String?) -> Void) -> Void

    static let anthropic = OAuthFlowConfig(
        kind: .anthropic,
        port: 54545,
        callbackPath: "/callback",
        localRedirect: AnthropicOAuth.localRedirect,
        manualRedirect: AnthropicOAuth.manualRedirect,
        makeAuthorizeURL: { verifier, redirect in
            AnthropicOAuth.authorizeURL(verifier: verifier, redirect: redirect)
        },
        exchange: { code, state, redirect, verifier, done in
            AnthropicOAuth.exchange(code: code, state: state, redirect: redirect,
                                    verifier: verifier) { creds, error in
                done(creds != nil, error)
            }
        })

    static let openAI = OAuthFlowConfig(
        kind: .openAI,
        port: 1455,
        callbackPath: "/auth/callback",
        localRedirect: OpenAIOAuth.redirect,
        manualRedirect: nil,
        makeAuthorizeURL: { verifier, _ in
            OpenAIOAuth.authorizeURL(verifier: verifier)
        },
        exchange: { code, _, _, verifier, done in
            OpenAIOAuth.exchange(code: code, verifier: verifier) { creds, error in
                done(creds != nil, error)
            }
        })
}

final class LoginFlowController: ObservableObject {
    enum Stage: Equatable {
        case idle
        case waitingBrowser(manual: Bool)
        case exchanging
        case success
        case failure(String)
    }

    @Published var stage: Stage = .idle
    var onSuccess: (() -> Void)?
    let config: OAuthFlowConfig

    private var verifier = ""
    private var redirect: String
    private var listener: NWListener?

    init(config: OAuthFlowConfig) {
        self.config = config
        self.redirect = config.localRedirect
    }

    func begin() {
        cancelListener()
        verifier = AnthropicOAuth.makeVerifier()
        let localOK = startListener()
        if localOK {
            redirect = config.localRedirect
        } else if let manual = config.manualRedirect {
            redirect = manual
        } else {
            stage = .failure(String(format: L.t("el puerto %@ está ocupado — ciérralo (p. ej. un «codex login» a medias) y reintenta", "port %@ is busy — close whatever is using it (e.g. a pending codex login) and retry"), "\(config.port)"))
            return
        }
        stage = .waitingBrowser(manual: !localOK)
        NSWorkspace.shared.open(config.makeAuthorizeURL(verifier, redirect))
    }

    func copyAuthorizeURL() {
        guard !verifier.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            config.makeAuthorizeURL(verifier, redirect).absoluteString,
            forType: .string)
    }

    func submitManualCode(_ pasted: String) {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !verifier.isEmpty else { return }
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        let code = parts[0]
        let state = parts.count > 1 ? parts[1] : verifier
        finish(code: code, state: state)
    }

    private func finish(code: String, state: String?) {
        cancelListener()
        DispatchQueue.main.async { self.stage = .exchanging }
        config.exchange(code, state, redirect, verifier) { ok, error in
            DispatchQueue.main.async {
                if ok {
                    self.stage = .success
                    self.onSuccess?()
                } else {
                    self.stage = .failure(error ?? "error desconocido")
                }
            }
        }
    }

    private func startListener() -> Bool {
        guard let port = NWEndpoint.Port(rawValue: config.port) else { return false }
        do {
            let l = try NWListener(using: .tcp, on: port)
            l.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            l.start(queue: .main)
            listener = l
            return true
        } catch {
            return false
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        receiveRequest(conn, buffer: Data())
    }

    private func receiveRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if error != nil { conn.cancel(); return }
            let headersDone = buf.range(of: Data("\r\n\r\n".utf8)) != nil
            if headersDone || complete {
                self.respond(conn, request: String(data: buf, encoding: .utf8) ?? "")
            } else {
                self.receiveRequest(conn, buffer: buf)
            }
        }
    }

    private func respond(_ conn: NWConnection, request: String) {
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        let path = parts.count > 1 ? String(parts[1]) : ""

        var code: String?
        var state: String?
        if path.hasPrefix(config.callbackPath),
           let comps = URLComponents(string: "http://localhost\(path)") {
            code = comps.queryItems?.first(where: { $0.name == "code" })?.value
            state = comps.queryItems?.first(where: { $0.name == "state" })?.value
        }

        let ok = code != nil
        let html = ok
            ? "<html><body style='font-family:-apple-system;text-align:center;padding-top:80px'><h2>✓ \(L.t("Autorizado", "Authorized"))</h2><p>\(L.t("Ya puedes cerrar esta pestaña y volver a AI Usage.", "You can close this tab and return to AI Usage."))</p></body></html>"
            : "<html><body style='font-family:-apple-system;text-align:center;padding-top:80px'><p>\(L.t("Esperando autorización…", "Waiting for authorization…"))</p></body></html>"
        let response = "HTTP/1.1 \(ok ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
        if let code {
            finish(code: code, state: state)
        }
    }

    func cancelListener() {
        listener?.cancel()
        listener = nil
    }
}
