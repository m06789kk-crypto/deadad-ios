import Foundation

enum Stats {
    static let appGroup = "group.com.deadblock.shared"

    private static var store: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func dayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func addBlocked() {
        guard let store else { return }
        let today = dayKey()
        let sameDay = store.string(forKey: "blocked_date") == today
        let todayCount = (sameDay ? store.integer(forKey: "blocked_today") : 0) + 1
        let total = store.integer(forKey: "blocked_total") + 1
        store.set(todayCount, forKey: "blocked_today")
        store.set(total, forKey: "blocked_total")
        store.set(today, forKey: "blocked_date")
    }

    static func snapshot() -> (today: Int, total: Int) {
        guard let store else { return (0, 0) }
        let today = store.string(forKey: "blocked_date") == dayKey()
            ? store.integer(forKey: "blocked_today")
            : 0
        return (today, store.integer(forKey: "blocked_total"))
    }

    static func reset() {
        guard let store else { return }
        store.set(0, forKey: "blocked_today")
        store.set(0, forKey: "blocked_total")
        store.set(dayKey(), forKey: "blocked_date")
    }
}
