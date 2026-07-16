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
                Text(String(format: L.t("connect_to"), kind.name))
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
                    Label(L.t("open_browser_to_authorize"), systemImage: "safari")
                }
                .keyboardShortcut(.defaultAction)

            case .waitingBrowser(let manual):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(manual
                         ? L.t("authorize_in_the_browser_and_paste")
                         : L.t("waiting_for_browser_authorization"))
                        .font(.callout)
                }
                if manual {
                    manualEntry
                }
                HStack {
                    Button(L.t("copy_authorization_link")) { flow.copyAuthorizeURL() }
                        .controlSize(.small)
                    Button(L.t("cancel")) {
                        flow.cancelListener()
                        flow.stage = .idle
                    }
                    .controlSize(.small)
                }
                if !manual && flow.config.manualRedirect != nil {
                    DisclosureGroup(L.t("didnt_come_back_paste_the_code")) {
                        manualEntry
                    }
                    .font(.caption)
                }

            case .exchanging:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L.t("exchanging_the_code_for_a_session"))
                        .font(.callout)
                }

            case .success:
                Label(L.t("signed_in_successfully"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button(L.t("close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)

            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L.t("retry")) {
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
            return L.t("your_browser_will_open_to_authorize")
        case .openAI:
            return L.t("your_browser_will_open_to_authorize_2")
        default:
            return ""
        }
    }

    private var manualEntry: some View {
        HStack {
            TextField(L.t("code_state"), text: $pastedCode)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            Button(L.t("connect")) {
                flow.submitManualCode(pastedCode)
            }
            .disabled(pastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
