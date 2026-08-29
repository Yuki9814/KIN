import Foundation

struct ProactiveMessagePolicy: Sendable {
    static let defaultFollowUpMinDays = 5
    static let defaultFollowUpMaxDays = 7
    static let minimumFollowUpDays = 1
    static let maximumFollowUpDays = 30

    static let followUpDelayRange: ClosedRange<TimeInterval> =
        followUpDelayRange(
            minDays: defaultFollowUpMinDays,
            maxDays: defaultFollowUpMaxDays
        )

    static func followUpDelayRange(
        minDays: Int,
        maxDays: Int
    ) -> ClosedRange<TimeInterval> {
        let lower = min(maximumFollowUpDays, max(minimumFollowUpDays, minDays))
        let upper = min(maximumFollowUpDays, max(lower, maxDays))
        let day: TimeInterval = 86_400
        return (TimeInterval(lower) * day)...(TimeInterval(upper) * day)
    }

    static func initialDelayRange(for affinityScore: Double) -> ClosedRange<TimeInterval> {
        let day: TimeInterval = 86_400
        switch min(100, max(0, affinityScore)) {
        case 0..<20: return (10 * day)...(14 * day)
        case 20..<50: return (7 * day)...(10 * day)
        case 50..<80: return (5 * day)...(7 * day)
        default: return (3 * day)...(5 * day)
        }
    }

    static func scheduledDate(
        from date: Date,
        affinityScore: Double,
        followUpCount: Int,
        randomUnit: Double = Double.random(in: 0...1),
        followUpDelayRange: ClosedRange<TimeInterval> = Self.followUpDelayRange,
        quietStartHour: Int = 23,
        quietEndHour: Int = 8,
        calendar: Calendar = .current
    ) -> Date {
        let range = followUpCount > 0
            ? followUpDelayRange
            : initialDelayRange(for: affinityScore)
        let unit = randomUnit.isFinite ? min(1, max(0, randomUnit)) : 0.5
        let raw = date.addingTimeInterval(
            range.lowerBound + (range.upperBound - range.lowerBound) * unit
        )
        return deferredOutOfQuietHours(
            raw,
            startHour: quietStartHour,
            endHour: quietEndHour,
            calendar: calendar
        )
    }

    static func deferredOutOfQuietHours(
        _ date: Date,
        startHour: Int,
        endHour: Int,
        calendar: Calendar = .current
    ) -> Date {
        let start = min(23, max(0, startHour))
        let end = min(23, max(0, endHour))
        guard start != end else { return date }
        let hour = calendar.component(.hour, from: date)
        let inQuietHours = start < end
            ? (hour >= start && hour < end)
            : (hour >= start || hour < end)
        guard inQuietHours else { return date }

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = end
        components.minute = 0
        components.second = 0
        guard var target = calendar.date(from: components) else { return date }
        if target <= date { target = calendar.date(byAdding: .day, value: 1, to: target) ?? date }
        return target
    }
}

#if os(iOS)
import UserNotifications

actor ProactiveNotificationService {
    static let shared = ProactiveNotificationService()

    func schedule(id: UUID, title: String, body: String, at date: Date) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let interval = max(1, date.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: id.uuidString.lowercased(),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        try? await center.add(request)
    }

    func cancel(ids: [UUID]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ids.map { $0.uuidString.lowercased() }
        )
    }
}
#endif
