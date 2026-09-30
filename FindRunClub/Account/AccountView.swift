import SwiftUI

/// Opened from the FRC mark: connect or disconnect Strava, sample data, about.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var clubLink = ""
    @State private var isAddingClub = false
    @State private var addClubMessage: String?

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
                    areaClubsCard
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

    /// Every club in the area, not just the runner's own: the curated list
    /// for the city plus clubs added by link.
    private var areaClubsCard: some View {
        let directory = model.directory
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle("Clubs in your area")
                    Spacer()
                    if directory.directory.areas.count > 1 {
                        Menu(directory.area?.name ?? "Area") {
                            ForEach(directory.directory.areas) { area in
                                Button(area.name) { directory.selectArea(area.id) }
                            }
                        }
                        .font(FRCFont.body(14, .semibold))
                    } else if let area = directory.area {
                        Text(area.name).font(FRCFont.body(14)).foregroundStyle(Theme.muted)
                    }
                }
                BodyText("FRC shows runs from every club listed for your area, not only the ones you've joined. Strava can't search clubs by location, so the list is curated. Add any public club by pasting its Strava link.")
                HStack {
                    Text("Listed for this area").foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(directory.listedClubs.count)").font(FRCFont.mono(14)).foregroundStyle(Theme.ink)
                }
                .font(FRCFont.body(15))

                HStack(spacing: 8) {
                    TextField("strava.com/clubs/123456", text: $clubLink)
                        .font(FRCFont.body(15))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Theme.ground, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    Button {
                        Task { await addClub() }
                    } label: {
                        if isAddingClub {
                            ProgressView().tint(Theme.ground)
                        } else {
                            Text("Add")
                        }
                    }
                    .buttonStyle(FRCButtonStyle(kind: .primary, height: 44))
                    .frame(width: 76)
                    .disabled(clubLink.trimmingCharacters(in: .whitespaces).isEmpty || isAddingClub)
                }
                if let addClubMessage {
                    Text(addClubMessage)
                        .font(FRCFont.body(13, .medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !model.auth.isSignedIn {
                    BodyText("Connect Strava to add clubs and see their events. The map shows sample clubs until then.")
                }

                ForEach(directory.addedClubs) { entry in
                    Divider().overlay(Theme.line)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(FRCFont.body(15, .medium)).foregroundStyle(Theme.ink)
                            Text("Added by you").font(FRCFont.body(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button {
                            directory.remove(entry.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.mid)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(entry.name)")
                    }
                }
            }
        }
    }

    private func addClub() async {
        isAddingClub = true
        defer { isAddingClub = false }
        do {
            let club = try await model.addClub(from: clubLink)
            clubLink = ""
            addClubMessage = "Added \(club.name). Its runs will show on the map."
        } catch {
            addClubMessage = error.localizedDescription
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
