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

/// The kind of proactive message represented by a local notification.
///
/// Keep the raw values stable: they are part of the notification request
/// identifier and can outlive an application process.
enum ProactiveNotificationStage: String, CaseIterable, Codable, Sendable {
    case initial
    case followUp
    case test
}

enum ProactiveNotificationAuthorizationStatus: String, CaseIterable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
}

/// Stable identifiers for KIN's native iOS chat notification type.
///
/// Keep these values stable because pending notifications may outlive the
/// application process and system notification settings are keyed by them.
enum KINSystemNotificationCategory {
    static let chatMessageIdentifier = "kin.chat-message"
    static let openChatActionIdentifier = "kin.open-chat"
}

/// The durable routing information carried by a proactive notification.
///
/// Notification request identifiers are intentionally derived only from the
/// task ID and stage.  Role and conversation IDs live in `userInfo`, where a
/// notification tap can recover the destination without changing the stable
/// identifier used for cancellation.
struct ProactiveNotificationRoute: Codable, Equatable, Sendable {
    let taskID: UUID
    let roleID: UUID
    let conversationID: UUID
    let stage: ProactiveNotificationStage

    private static let taskIDKey = "taskID"
    private static let roleIDKey = "roleID"
    private static let conversationIDKey = "conversationID"
    private static let stageKey = "stage"

    init(
        taskID: UUID,
        roleID: UUID,
        conversationID: UUID,
        stage: ProactiveNotificationStage
    ) {
        self.taskID = taskID
        self.roleID = roleID
        self.conversationID = conversationID
        self.stage = stage
    }

    /// Reconstructs a route from `UNNotificationContent.userInfo`.
    ///
    /// Values normally arrive as strings, but accepting UUID values as well
    /// makes this initializer useful in unit tests and when a caller builds a
    /// user-info dictionary directly.
    init?(userInfo: [AnyHashable: Any]) {
        guard let taskID = Self.uuid(from: userInfo[Self.taskIDKey]),
              let roleID = Self.uuid(from: userInfo[Self.roleIDKey]),
              let conversationID = Self.uuid(from: userInfo[Self.conversationIDKey]),
              let stage = Self.stage(from: userInfo[Self.stageKey]) else {
            return nil
        }
        self.init(
            taskID: taskID,
            roleID: roleID,
            conversationID: conversationID,
            stage: stage
        )
    }

    /// The property-list-safe payload written to a local notification.
    var userInfo: [AnyHashable: Any] {
        [
            Self.taskIDKey: taskID.uuidString.lowercased(),
            Self.roleIDKey: roleID.uuidString.lowercased(),
            Self.conversationIDKey: conversationID.uuidString.lowercased(),
            Self.stageKey: stage.rawValue
        ]
    }

    /// A stable identifier for one task/stage pair.
    var requestIdentifier: String {
        Self.requestIdentifier(taskID: taskID, stage: stage)
    }

    /// Returns every identifier that may have been used for the task.
    ///
    /// The first entry is the legacy UUID-only identifier.  The remaining
    /// entries cover all routed stages so cancelling an old task also removes
    /// notifications created by the new routing format.
    static func cancellationIdentifiers(for taskIDs: [UUID]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for taskID in taskIDs {
            for identifier in cancellationIdentifiers(for: taskID) where seen.insert(identifier).inserted {
                result.append(identifier)
            }
        }
        return result
    }

    static func cancellationIdentifiers(for taskID: UUID) -> [String] {
        let legacyIdentifier = taskID.uuidString.lowercased()
        let routedIdentifiers = ProactiveNotificationStage.allCases.map {
            requestIdentifier(taskID: taskID, stage: $0)
        }
        return [legacyIdentifier] + routedIdentifiers
    }

    private static func requestIdentifier(
        taskID: UUID,
        stage: ProactiveNotificationStage
    ) -> String {
        "proactive:\(taskID.uuidString.lowercased()):\(stage.rawValue)"
    }

    private static func uuid(from value: Any?) -> UUID? {
        if let value = value as? UUID { return value }
        if let value = value as? String { return UUID(uuidString: value) }
        if let value = value as? NSString { return UUID(uuidString: value as String) }
        return nil
    }

    private static func stage(from value: Any?) -> ProactiveNotificationStage? {
        if let value = value as? ProactiveNotificationStage { return value }
        if let value = value as? String { return ProactiveNotificationStage(rawValue: value) }
        if let value = value as? NSString {
            return ProactiveNotificationStage(rawValue: value as String)
        }
        return nil
    }
}

#if os(iOS)
import UserNotifications

extension KINSystemNotificationCategory {
    static var registeredCategories: Set<UNNotificationCategory> {
        let openChatAction = UNNotificationAction(
            identifier: openChatActionIdentifier,
            title: "打开聊天",
            options: [.foreground]
        )
        let chatMessageCategory = UNNotificationCategory(
            identifier: chatMessageIdentifier,
            actions: [openChatAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "收到一条新消息",
            options: []
        )
        return [chatMessageCategory]
    }

    static func shouldOpenChat(for actionIdentifier: String) -> Bool {
        actionIdentifier == UNNotificationDefaultActionIdentifier
            || actionIdentifier == openChatActionIdentifier
    }
}

actor ProactiveNotificationService {
    static let shared = ProactiveNotificationService()

    private var cancelledIdentifiers: Set<String> = []

    /// Returns the current system authorization state without prompting.
    func authorizationStatus() async -> ProactiveNotificationAuthorizationStatus {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .denied
        }
    }

    /// Requests alert, sound, and badge authorization from the system and
    /// returns the resulting status.
    func requestAuthorization() async -> ProactiveNotificationAuthorizationStatus {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )) ?? false
        guard granted else { return .denied }
        return await authorizationStatus()
    }

    func schedule(id: UUID, title: String, body: String, at date: Date) async {
        _ = await schedule(
            identifier: id.uuidString.lowercased(),
            title: title,
            body: body,
            at: date,
            userInfo: [:],
            threadIdentifier: nil,
            categoryIdentifier: nil,
            targetContentIdentifier: nil
        )
    }

    /// Schedules a routed proactive notification.
    ///
    /// A not-yet-decided authorization state may present the system prompt;
    /// denied authorization never creates a pending request.
    func schedule(
        route: ProactiveNotificationRoute,
        title: String,
        body: String,
        at date: Date
    ) async -> Bool {
        // `requestIdentifier` is route-stable, so adding this request again
        // updates the existing pending request instead of creating a second
        // notification for the same task/stage.
        let conversationIdentifier = route.conversationID.uuidString.lowercased()
        return await schedule(
            identifier: route.requestIdentifier,
            title: title,
            body: body,
            at: date,
            userInfo: route.userInfo,
            threadIdentifier: conversationIdentifier,
            categoryIdentifier: KINSystemNotificationCategory.chatMessageIdentifier,
            targetContentIdentifier: "conversation:\(conversationIdentifier)"
        )
    }

    func cancel(ids: [UUID]) {
        let identifiers = ProactiveNotificationRoute.cancellationIdentifiers(for: ids)
        let center = UNUserNotificationCenter.current()
        cancelledIdentifiers.formUnion(identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Returns delivered request identifiers for deterministic notification QA.
    func deliveredNotificationIdentifiers() async -> Set<String> {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                continuation.resume(
                    returning: Set(notifications.map { $0.request.identifier })
                )
            }
        }
    }

    /// Returns all currently pending request identifiers.
    func pendingNotificationIdentifiers() async -> Set<String> {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(
                    returning: Set(requests.map(\.identifier))
                )
            }
        }
    }

    private func schedule(
        identifier: String,
        title: String,
        body: String,
        at date: Date,
        userInfo: [AnyHashable: Any],
        threadIdentifier: String?,
        categoryIdentifier: String?,
        targetContentIdentifier: String?
    ) async -> Bool {
        let center = UNUserNotificationCenter.current()
        // Scheduling is an explicit replacement: a fresh request for this
        // stable identifier is allowed to clear an earlier cancellation.
        cancelledIdentifiers.remove(identifier)
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            let requestedStatus = await requestAuthorization()
            guard requestedStatus == .authorized
                    || requestedStatus == .provisional
                    || requestedStatus == .ephemeral else {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        content.sound = .default
        content.interruptionLevel = .active
        if let threadIdentifier {
            content.threadIdentifier = threadIdentifier
        }
        if let categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }
        if let targetContentIdentifier {
            content.targetContentIdentifier = targetContentIdentifier
        }
        let interval = max(1, date.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        do {
            try await center.add(request)
            guard !cancelledIdentifiers.contains(identifier) else {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
                return false
            }
            return true
        } catch {
            return false
        }
    }
}
#endif
