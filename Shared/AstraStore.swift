import Foundation
import SwiftData

/// Where the data lives, and the small set of values the widget reads.
///
/// A widget runs in its own process and cannot see the app's private container,
/// so the store has to sit in a shared App Group that both can open. Everything
/// here exists to make that one fact work safely.
enum AstraStore {
    /// Must match the App Group capability on both targets.
    static let groupID = "group.com.hanryli.Astra"

    /// Defaults both processes can read. Distinct from `.standard`, which is
    /// per-process and would leave the widget looking at nothing.
    static let defaults = UserDefaults(suiteName: groupID) ?? .standard

    // MARK: - Container

    static let container: ModelContainer = {
        let schema = Schema([Habit.self, Completion.self, Award.self])
        do {
            migrateFromPrivateContainerIfNeeded(schema: schema)
            let configuration = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("could not open the shared store: \(error)")
        }
    }()

    static var storeURL: URL {
        guard let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            // Without the entitlement there's no group to write to. Falling
            // back keeps the app usable; the widget simply shows nothing.
            return privateStoreURL
        }
        return group.appending(path: "Astra.store")
    }

    private static var privateStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// Whether the app has put a store in the group yet.
    ///
    /// The widget asks before touching `container`, because opening a container
    /// creates the database as a side effect. A widget that creates its own
    /// empty store is the race `migrateFromPrivateContainerIfNeeded` has to
    /// survive; not creating one is the cheaper half of the fix.
    static var storeExists: Bool {
        FileManager.default.fileExists(atPath: storeURL.path)
    }

    /// True when this code is running inside the widget rather than the app.
    ///
    /// The two processes share every file in here, so the ones that write need
    /// to be told apart from the one that only reads.
    private static var isExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    /// Set once the app has decided what belongs in the group store. Keyed in
    /// shared defaults so the widget can see the decision too.
    private static let adoptedKey = "store.adoptedPrivate.v1"

    /// Moves an existing private store into the group, once.
    ///
    /// Anyone who used the app before the widget existed has their habits in
    /// the old location. Without this they'd open the new build to an empty
    /// sky, which is the worst possible bug in an app about not losing what
    /// you've earned.
    ///
    /// Existence of the group store is *not* the test. The widget refreshes on
    /// its own schedule, so after an update it can open the group container —
    /// creating an empty database there — before the app has launched even
    /// once. An existence check reads that empty file as "already migrated" and
    /// abandons the real data. Emptiness is the test instead, and the flag
    /// afterwards stops a user who has since deleted every habit from having
    /// the old ones copied back on top.
    ///
    /// SQLite keeps its write-ahead log and shared-memory files alongside the
    /// database; copying only the `.store` would silently drop the most recent
    /// writes, so all three move together.
    private static func migrateFromPrivateContainerIfNeeded(schema: Schema) {
        // Only the app migrates. An extension that lost the race would be
        // rewriting the store underneath the process that owns it.
        guard !isExtension else { return }
        guard !defaults.bool(forKey: adoptedKey) else { return }

        let manager = FileManager.default
        let destination = storeURL
        // No group container means there is nowhere to migrate to, and no
        // decision worth recording — try again on the next launch.
        guard destination != privateStoreURL else { return }
        defer { defaults.set(true, forKey: adoptedKey) }

        guard manager.fileExists(atPath: privateStoreURL.path) else { return }
        guard isEmpty(at: destination, schema: schema) else { return }

        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: privateStoreURL.path + suffix)
            let to = URL(fileURLWithPath: destination.path + suffix)
            try? manager.removeItem(at: to)
            guard manager.fileExists(atPath: from.path) else { continue }
            try? manager.copyItem(at: from, to: to)
        }
    }

    /// Whether the store at `url` holds nothing worth keeping.
    ///
    /// Asked through the model layer rather than by inspecting the file, so it
    /// stays true whatever SwiftData writes on disk. The container is opened
    /// and released inside this call: the caller is about to copy files over
    /// that path and nothing may still hold it open.
    private static func isEmpty(at url: URL, schema: Schema) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let probe = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(probe)
            let habits = try context.fetchCount(FetchDescriptor<Habit>())
            let awards = try context.fetchCount(FetchDescriptor<Award>())
            return habits == 0 && awards == 0
        } catch {
            // Unreadable is not the same as empty. Leave it alone.
            return false
        }
    }

    // MARK: - Values the widget reads

    /// What one more completed day would earn: the star it lights, and the
    /// figure that star belongs to.
    struct Unlock: Codable, Hashable {
        let star: String
        let figure: String
        let lit: Int
        let total: Int
    }

    /// How many unlocks ahead the app publishes.
    ///
    /// One would do if the app were always the thing marking habits, but the
    /// widget can finish a day on its own — and then it needs to name the star
    /// after the one it just lit, with no catalogue to name it from. A run of
    /// ten covers well over a week of logging without the app being opened.
    static let upcomingDepth = 10

    /// A run of unlocks the app has worked out ahead of time.
    ///
    /// Naming a star needs the whole 1,584-star catalogue and the frozen
    /// progression. A widget has neither the memory budget for a second copy of
    /// a 200KB file nor any reason to carry one, so the app resolves the names
    /// and the widget only indexes into them.
    struct UpcomingRun: Codable, Hashable {
        /// The award count the first entry belongs to. Carried alongside the
        /// entries so a widget that has lit a star since the run was published
        /// can still find its own place in it.
        let base: Int
        let unlocks: [Unlock]

        /// What is waiting, for someone who has lit `awardCount` stars.
        ///
        /// Nil once past the end of the run: better to show nothing than to
        /// name a star that has already been lit.
        func unlock(forAwardCount awardCount: Int) -> Unlock? {
            let index = awardCount - base
            guard unlocks.indices.contains(index) else { return nil }
            return unlocks[index]
        }
    }

    private static let upcomingKey = "widget.upcoming.v2"

    static func publish(_ run: UpcomingRun) {
        defaults.set(try? JSONEncoder().encode(run), forKey: upcomingKey)
    }

    static func unlock(forAwardCount awardCount: Int) -> Unlock? {
        guard let data = defaults.data(forKey: upcomingKey),
              let run = try? JSONDecoder().decode(UpcomingRun.self, from: data) else {
            return nil
        }
        return run.unlock(forAwardCount: awardCount)
    }
}
