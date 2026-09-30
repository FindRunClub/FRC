import FRCKit
import Foundation
import Observation

/// The clubs FRC loads for the runner's area on top of their own Strava clubs:
/// the curated directory (bundled, refreshed from its hosted copy) plus any
/// clubs the runner added by link.
@MainActor
@Observable
final class ClubDirectoryStore {
    private(set) var directory: ClubDirectory
    private(set) var addedClubs: [ClubDirectory.Entry]
    private var selectedAreaID: String?

    @ObservationIgnored private let remoteURL: URL?

    private static let areaKey = "clubDirectoryArea"
    private static let addedKey = "addedClubs"

    init(remoteURL: URL?) {
        self.remoteURL = remoteURL
        directory = Self.loadCached() ?? Self.loadBundled() ?? ClubDirectory(areas: [])
        addedClubs = Self.loadAdded()
        selectedAreaID = UserDefaults.standard.string(forKey: Self.areaKey)
    }

    var area: ClubDirectory.Area? {
        directory.areas.first { $0.id == selectedAreaID } ?? directory.areas.first
    }

    var listedClubs: [ClubDirectory.Entry] {
        area?.clubs ?? []
    }

    /// Everything to load besides the athlete's own clubs.
    var clubs: [StravaClub] {
        var seen = Set<Int>()
        return (listedClubs + addedClubs)
            .filter { seen.insert($0.id).inserted }
            .map(\.club)
    }

    /// Changes whenever the set of clubs does, so events reload.
    var revision: String {
        "\(area?.id ?? "-"):" + clubs.map { String($0.id) }.joined(separator: ",")
    }

    func selectArea(_ id: String) {
        selectedAreaID = id
        UserDefaults.standard.set(id, forKey: Self.areaKey)
    }

    func add(_ club: StravaClub) {
        guard !addedClubs.contains(where: { $0.id == club.id }) else { return }
        addedClubs.append(ClubDirectory.Entry(club: club))
        saveAdded()
    }

    func remove(_ clubID: Int) {
        addedClubs.removeAll { $0.id == clubID }
        saveAdded()
    }

    /// Picks up clubs added to the hosted directory since this build.
    func refresh() async {
        guard let remoteURL,
              let result = try? await URLSession.shared.data(from: remoteURL),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let remote = try? ClubDirectory.decode(result.0),
              !remote.areas.isEmpty
        else { return }
        let data = result.0
        if remote != directory {
            directory = remote
        }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    // MARK: Persistence

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClubDirectory.json")
    }

    private static func loadCached() -> ClubDirectory? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? ClubDirectory.decode(data)
    }

    private static func loadBundled() -> ClubDirectory? {
        guard let url = Bundle.main.url(forResource: "ClubDirectory", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? ClubDirectory.decode(data)
    }

    private static func loadAdded() -> [ClubDirectory.Entry] {
        guard let data = UserDefaults.standard.data(forKey: addedKey),
              let entries = try? JSONDecoder().decode([ClubDirectory.Entry].self, from: data)
        else { return [] }
        return entries
    }

    private func saveAdded() {
        if let data = try? JSONEncoder().encode(addedClubs) {
            UserDefaults.standard.set(data, forKey: Self.addedKey)
        }
    }
}
