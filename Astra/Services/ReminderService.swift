import Foundation
import UserNotifications

/// One nudge a day, at a time the user picks.
///
/// The wording is the whole design here. A habit app's reminder is the moment
/// it is most tempting to use guilt, and guilt is exactly what makes people
/// delete it. So a reminder never reports what was missed, never counts days
/// lost, and never says "don't break" anything. It names the star that is
/// waiting and stops.
///
/// Notifications are also cancelled the moment a day is finished, so nobody is
/// ever told to do something they already did.
@MainActor
final class ReminderService {
    static let shared = ReminderService()

    /// Whether the user has switched reminders on. Separate from the system
    /// permission: they can hold authorisation and still want silence.
    static let enabledKey = "reminders.enabled.v1"
    /// Minutes after midnight.
    static let timeKey = "reminders.minutes.v1"
    /// Whether we've already offered reminders once, so the offer is made a
    /// single time and never nags.
    static let offeredKey = "reminders.offered.v1"

    static let defaultMinutes = 20 * 60      // 8pm

    private let identifierPrefix = "astra.reminder."
    /// A week of individually scheduled days. iOS caps pending requests at 64,
    /// and a week is refreshed often enough that the content never goes stale.
    private let daysAhead = 7

    private let centre = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var minutesAfterMidnight: Int {
        get {
            defaults.object(forKey: Self.timeKey) as? Int ?? Self.defaultMinutes
        }
        set { defaults.set(newValue, forKey: Self.timeKey) }
    }

    var hasBeenOffered: Bool {
        get { defaults.bool(forKey: Self.offeredKey) }
        set { defaults.set(newValue, forKey: Self.offeredKey) }
    }

    // MARK: - Permission

    func authorizationStatus() async -> UNAuthorizationStatus {
        await centre.notificationSettings().authorizationStatus
    }

    /// Asks the system. Returns false if the user declines or has already
    /// declined, so the caller can leave the switch off rather than showing it
    /// on while nothing arrives.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await centre.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    // MARK: - Scheduling

    /// Rebuilds the pending week.
    ///
    /// Call on launch, when the app comes forward, when the time changes, and
    /// whenever a day is completed. Cheap: it clears and rewrites at most seven
    /// requests.
    func refresh(nextStarName: String?, isTodayComplete: Bool, calendar: Calendar = .current) async {
        centre.removePendingNotificationRequests(
            withIdentifiers: (0...daysAhead).map { "\(identifierPrefix)\($0)" }
        )

        guard isEnabled, await authorizationStatus() == .authorized else { return }

        let hour = minutesAfterMidnight / 60
        let minute = minutesAfterMidnight % 60
        let now = Date.now

        for offset in 0...daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fireAt = calendar.date(
                    bySettingHour: hour, minute: minute, second: 0, of: day
                  ) else { continue }

            // Nothing for a moment already past, and nothing for today if the
            // day is already done — being reminded to do what you've done is
            // the fastest way to get an app muted.
            guard fireAt > now else { continue }
            if offset == 0 && isTodayComplete { continue }

            let content = UNMutableNotificationContent()
            content.title = "Astra"
            content.body = Self.message(nextStarName: nextStarName)
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "\(identifierPrefix)\(offset)",
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents(
                        [.year, .month, .day, .hour, .minute], from: fireAt
                    ),
                    repeats: false
                )
            )
            try? await centre.add(request)
        }
    }

    func cancelAll() {
        centre.removePendingNotificationRequests(
            withIdentifiers: (0...daysAhead).map { "\(identifierPrefix)\($0)" }
        )
    }

    /// What the reminder says.
    ///
    /// Names the star and leaves it there. No count of what's undone, no
    /// mention of days, nothing a person could read as being told off.
    static func message(nextStarName: String?) -> String {
        guard let nextStarName else { return "Your sky is waiting." }
        return "\(nextStarName) is waiting to be lit."
    }
}
