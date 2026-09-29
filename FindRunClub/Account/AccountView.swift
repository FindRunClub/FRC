import SwiftUI

/// Connect or disconnect Strava, and switch demo data on for QA.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                stravaSection

                Section {
                    Toggle("Show demo data", isOn: Binding(
                        get: { model.isUsingDemoData },
                        set: { model.setForceDemoData($0) }
                    ))
                    .disabled(!model.auth.isSignedIn)
                } header: {
                    Text("Testing")
                } footer: {
                    Text("Demo data is a set of fictional run clubs in New York City. It shows automatically until Strava is connected.")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.appVersion)
                    LabeledContent("Maps", value: "Apple Maps")
                    Text("Club events are powered by Strava.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var stravaSection: some View {
        let auth = model.auth
        Section {
            switch auth.state {
            case .notConfigured:
                Label("Strava isn't set up in this build", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Add STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET to Config/Secrets.xcconfig and rebuild. The README walks through it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .signedOut, .signingIn:
                Button {
                    Task { await auth.signIn() }
                } label: {
                    HStack {
                        Spacer()
                        if auth.state == .signingIn {
                            ProgressView().tint(.white)
                        } else {
                            Text("Connect with Strava")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .background(Theme.stravaOrange, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(auth.state == .signingIn)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            case .signedIn(let athleteName):
                LabeledContent("Connected as", value: athleteName)
                Button("Disconnect Strava", role: .destructive) {
                    Task { await auth.signOut() }
                }
            }
        } header: {
            Text("Strava")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let error = auth.lastError {
                    Text(error).foregroundStyle(.red)
                }
                Text("Find Run Club shows upcoming events from the Strava clubs you belong to. It only asks for read access.")
            }
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
