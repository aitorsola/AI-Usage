import SwiftUI
import AppKit

struct LoginView: View {
    @ObservedObject var store: UsageStore
    @StateObject private var flow: LoginFlowController
    @State private var pastedCode = ""
    @Environment(\.dismiss) private var dismiss

    private let kind: ProviderKind

    init(store: UsageStore, config: OAuthFlowConfig) {
        _store = ObservedObject(wrappedValue: store)
        _flow = StateObject(wrappedValue: LoginFlowController(config: config))
        kind = config.kind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "asterisk")
                    .font(.title2)
                    .foregroundStyle(kind.color)
                Text(String(format: L.t("Conectar con %@", "Connect to %@"), kind.name))
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch flow.stage {
            case .idle:
                Button {
                    flow.onSuccess = { [weak store] in store?.refresh() }
                    flow.begin()
                } label: {
                    Label(L.t("Abrir navegador para autorizar", "Open browser to authorize"), systemImage: "safari")
                }
                .keyboardShortcut(.defaultAction)

            case .waitingBrowser(let manual):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(manual
                         ? L.t("Autoriza en el navegador y pega abajo el código que se muestra.", "Authorize in the browser and paste the code shown below.")
                         : L.t("Esperando la autorización del navegador…", "Waiting for browser authorization…"))
                        .font(.callout)
                }
                if manual {
                    manualEntry
                }
                HStack {
                    Button(L.t("Copiar enlace de autorización", "Copy authorization link")) { flow.copyAuthorizeURL() }
                        .controlSize(.small)
                    Button(L.t("Cancelar", "Cancel")) {
                        flow.cancelListener()
                        flow.stage = .idle
                    }
                    .controlSize(.small)
                }
                if !manual && flow.config.manualRedirect != nil {
                    DisclosureGroup(L.t("¿No vuelve solo? Pega el código manualmente", "Didn't come back? Paste the code manually")) {
                        manualEntry
                    }
                    .font(.caption)
                }

            case .exchanging:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L.t("Intercambiando el código por la sesión…", "Exchanging the code for a session…"))
                        .font(.callout)
                }

            case .success:
                Label(L.t("Sesión iniciada correctamente", "Signed in successfully"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button(L.t("Cerrar", "Close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)

            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L.t("Reintentar", "Retry")) {
                    flow.begin()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 440, height: 300, alignment: .topLeading)
        .tint(kind.color)
        .onAppear { ActivationPolicy.windowAppeared() }
        .onDisappear {
            flow.cancelListener()
            ActivationPolicy.windowClosed()
        }
    }

    private var explanation: String {
        switch kind {
        case .anthropic:
            return L.t("Se abrirá el navegador para autorizar el acceso con tu cuenta de Claude (el mismo flujo que usa Claude Code). Al aceptar, la app recibirá la autorización automáticamente.", "Your browser will open to authorize access with your Claude account (the same flow Claude Code uses). Once you approve, the app receives the authorization automatically.")
        case .openAI:
            return L.t("Se abrirá el navegador para autorizar el acceso con tu cuenta de OpenAI/ChatGPT (el mismo flujo que usa Codex CLI). Al aceptar, la app recibirá la autorización automáticamente.", "Your browser will open to authorize access with your OpenAI/ChatGPT account (the same flow Codex CLI uses). Once you approve, the app receives the authorization automatically.")
        }
    }

    private var manualEntry: some View {
        HStack {
            TextField(L.t("código#estado", "code#state"), text: $pastedCode)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            Button(L.t("Conectar", "Connect")) {
                flow.submitManualCode(pastedCode)
            }
            .disabled(pastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
