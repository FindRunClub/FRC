import SwiftUI

/// Opened from the FRC mark: connect or disconnect Strava, sample data, about.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                StrideWordmark(height: 30)
                Spacer()
                IconButton(systemImage: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stravaCard
                    sampleDataCard
                    aboutCard
                }
                .padding(16)
            }
        }
        .background(Theme.ground)
        .presentationDetents([.large])
    }

    private var stravaCard: some View {
        let auth = model.auth
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Strava")
                switch auth.state {
                case .notConfigured:
                    Label("Strava isn't set up in this build", systemImage: "exclamationmark.triangle.fill")
                        .font(FRCFont.body(15, .semibold))
                        .foregroundStyle(Theme.ink)
                    BodyText("Add STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET to Config/Secrets.xcconfig and rebuild. The README walks through it.")
                case .signedOut, .signingIn:
                    BodyText("Connect Strava to see upcoming runs from the clubs you belong to. FRC only asks for read access.")
                    Button {
                        Task { await auth.signIn() }
                    } label: {
                        if auth.state == .signingIn {
                            ProgressView().tint(Theme.ground)
                        } else {
                            Text("Connect with Strava")
                        }
                    }
                    .buttonStyle(FRCButtonStyle(kind: .primary))
                    .disabled(auth.state == .signingIn)
                case .signedIn(let athleteName):
                    HStack {
                        Text("Connected as").foregroundStyle(Theme.muted)
                        Spacer()
                        Text(athleteName).foregroundStyle(Theme.ink)
                    }
                    .font(FRCFont.body(15))
                    Button("Disconnect Strava") {
                        Task { await auth.signOut() }
                    }
                    .buttonStyle(FRCButtonStyle(kind: .secondary, height: 44))
                }
                if let error = auth.lastError {
                    Text(error)
                        .font(FRCFont.body(13, .medium))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var sampleDataCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Sample data")
                    Spacer()
                    SampleDataBadge()
                }
                BodyText("Fictional Nashville run clubs from the design handoff. They show until Strava is connected, and you can switch back to them for testing.")
                Toggle(isOn: Binding(
                    get: { model.isUsingDemoData },
                    set: { model.setForceDemoData($0) }
                )) {
                    Text("Show sample data").font(FRCFont.body(15, .semibold)).foregroundStyle(Theme.ink)
                }
                .tint(Theme.ink)
                .disabled(!model.auth.isSignedIn)
            }
        }
    }

    private var aboutCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("About")
                row("Version", Self.appVersion)
                row("Club events", "Strava")
                row("Maps", "Apple Maps")
                BodyText("Archivo and Geist fonts are used under the SIL Open Font License.")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(FRCFont.mono(14)).foregroundStyle(Theme.ink)
        }
        .font(FRCFont.body(15))
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(FRCFont.display(18))
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct BodyText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(FRCFont.body(14))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
