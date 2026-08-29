import Foundation
import SwiftUI

/// The scheduled-task screens share one small set of calendar and formatting
/// helpers.  Keeping these helpers value-only also means the views never hold
/// a SwiftData record across a refresh.
private enum ScheduledTasksSupport {
    static let maximumHourlyOccurrencesPerDay = 48
    static let maximumAgendaEntriesPerDay = 256

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        return calendar
    }

    static func calendar(timeZoneIdentifier: String) -> Calendar {
        var result = calendar
        if let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            result.timeZone = timeZone
        }
        return result
    }

    static var locale: Locale { Locale(identifier: "zh_CN") }

    static func normalizedFrequency(_ frequency: MomentTaskRecurrenceFrequency) -> String {
        String(describing: frequency)
            .split(separator: ".")
            .last
            .map(String.init)?
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            ?? "once"
    }

    static func frequencyTitle(
        _ frequency: MomentTaskRecurrenceFrequency,
        interval: Int = 1,
        weekday: Int? = nil,
        monthDay: Int? = nil
    ) -> String {
        let safeInterval = max(interval, 1)
        switch normalizedFrequency(frequency) {
        case "hourly", "hour":
            return safeInterval == 1 ? "每小时" : "每\(safeInterval)小时"
        case "daily", "day":
            return safeInterval == 1 ? "每天" : "每\(safeInterval)天"
        case "weekly", "week":
            let weekdayTitle = weekday.map(weekdayTitle(for:))
            if safeInterval == 1 {
                return weekdayTitle.map { "每\($0)" } ?? "每周"
            }
            return weekdayTitle.map { "每\(safeInterval)周\($0)" } ?? "每\(safeInterval)周"
        case "monthly", "month":
            if let monthDay {
                return safeInterval == 1
                    ? "每月\(monthDay)日"
                    : "每\(safeInterval)个月\(monthDay)日"
            }
            return safeInterval == 1 ? "每月" : "每\(safeInterval)个月"
        default:
            return "一次"
        }
    }

    static func weekdayTitle(for weekday: Int) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        guard names.indices.contains(weekday - 1) else { return "周\(weekday)" }
        return names[weekday - 1]
    }

    static func relativeDate(_ date: Date, now: Date = Date()) -> String {
        let calendar = calendar
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天 \(time)"
        }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    static func effectiveTime(_ task: CompanionMomentTaskSummary) -> Date {
        max(task.scheduledAt, task.nextAttemptAt ?? .distantPast)
    }

    static func isBirthdayAutomationEligible(_ companion: CompanionProfileSummary) -> Bool {
        companion.relationshipState == .accepted
            && companion.contactMembership == .active
    }

    static func dayTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month().day())
    }

    static func monthTitle(_ date: Date) -> String {
        date.formatted(.dateTime.year().month())
    }

    static func birthdayMonthDay(month: Int?, day: Int?) -> BirthdayMonthDay? {
        guard let month, let day else { return nil }
        return BirthdayMonthDay(month: month, day: day)
    }

    static func birthdayOccurrence(
        month: Int?,
        day: Int?,
        year: Int,
        roleID: UUID,
        kind: BirthdayAutomationKind,
        timeZoneIdentifier: String
    ) -> BirthdayAutomationOccurrence? {
        guard let birthday = birthdayMonthDay(month: month, day: day) else {
            return nil
        }
        let policy = BirthdayAutomationPolicy(timeZoneIdentifier: timeZoneIdentifier)
        switch kind {
        case .userBirthdayGreeting:
            return policy.userBirthdayGreetingOccurrence(
                roleID: roleID,
                birthday: birthday,
                localYear: year
            )
        case .roleBirthdayCheckIn:
            return policy.roleBirthdayCheckInOccurrence(
                roleID: roleID,
                birthday: birthday,
                localYear: year
            )
        }
    }

    static func birthdayDate(
        month: Int?,
        day: Int?,
        year: Int,
        roleID: UUID,
        kind: BirthdayAutomationKind,
        timeZoneIdentifier: String
    ) -> Date? {
        birthdayOccurrence(
            month: month,
            day: day,
            year: year,
            roleID: roleID,
            kind: kind,
            timeZoneIdentifier: timeZoneIdentifier
        )?.scheduledAt
    }

    static func birthdayLabel(
        month: Int?,
        day: Int?,
        year: Int,
        roleID: UUID,
        kind: BirthdayAutomationKind,
        timeZoneIdentifier: String
    ) -> String? {
        let policy = BirthdayAutomationPolicy(timeZoneIdentifier: timeZoneIdentifier)
        guard let occurrence = birthdayOccurrence(
            month: month,
            day: day,
            year: year,
            roleID: roleID,
            kind: kind,
            timeZoneIdentifier: timeZoneIdentifier
        ) else {
            return nil
        }
        let components = policy.calendar.dateComponents(
            [.month, .day],
            from: occurrence.scheduledAt
        )
        guard let resolvedMonth = components.month, let resolvedDay = components.day else {
            return nil
        }
        return "\(resolvedMonth)月\(resolvedDay)日"
    }

    static func daysInMonth(_ month: Int) -> Int {
        let maximumDays = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard maximumDays.indices.contains(month - 1) else { return 31 }
        return maximumDays[month - 1]
    }

    /// The data layer may add fields to the recurrence rule over time.  The
    /// UI only needs these scalar values, so Mirror keeps the presentation
    /// boundary tolerant of extra persisted metadata while retaining the
    /// typed rule for saving.
    static func recurrenceDescriptor(
        _ rule: MomentTaskRecurrenceRule
    ) -> (frequency: String, interval: Int, weekday: Int?, monthDay: Int?) {
        var frequency = "once"
        var interval = 1
        var weekday: Int?
        var monthDay: Int?

        for child in Mirror(reflecting: rule).children {
            guard let label = child.label?.lowercased() else { continue }
            let value = unwrapOptional(child.value)
            switch label {
            case "frequency", "frequencyraw":
                frequency = String(describing: value)
                    .split(separator: ".")
                    .last
                    .map(String.init)?
                    .lowercased()
                    .replacingOccurrences(of: "_", with: "") ?? frequency
            case "interval":
                interval = (value as? Int) ?? interval
            case "weekday", "week day", "weekdayvalue":
                weekday = value as? Int
            case "monthday", "monthdayvalue", "dayofmonth":
                monthDay = value as? Int
            default:
                continue
            }
        }
        return (frequency, max(interval, 1), weekday, monthDay)
    }

    static func recurrenceRule(for task: CompanionMomentTaskSummary) -> MomentTaskRecurrenceRule {
        return MomentTaskRecurrenceRule(
            recurrenceRaw: task.recurrenceRaw,
            recurrenceInterval: task.recurrenceInterval,
            recurrenceWeekday: task.recurrenceWeekday,
            recurrenceDayOfMonth: task.recurrenceDayOfMonth,
            recurrenceHour: task.recurrenceHour,
            recurrenceMinute: task.recurrenceMinute,
            timezoneIdentifier: task.timezoneIdentifier,
            scheduledAt: task.scheduledAt,
            seriesID: task.seriesID
        )
    }

    private static func unwrapOptional(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first.map { unwrapOptional($0.value) } ?? value
    }

    static func isOneTime(_ rule: MomentTaskRecurrenceRule) -> Bool {
        let key = recurrenceDescriptor(rule).frequency
        return ["once", "onetime", "oneoff", "single"].contains(key)
    }

    static func recurrenceDescription(_ rule: MomentTaskRecurrenceRule) -> String {
        let descriptor = recurrenceDescriptor(rule)
        return frequencyTitle(
            rule.frequency,
            interval: descriptor.interval,
            weekday: descriptor.weekday,
            monthDay: descriptor.monthDay
        )
    }

    static func makeRule(
        frequency: MomentTaskRecurrenceFrequency,
        interval: Int,
        weekday: Int?,
        monthDay: Int?,
        scheduledAt: Date,
        timezoneIdentifier: String = TimeZone.current.identifier,
        seriesID: UUID? = nil
    ) -> MomentTaskRecurrenceRule {
        let scheduleCalendar = calendar(timeZoneIdentifier: timezoneIdentifier)
        return MomentTaskRecurrenceRule(
            frequency: frequency,
            interval: max(interval, 1),
            weekday: weekday,
            dayOfMonth: monthDay,
            hour: scheduleCalendar.component(.hour, from: scheduledAt),
            minute: scheduleCalendar.component(.minute, from: scheduledAt),
            timezoneIdentifier: timezoneIdentifier,
            scheduledAt: scheduledAt,
            seriesID: seriesID
        )
    }

    static func defaultFrequency() -> MomentTaskRecurrenceFrequency {
        MomentTaskRecurrenceFrequency.allCases.first {
            let key = normalizedFrequency($0)
            return ["once", "onetime", "oneoff", "single"].contains(key)
        } ?? MomentTaskRecurrenceFrequency.allCases[0]
    }

    static func frequency(for rawKey: String) -> MomentTaskRecurrenceFrequency {
        MomentTaskRecurrenceFrequency.allCases.first {
            normalizedFrequency($0) == rawKey
                || (rawKey == "once" && ["onetime", "oneoff", "single"].contains(normalizedFrequency($0)))
        } ?? defaultFrequency()
    }

    static func roleName(
        _ roleID: UUID,
        in companions: [CompanionProfileSummary]
    ) -> String {
        companions.first { RoleScope.resolve($0.id) == RoleScope.resolve(roleID) }?.name ?? "角色"
    }

    static func roleAvatar(
        _ roleID: UUID,
        in companions: [CompanionProfileSummary]
    ) -> (name: String, imageData: Data?) {
        guard let role = companions.first(where: { RoleScope.resolve($0.id) == RoleScope.resolve(roleID) }) else {
            return ("角色", nil)
        }
        return (role.name, role.avatarImageData)
    }
}

private struct ScheduledTasksHeader: View {
    let title: String
    var showsPlus = false
    var plusAction: (() -> Void)?
    var menuActions: [(title: String, systemImage: String, action: () -> Void)] = []

    var body: some View {
        #if os(iOS)
        ZStack {
            WeChatBackHeader(title: title)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if !menuActions.isEmpty {
                    Menu {
                        ForEach(menuActions.indices, id: \.self) { index in
                            let action = menuActions[index]
                            Button(action: action.action) {
                                Label(action.title, systemImage: action.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(AppTheme.iconPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("定时任务更多操作")
                    .accessibilityIdentifier("scheduled-tasks.menu")
                }
                if showsPlus, let plusAction {
                    Button(action: plusAction) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(AppTheme.iconPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新建定时任务")
                    .accessibilityIdentifier("scheduled-tasks.add")
                }
            }
            .padding(.trailing, 2)
        }
        .frame(height: 56)
        .background(AppTheme.rootBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)
        }
        #else
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
            Spacer(minLength: 0)
            if !menuActions.isEmpty {
                Menu {
                    ForEach(menuActions.indices, id: \.self) { index in
                        let action = menuActions[index]
                        Button(action: action.action) {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.iconPrimary)
                        .frame(width: 44, height: 44)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("定时任务更多操作")
                .accessibilityIdentifier("scheduled-tasks.menu")
            }
            if showsPlus, let plusAction {
                Button(action: plusAction) {
                    Image(systemName: "plus")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.iconPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建定时任务")
                .accessibilityIdentifier("scheduled-tasks.add")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(AppTheme.barBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)
        }
        #endif
    }
}

private struct ScheduledTasksDisclosureIndicator: View {
    var body: some View {
        #if os(iOS)
        WeChatDisclosureIndicator()
        #else
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.tertiaryText)
            .accessibilityHidden(true)
        #endif
    }
}

private struct ScheduledTasksIconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        #if os(iOS)
        WeChatIconTile(systemImage: systemImage, color: color, size: size)
        #else
        Image(systemName: systemImage)
            .font(.system(size: size * 0.49, weight: .medium))
            .foregroundStyle(AppTheme.iconOnAccent)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
        #endif
    }
}

private struct ScheduledTaskEditorRequest: Identifiable {
    let id = UUID()
    let task: CompanionMomentTaskSummary?
}

private enum ScheduledTasksDestination: Hashable, Identifiable {
    case calendar
    case birthdays
    case history

    var id: String {
        switch self {
        case .calendar: "calendar"
        case .birthdays: "birthdays"
        case .history: "history"
        }
    }
}

struct ScheduledTasksHomeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var destination: ScheduledTasksDestination?
    @State private var editorRequest: ScheduledTaskEditorRequest?

    var body: some View {
        VStack(spacing: 0) {
            ScheduledTasksHeader(
                title: "定时任务",
                showsPlus: true,
                plusAction: { editorRequest = ScheduledTaskEditorRequest(task: nil) },
                menuActions: [
                    ("任务日历", "calendar", { destination = .calendar }),
                    ("生日与日期", "gift", { destination = .birthdays }),
                    ("执行记录", "clock.arrow.circlepath", { destination = .history })
                ]
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    scheduledStatusBanner
                    taskSection(
                        title: "下一次",
                        content: { nextTaskContent }
                    )
                    taskSection(
                        title: "循环任务",
                        content: { recurringTaskContent }
                    )
                    birthdaySection

                    Text("错过时间会在下次打开应用时补执行")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                        .padding(.bottom, 34)
                }
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
            .background(AppTheme.rootBackground)
        }
        .background(AppTheme.rootBackground.ignoresSafeArea())
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .restoresWeChatEdgeBackGesture()
        .wechatEdgeBackFallback()
        #else
        .navigationTitle("定时任务")
        #endif
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .calendar:
                ScheduledTasksCalendarView()
            case .birthdays:
                BirthdayManagementView()
            case .history:
                ScheduledTaskHistoryView()
            }
        }
        .sheet(item: $editorRequest) { request in
            NavigationStack {
                ScheduledMomentTaskEditor(task: request.task)
            }
            #if os(iOS)
            .presentationDetents([.large])
            #else
            .frame(minWidth: 480, minHeight: 620)
            #endif
        }
        .onAppear {
            appModel.refreshFromStore()
        }
        .accessibilityIdentifier("scheduled-tasks.home")
    }

    @ViewBuilder
    private var scheduledStatusBanner: some View {
        if let message = appModel.errorMessage, !message.isEmpty {
            StatusBanner(text: message, style: .error)
                .padding(.top, 12)
                .padding(.bottom, 4)
        } else if let message = appModel.momentStatusText, !message.isEmpty {
            StatusBanner(text: message, style: .information)
                .padding(.top, 12)
                .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func taskSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.leading, 8)
                .padding(.top, 25)

            content()
        }
    }

    @ViewBuilder
    private var nextTaskContent: some View {
        let tasks = activeTasks.sorted {
            let lhs = ScheduledTasksSupport.effectiveTime($0)
            let rhs = ScheduledTasksSupport.effectiveTime($1)
            if lhs != rhs { return lhs < rhs }
            return $0.id.uuidString < $1.id.uuidString
        }
        if let next = tasks.first {
            ScheduledTaskRow(
                task: next,
                role: ScheduledTasksSupport.roleAvatar(next.roleID, in: appModel.companions),
                showsToggle: false,
                isEnabled: true,
                toggle: nil,
                action: { editorRequest = ScheduledTaskEditorRequest(task: next) }
            )
        } else {
            ScheduledTasksEmptyCard(
                title: "没有待执行任务",
                message: "点右上角加号，安排角色发布下一条朋友圈。",
                systemImage: "calendar.badge.plus",
                action: { editorRequest = ScheduledTaskEditorRequest(task: nil) }
            )
        }
    }

    @ViewBuilder
    private var recurringTaskContent: some View {
        // A series can retain published/cancelled occurrences for history.
        // The home screen represents each series once, using its latest
        // occurrence so a paused series stays visible and can be resumed.
        let tasks = recurringSeriesTasks
        if tasks.isEmpty {
            ScheduledTasksEmptyCard(
                title: "还没有循环任务",
                message: "每日、每周或每月的朋友圈规则会显示在这里。",
                systemImage: "repeat",
                action: { editorRequest = ScheduledTaskEditorRequest(task: nil) }
            )
        } else {
            VStack(spacing: 0) {
                ForEach(tasks) { task in
                    ScheduledTaskRow(
                        task: task,
                        role: ScheduledTasksSupport.roleAvatar(task.roleID, in: appModel.companions),
                        showsToggle: true,
                        isEnabled: seriesIsEnabled(task),
                        toggle: { enabled in
                            setSeriesEnabled(for: task, enabled: enabled)
                        },
                        action: { editorRequest = ScheduledTaskEditorRequest(task: task) }
                    )
                    if task.id != tasks.last?.id {
                        Rectangle()
                            .fill(AppTheme.divider)
                            .frame(height: 0.5)
                            .padding(.leading, 76)
                    }
                }
            }
            .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var birthdaySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("生日")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.leading, 8)
                .padding(.top, 25)

            VStack(spacing: 0) {
                Button {
                    destination = .birthdays
                } label: {
                    HStack(spacing: 14) {
                        ScheduledTasksIconTile(systemImage: "birthday.cake.fill", color: AppTheme.accent, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("我的生日")
                                .font(.system(size: 17))
                                .foregroundStyle(AppTheme.primaryText)
                            Text(userBirthdaySummary)
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        if let date = userBirthdayDateLabel {
                            Text(date)
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.secondaryText)
                        } else {
                            Text("未设置")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                        ScheduledTasksDisclosureIndicator()
                    }
                    .frame(minHeight: 72)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .accessibilityLabel("我的生日")
                .accessibilityValue(userBirthdaySummary)
                .accessibilityIdentifier("scheduled-tasks.birthday.user")

                Rectangle()
                    .fill(AppTheme.divider)
                    .frame(height: 0.5)
                    .padding(.leading, 72)

                Button {
                    destination = .birthdays
                } label: {
                    HStack(spacing: 14) {
                        ScheduledTasksIconTile(systemImage: "calendar", color: AppTheme.accent, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("角色生日")
                                .font(.system(size: 17))
                                .foregroundStyle(AppTheme.primaryText)
                            Text("未祝福时，角色会在当天主动问候")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Text("已设置 \(companionsWithBirthdayCount) 位")
                            .font(.system(size: 15))
                            .foregroundStyle(AppTheme.secondaryText)
                        ScheduledTasksDisclosureIndicator()
                    }
                    .frame(minHeight: 72)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .accessibilityLabel("角色生日")
                .accessibilityValue("已设置 \(companionsWithBirthdayCount) 位")
                .accessibilityIdentifier("scheduled-tasks.birthday.companions")
            }
            .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var activeTasks: [CompanionMomentTaskSummary] {
        appModel.momentTasks.filter {
            $0.state == .scheduled || $0.state == .running
        }
    }

    private var recurringSeriesTasks: [CompanionMomentTaskSummary] {
        let recurring = appModel.momentTasks.filter {
            !ScheduledTasksSupport.isOneTime(
                ScheduledTasksSupport.recurrenceRule(for: $0)
            )
        }
        let grouped = Dictionary(grouping: recurring) { task in
            (task.seriesID ?? task.id).uuidString.lowercased()
        }
        return grouped.values.compactMap { occurrences in
            occurrences.max {
                if $0.scheduledAt != $1.scheduledAt {
                    return $0.scheduledAt < $1.scheduledAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
        .sorted {
            if $0.scheduledAt != $1.scheduledAt {
                return $0.scheduledAt < $1.scheduledAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var companionsWithBirthdayCount: Int {
        appModel.companions.filter {
            ScheduledTasksSupport.isBirthdayAutomationEligible($0)
                && $0.birthdayMonth != nil
                && $0.birthdayDay != nil
        }.count
    }

    private var userBirthdaySummary: String {
        guard let month = appModel.userProfile.birthdayMonth,
              let day = appModel.userProfile.birthdayDay else {
            return "设置后，角色会在各自对话里记得这一天"
        }
        return "每年 \(month) 月 \(day) 日，角色会在对话里祝福"
    }

    private var userBirthdayDateLabel: String? {
        let policy = BirthdayAutomationPolicy(
            timeZoneIdentifier: appModel.userProfile.birthdayTimeZoneIdentifier
        )
        return ScheduledTasksSupport.birthdayLabel(
            month: appModel.userProfile.birthdayMonth,
            day: appModel.userProfile.birthdayDay,
            year: policy.calendar.component(.year, from: Date()),
            roleID: appModel.userProfile.id,
            kind: .userBirthdayGreeting,
            timeZoneIdentifier: appModel.userProfile.birthdayTimeZoneIdentifier
        )
    }

    private func setSeriesEnabled(for task: CompanionMomentTaskSummary, enabled: Bool) {
        do {
            try appModel.setMomentSeriesEnabled(
                seriesID: task.seriesID ?? task.id,
                enabled: enabled
            )
        } catch {
            appModel.errorMessage = error.localizedDescription
        }
    }

    private func seriesIsEnabled(_ task: CompanionMomentTaskSummary) -> Bool {
        let seriesID = task.seriesID ?? task.id
        return appModel.momentTasks.contains {
            ($0.seriesID ?? $0.id) == seriesID
                && ($0.state == .scheduled || $0.state == .running)
        }
    }
}

private struct ScheduledTasksEmptyCard: View {
    let title: String
    let message: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                ScheduledTasksDisclosureIndicator()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(title)
        .accessibilityValue(message)
    }
}

private struct ScheduledTaskRow: View {
    let task: CompanionMomentTaskSummary
    let role: (name: String, imageData: Data?)
    let showsToggle: Bool
    let isEnabled: Bool
    let toggle: ((Bool) -> Void)?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    CompanionAvatar(size: 56, name: role.name, imageData: role.imageData)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(
                                showsToggle
                                    ? taskTitle
                                    : ScheduledTasksSupport.relativeDate(
                                        ScheduledTasksSupport.effectiveTime(task)
                                    )
                            )
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(AppTheme.primaryText)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if showsToggle == false {
                                Text(
                                    ScheduledTasksSupport.recurrenceDescription(
                                        ScheduledTasksSupport.recurrenceRule(for: task)
                                    )
                                )
                                    .font(.system(size: 15))
                                    .foregroundStyle(AppTheme.primaryText)
                                    .lineLimit(1)
                            }
                        }
                        Text(task.instruction)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if showsToggle {
                            Text(
                                ScheduledTasksSupport.recurrenceDescription(
                                    ScheduledTasksSupport.recurrenceRule(for: task)
                                )
                            )
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.secondaryText)
                        } else {
                            Text(role.name)
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsToggle, let toggle {
                Toggle(
                    "启用\(taskTitle)的循环任务",
                    isOn: Binding(
                        get: { isEnabled },
                        set: toggle
                    )
                )
                .labelsHidden()
                .tint(AppTheme.accent)
                .frame(minWidth: 52, minHeight: 44)
                .accessibilityLabel("启用\(taskTitle)的循环任务")
                .accessibilityValue(isEnabled ? "已启用" : "已停用")
                .accessibilityIdentifier("scheduled-tasks.toggle.\(task.id.uuidString)")
            } else {
                ScheduledTasksDisclosureIndicator()
                    .frame(width: 24, height: 44)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 82)
        .background(AppTheme.secondarySurface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scheduled-tasks.row.\(task.id.uuidString)")
    }

    private var taskTitle: String {
        role.name
    }
}

struct ScheduledTasksCalendarView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedDate = Date()
    @State private var destination: ScheduledTasksDestination?
    @State private var editorRequest: ScheduledTaskEditorRequest?

    var body: some View {
        VStack(spacing: 0) {
            ScheduledTasksHeader(
                title: "定时任务",
                showsPlus: true,
                plusAction: { editorRequest = ScheduledTaskEditorRequest(task: nil) }
            )
            ScrollView {
                LazyVStack(spacing: 0) {
                    calendarStrip
                    agendaContent
                    Text("错过时间会在下次打开应用时补执行")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
            }
            .scrollIndicators(.hidden)
            .background(AppTheme.rootBackground)
        }
        .background(AppTheme.rootBackground.ignoresSafeArea())
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .restoresWeChatEdgeBackGesture()
        .wechatEdgeBackFallback()
        #else
        .navigationTitle("任务日历")
        #endif
        .sheet(item: $editorRequest) { request in
            NavigationStack { ScheduledMomentTaskEditor(task: request.task) }
            #if os(iOS)
            .presentationDetents([.large])
            #else
            .frame(minWidth: 480, minHeight: 620)
            #endif
        }
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .calendar:
                ScheduledTasksCalendarView()
            case .birthdays:
                BirthdayManagementView()
            case .history:
                ScheduledTaskHistoryView()
            }
        }
        .onAppear { appModel.refreshFromStore() }
        .accessibilityIdentifier("scheduled-tasks.calendar")
    }

    private var calendar: Calendar { ScheduledTasksSupport.calendar }

    private var weekDates: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return [selectedDate]
        }
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    private var calendarStrip: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(ScheduledTasksSupport.monthTitle(selectedDate))
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer(minLength: 0)
                weekNavigationButton(
                    systemImage: "chevron.left",
                    label: "上一周",
                    identifier: "scheduled-tasks.calendar.previous-week",
                    value: -1
                )
                weekNavigationButton(
                    systemImage: "chevron.right",
                    label: "下一周",
                    identifier: "scheduled-tasks.calendar.next-week",
                    value: 1
                )
            }
            .padding(.horizontal, 14)

            HStack(spacing: 0) {
                ForEach(weekDates, id: \.self) { date in
                    Button {
                        selectedDate = date
                    } label: {
                        VStack(spacing: 9) {
                            Text(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1])
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.secondaryText)
                            Text(calendar.component(.day, from: date), format: .number)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(isSelected(date) ? .white : AppTheme.primaryText)
                                .frame(width: 40, height: 40)
                                .background(isSelected(date) ? AppTheme.accent : .clear, in: Circle())
                            Circle()
                                .fill(hasEntries(on: date) ? AppTheme.accent : .clear)
                                .frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity, minHeight: 82)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(calendarDateAccessibilityLabel(date))
                    .accessibilityValue(hasEntries(on: date) ? "有任务或生日" : "无任务")
                    .accessibilityAddTraits(isSelected(date) ? .isSelected : [])
                    .accessibilityIdentifier("scheduled-tasks.calendar.day.\(calendar.startOfDay(for: date).timeIntervalSince1970)")
                }
            }
        }
        .padding(.vertical, 18)
        .background(AppTheme.secondarySurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)
        }
    }

    private func weekNavigationButton(
        systemImage: String,
        label: String,
        identifier: String,
        value: Int
    ) -> some View {
        Button {
            if let date = calendar.date(byAdding: .weekOfYear, value: value, to: selectedDate) {
                selectedDate = date
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.iconPrimary)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var agendaContent: some View {
        let selectedEntries = entries(on: selectedDate)
        let upcomingEntries = entries(after: selectedDate)
        VStack(spacing: 0) {
            agendaSection(
                title: calendar.isDateInToday(selectedDate)
                    ? "今天 · \(ScheduledTasksSupport.dayTitle(selectedDate))"
                    : ScheduledTasksSupport.dayTitle(selectedDate),
                entries: selectedEntries
            )
            agendaSection(title: "接下来", entries: upcomingEntries, showsDates: true)
        }
    }

    @ViewBuilder
    private func agendaSection(
        title: String,
        entries: [ScheduledAgendaItem],
        showsDates: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(entries.isEmpty ? AppTheme.secondaryText : AppTheme.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.rootBackground)

            if entries.isEmpty {
                Text(title == "接下来" ? "未来 30 天暂时没有更多安排" : "这一天没有任务或生日")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 56)
                    .padding(.vertical, 24)
                    .background(AppTheme.secondarySurface)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        ScheduledAgendaRow(entry: entry, showsDate: showsDates) {
                            if let taskID = entry.taskID,
                               let task = appModel.momentTasks.first(where: { $0.id == taskID }) {
                                editorRequest = ScheduledTaskEditorRequest(task: task)
                            } else {
                                destination = .birthdays
                            }
                        }
                        if entry.id != entries.last?.id {
                            Rectangle()
                                .fill(AppTheme.divider)
                                .frame(height: 0.5)
                                .padding(.leading, 170)
                        }
                    }
                }
                .background(AppTheme.secondarySurface)
            }
        }
    }

    private var activeTasks: [CompanionMomentTaskSummary] {
        let pending = appModel.momentTasks.filter {
            $0.state == .scheduled || $0.state == .running
        }
        let oneTime = pending.filter {
            ScheduledTasksSupport.isOneTime(
                ScheduledTasksSupport.recurrenceRule(for: $0)
            )
        }
        let recurring = pending.filter {
            !ScheduledTasksSupport.isOneTime(
                ScheduledTasksSupport.recurrenceRule(for: $0)
            )
        }
        let nextBySeries = Dictionary(grouping: recurring) {
            ($0.seriesID ?? $0.id).uuidString.lowercased()
        }.values.compactMap { occurrences in
            occurrences.min {
                if $0.scheduledAt != $1.scheduledAt {
                    return $0.scheduledAt < $1.scheduledAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
        return oneTime + nextBySeries
    }

    private func entries(on date: Date) -> [ScheduledAgendaItem] {
        let taskEntries = activeTasks.flatMap { task -> [ScheduledAgendaItem] in
            let occurrences = occurrences(of: task, on: date)
            let role = ScheduledTasksSupport.roleAvatar(task.roleID, in: appModel.companions)
            let subtitle = ScheduledTasksSupport.recurrenceDescription(
                ScheduledTasksSupport.recurrenceRule(for: task)
            )
            return occurrences.enumerated().map { index, occurrence in
                ScheduledAgendaItem(
                    id: "task-\(task.id.uuidString)-\(calendar.startOfDay(for: date).timeIntervalSince1970)-\(index)",
                    date: occurrence,
                    title: task.instruction,
                    subtitle: subtitle,
                    roleName: role.name,
                    avatarImageData: role.imageData,
                    systemImage: nil,
                    tint: AppTheme.accent,
                    taskID: task.id
                )
            }
        }
        let birthdayEntries = birthdayEntries(on: date)
        let sortedEntries = (taskEntries + birthdayEntries).sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        return Array(sortedEntries.prefix(ScheduledTasksSupport.maximumAgendaEntriesPerDay))
    }

    private func entries(after date: Date) -> [ScheduledAgendaItem] {
        let start = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let end = calendar.date(byAdding: .day, value: 30, to: start) ?? start
        let candidates = (0..<30).flatMap { offset -> [ScheduledAgendaItem] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return [] }
            return entries(on: day)
        }
        .filter { $0.date < end }

        // “接下来”是系列摘要：每个任务只展示最近一次，但生日全部保留。
        // 选中某一天时仍会在上方完整展示该日的 hourly 等全部 occurrence。
        var representedTaskIDs = Set<UUID>()
        return candidates.filter { entry in
            guard let taskID = entry.taskID else { return true }
            return representedTaskIDs.insert(taskID).inserted
        }
    }

    private func birthdayEntries(on date: Date) -> [ScheduledAgendaItem] {
        var result: [ScheduledAgendaItem] = []
        let userTimeZoneIdentifier = appModel.userProfile.birthdayTimeZoneIdentifier
        if let birthday = displayedBirthdayOccurrence(
            month: appModel.userProfile.birthdayMonth,
            day: appModel.userProfile.birthdayDay,
            roleID: appModel.userProfile.id,
            kind: .userBirthdayGreeting,
            timeZoneIdentifier: userTimeZoneIdentifier,
            on: date
        ) {
            result.append(
                ScheduledAgendaItem(
                    id: "birthday-user-\(birthday.localYear)",
                    date: birthday.scheduledAt,
                    title: "我的生日",
                    subtitle: "所有角色会在各自对话里祝福",
                    roleName: appModel.userProfile.displayName,
                    avatarImageData: appModel.userProfile.avatarImageData,
                    systemImage: "gift.fill",
                    tint: AppTheme.accent,
                    taskID: nil
                )
            )
        }
        for companion in appModel.companions
        where ScheduledTasksSupport.isBirthdayAutomationEligible(companion) {
            let timeZoneIdentifier = appModel.worldTimeZoneIdentifier(for: companion.id)
            guard let birthday = displayedBirthdayOccurrence(
                month: companion.birthdayMonth,
                day: companion.birthdayDay,
                roleID: companion.id,
                kind: .roleBirthdayCheckIn,
                timeZoneIdentifier: timeZoneIdentifier,
                on: date
            ) else { continue }
            result.append(
                ScheduledAgendaItem(
                    id: "birthday-\(companion.id.uuidString)-\(birthday.localYear)",
                    date: birthday.scheduledAt,
                    title: "\(companion.name)的生日",
                    subtitle: "生日提醒",
                    roleName: companion.name,
                    avatarImageData: companion.avatarImageData,
                    systemImage: "birthday.cake.fill",
                    tint: AppTheme.accent,
                    taskID: nil
                )
            )
        }
        return result
    }

    private func occurrences(of task: CompanionMomentTaskSummary, on day: Date) -> [Date] {
        let rule = ScheduledTasksSupport.recurrenceRule(for: task)
        let effectiveTime = ScheduledTasksSupport.effectiveTime(task)
        let dayInterval = calendar.dateInterval(of: .day, for: day)
            ?? DateInterval(start: calendar.startOfDay(for: day), duration: 86_400)
        let dayStart = dayInterval.start
        let dayEnd = dayInterval.end
        guard rule.frequency.isRecurring else {
            return dayInterval.contains(effectiveTime) ? [effectiveTime] : []
        }

        if rule.frequency != .hourly {
            if dayInterval.contains(effectiveTime) {
                return [effectiveTime]
            }
            guard dayStart > effectiveTime,
                  let candidate = rule.nextOccurrence(
                      after: max(effectiveTime, dayStart.addingTimeInterval(-1))
                  ),
                  dayInterval.contains(candidate) else {
                return []
            }
            return [candidate]
        }

        var result: [Date] = []
        let searchStart: Date
        if dayInterval.contains(effectiveTime) {
            result.append(effectiveTime)
            searchStart = effectiveTime
        } else {
            guard dayStart > effectiveTime else { return [] }
            searchStart = max(effectiveTime, dayStart.addingTimeInterval(-1))
        }
        guard var candidate = rule.nextOccurrence(after: searchStart) else { return result }
        while candidate < dayEnd,
              result.count < ScheduledTasksSupport.maximumHourlyOccurrencesPerDay {
            if candidate >= dayStart, candidate > effectiveTime {
                result.append(candidate)
            }
            guard let next = rule.nextOccurrence(after: candidate), next > candidate else {
                break
            }
            candidate = next
        }
        return result
    }

    private func displayedBirthdayOccurrence(
        month: Int?,
        day: Int?,
        roleID: UUID,
        kind: BirthdayAutomationKind,
        timeZoneIdentifier: String,
        on displayedDate: Date
    ) -> BirthdayAutomationOccurrence? {
        let displayedYear = calendar.component(.year, from: displayedDate)
        // An occurrence near New Year can belong to the adjacent configured
        // local year while appearing on this device's previous/next day.
        return ((displayedYear - 1)...(displayedYear + 1)).compactMap { localYear in
            ScheduledTasksSupport.birthdayOccurrence(
                month: month,
                day: day,
                year: localYear,
                roleID: roleID,
                kind: kind,
                timeZoneIdentifier: timeZoneIdentifier
            )
        }.first {
            calendar.isDate($0.scheduledAt, inSameDayAs: displayedDate)
        }
    }

    private func hasEntries(on date: Date) -> Bool {
        !entries(on: date).isEmpty
    }

    private func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func calendarDateAccessibilityLabel(_ date: Date) -> String {
        let day = ScheduledTasksSupport.dayTitle(date)
        return calendar.isDateInToday(date) ? "今天，\(day)" : day
    }
}

private struct ScheduledAgendaItem: Identifiable {
    let id: String
    let date: Date
    let title: String
    let subtitle: String
    let roleName: String
    let avatarImageData: Data?
    let systemImage: String?
    let tint: Color
    let taskID: UUID?
}

private struct ScheduledAgendaRow: View {
    let entry: ScheduledAgendaItem
    let showsDate: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    if showsDate {
                        Text(entry.date.formatted(.dateTime.month().day()))
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Text(entry.date.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.secondaryText)
                    if entry.taskID == nil {
                        Text("全天")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .frame(width: 66, alignment: .trailing)

                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(AppTheme.divider)
                        .frame(width: 1)
                    Circle()
                        .fill(entry.tint)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(AppTheme.rootBackground, lineWidth: 2))
                        .offset(y: 7)
                }
                .frame(width: 18)

                HStack(spacing: 13) {
                    if let systemImage = entry.systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(entry.tint)
                            .frame(width: 56, height: 56)
                            .background(entry.tint.opacity(0.13), in: Circle())
                    } else {
                        CompanionAvatar(
                            size: 56,
                            name: entry.roleName,
                            imageData: entry.avatarImageData
                        )
                        .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(entry.subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if entry.taskID != nil {
                        ScheduledTasksDisclosureIndicator()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.title)
        .accessibilityValue(entry.subtitle)
        .accessibilityIdentifier("scheduled-tasks.agenda.\(entry.id)")
    }
}

struct ScheduledMomentTaskEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let task: CompanionMomentTaskSummary?

    @State private var selectedRoleID: UUID
    @State private var instruction: String
    @State private var scheduledAt: Date
    @State private var frequency: MomentTaskRecurrenceFrequency
    @State private var interval: Int
    @State private var weekday: Int
    @State private var monthDay: Int
    @State private var timezoneIdentifier: String
    @State private var errorText: String?
    @State private var isSaving = false

    init(task: CompanionMomentTaskSummary? = nil) {
        self.task = task
        let date = task?.scheduledAt ?? Date().addingTimeInterval(5 * 60)
        let storedTimezone = task?.timezoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let timezone = storedTimezone?.isEmpty == false
            ? storedTimezone!
            : TimeZone.current.identifier
        let scheduleCalendar = ScheduledTasksSupport.calendar(timeZoneIdentifier: timezone)
        let descriptor = task.map {
            ScheduledTasksSupport.recurrenceDescriptor(
                ScheduledTasksSupport.recurrenceRule(for: $0)
            )
        }
        _selectedRoleID = State(initialValue: task?.roleID ?? RoleScope.legacyRoleID)
        _instruction = State(initialValue: task?.instruction ?? "")
        _scheduledAt = State(initialValue: date)
        _frequency = State(
            initialValue: task.map {
                ScheduledTasksSupport.recurrenceRule(for: $0).frequency
            } ?? ScheduledTasksSupport.defaultFrequency()
        )
        _interval = State(initialValue: max(descriptor?.interval ?? 1, 1))
        _weekday = State(initialValue: descriptor?.weekday ?? scheduleCalendar.component(.weekday, from: date))
        _monthDay = State(initialValue: descriptor?.monthDay ?? scheduleCalendar.component(.day, from: date))
        _timezoneIdentifier = State(initialValue: timezone)
    }

    var body: some View {
        Form {
            roleSection
            contentSection
            scheduleSection
            if let errorText {
                Section {
                    StatusBanner(text: errorText, style: .error)
                }
            }
            Section {
                Text("任务会使用当前角色的连接生成文字动态；错过时间会在下次打开应用时补执行。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.rootBackground)
        .navigationTitle(task == nil ? "新建定时任务" : "编辑定时任务")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .accessibilityIdentifier("scheduled-tasks.editor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "保存中…" : "保存") { save() }
                    .disabled(!canSave || isSaving)
                    .accessibilityLabel(isSaving ? "保存中" : "保存定时任务")
                    .accessibilityIdentifier("scheduled-tasks.editor.save")
            }
        }
        .onAppear {
            if selectedRoleID == RoleScope.legacyRoleID,
               !availableCompanions.contains(where: { $0.id == selectedRoleID }),
               let first = availableCompanions.first {
                selectedRoleID = first.id
            }
        }
        .accessibilityIdentifier("scheduled-tasks.editor")
    }

    private var roleSection: some View {
        Section("发布角色") {
            if task != nil, isEditingRoleUnavailable {
                let role = task.flatMap { appModel.companionSummary(for: $0.roleID) }
                HStack(spacing: 12) {
                    CompanionAvatar(
                        size: 42,
                        name: role?.name ?? "已隐藏角色",
                        imageData: role?.avatarImageData
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role?.name ?? "已隐藏角色")
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.primaryText)
                        Text("此角色已隐藏或不可用，恢复后才能保存这条任务。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("任务角色不可用")
                .accessibilityValue(role?.name ?? "已隐藏角色")
                .accessibilityIdentifier("scheduled-tasks.editor.role-unavailable")
            } else if availableCompanions.isEmpty {
                ContentUnavailableView(
                    "暂无可用角色",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("先添加一个角色，才能创建朋友圈任务。")
                )
                .frame(minHeight: 110)
            } else {
                Picker("角色", selection: $selectedRoleID) {
                    ForEach(availableCompanions) { companion in
                        HStack(spacing: 8) {
                            CompanionAvatar(size: 26, name: companion.name, imageData: companion.avatarImageData)
                            Text(companion.name)
                        }
                        .tag(companion.id)
                    }
                }
                .accessibilityIdentifier("scheduled-tasks.editor.role")
            }
        }
    }

    private var contentSection: some View {
        Section("动态内容") {
            TextField("例如：傍晚分享今天的心情", text: $instruction, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityLabel("动态内容")
                .accessibilityIdentifier("scheduled-tasks.editor.instruction")
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        Section("时间规则") {
            Picker("频率", selection: $frequency) {
                ForEach(MomentTaskRecurrenceFrequency.allCases, id: \.self) { option in
                    Text(ScheduledTasksSupport.frequencyTitle(option)).tag(option)
                }
            }
            .accessibilityIdentifier("scheduled-tasks.editor.frequency")

            DatePicker(
                "开始日期与时间",
                selection: $scheduledAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("scheduled-tasks.editor.date")

            Picker("时区", selection: $timezoneIdentifier) {
                ForEach(timezoneOptions, id: \.self) { identifier in
                    Text(identifier).tag(identifier)
                }
            }
            .accessibilityIdentifier("scheduled-tasks.editor.timezone")

            if TimeZone(identifier: timezoneIdentifier) == nil {
                Text("原任务的时区标识不可用，请选择有效的 IANA 时区后再保存。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if !isOneTime {
                Stepper(value: $interval, in: 1...31) {
                    HStack {
                        Text("间隔")
                        Spacer()
                        Text(intervalTitle)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .accessibilityLabel("循环间隔")
                .accessibilityValue(intervalTitle)
                .accessibilityIdentifier("scheduled-tasks.editor.interval")

                if frequencyKey == "weekly" || frequencyKey == "week" {
                    Picker("星期", selection: $weekday) {
                        ForEach(1...7, id: \.self) { value in
                            Text(ScheduledTasksSupport.weekdayTitle(for: value)).tag(value)
                        }
                    }
                    .accessibilityIdentifier("scheduled-tasks.editor.weekday")
                }

                if frequencyKey == "monthly" || frequencyKey == "month" {
                    Picker("月日", selection: $monthDay) {
                        ForEach(1...31, id: \.self) { value in
                            Text("每月\(value)日").tag(value)
                        }
                    }
                    .accessibilityIdentifier("scheduled-tasks.editor.month-day")
                }
            }
        }
    }

    private var frequencyKey: String {
        ScheduledTasksSupport.normalizedFrequency(frequency)
    }

    private var isOneTime: Bool {
        ["once", "onetime", "oneoff", "single"].contains(frequencyKey)
    }

    private var intervalTitle: String {
        switch frequencyKey {
        case "hourly", "hour": return interval == 1 ? "每小时" : "每\(interval)小时"
        case "daily", "day": return interval == 1 ? "每天" : "每\(interval)天"
        case "weekly", "week": return interval == 1 ? "每周" : "每\(interval)周"
        case "monthly", "month": return interval == 1 ? "每月" : "每\(interval)个月"
        default: return "一次"
        }
    }

    private var canSave: Bool {
        !availableCompanions.isEmpty
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isEditingRoleUnavailable
            && availableCompanions.contains {
                RoleScope.resolve($0.id) == RoleScope.resolve(selectedRoleID)
            }
            && TimeZone(identifier: timezoneIdentifier) != nil
    }

    private var recurrence: MomentTaskRecurrenceRule {
        ScheduledTasksSupport.makeRule(
            frequency: frequency,
            interval: isOneTime ? 1 : interval,
            weekday: (frequencyKey == "weekly" || frequencyKey == "week") ? weekday : nil,
            monthDay: (frequencyKey == "monthly" || frequencyKey == "month") ? monthDay : nil,
            scheduledAt: scheduledAt,
            timezoneIdentifier: timezoneIdentifier,
            seriesID: task?.seriesID
        )
    }

    private var isEditingRoleUnavailable: Bool {
        guard let task else { return false }
        let roleID = RoleScope.resolve(task.roleID)
        return !availableCompanions.contains {
            RoleScope.resolve($0.id) == roleID
        }
    }

    private var availableCompanions: [CompanionProfileSummary] {
        appModel.companions.filter(ScheduledTasksSupport.isBirthdayAutomationEligible)
    }

    private var timezoneOptions: [String] {
        let preferred = [
            TimeZone.current.identifier,
            timezoneIdentifier,
            task?.timezoneIdentifier ?? "",
            "Asia/Shanghai",
            "Asia/Tokyo",
            "Europe/London",
            "America/Los_Angeles",
            "UTC"
        ]
        return Array(Set(preferred.filter { !$0.isEmpty } + TimeZone.knownTimeZoneIdentifiers)).sorted {
            if $0 == timezoneIdentifier { return true }
            if $1 == timezoneIdentifier { return false }
            if $0 == TimeZone.current.identifier { return true }
            if $1 == TimeZone.current.identifier { return false }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorText = nil
        do {
            try appModel.scheduleMoment(
                roleID: selectedRoleID,
                instruction: instruction,
                scheduledAt: scheduledAt,
                recurrence: recurrence,
                taskID: task?.id ?? UUID()
            )
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            errorText = error.localizedDescription
        }
    }
}

struct BirthdayManagementView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var userMonth = 0
    @State private var userDay = 0
    @State private var timeZoneIdentifier = TimeZone.current.identifier
    @State private var companionBirthdays: [UUID: BirthdayDraft] = [:]
    @State private var errorText: String?
    @State private var statusText: String?
    @State private var savingRoleID: UUID?

    var body: some View {
        Form {
            userBirthdaySection
            companionBirthdaySection

            Section {
                Text("只保存月和日，不记录出生年份。时区用于判断生日当天。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            if let errorText {
                Section { StatusBanner(text: errorText, style: .error) }
            } else if let statusText {
                Section { StatusBanner(text: statusText, style: .information) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.rootBackground)
        .navigationTitle("生日与日期")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
                    .accessibilityIdentifier("scheduled-tasks.birthday.done")
            }
        }
        .onAppear(perform: loadDraft)
        .accessibilityIdentifier("scheduled-tasks.birthday-management")
    }

    private var userBirthdaySection: some View {
        Section("我的生日") {
            BirthdayMonthDayPicker(
                month: $userMonth,
                day: $userDay,
                label: "生日月日"
            )
            Picker("时区", selection: $timeZoneIdentifier) {
                ForEach(timeZoneOptions, id: \.self) { identifier in
                    Text(identifier).tag(identifier)
                }
            }
            .accessibilityIdentifier("scheduled-tasks.birthday.user-timezone")

            HStack {
                Spacer()
                Button("保存我的生日") { saveUserBirthday() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("scheduled-tasks.birthday.user-save")
                Spacer()
            }
        }
    }

    private var companionBirthdaySection: some View {
        Section("角色生日") {
            if birthdayCompanions.isEmpty {
                ContentUnavailableView(
                    "还没有角色",
                    systemImage: "person.2",
                    description: Text("添加角色后，可以分别设置每个角色的生日。")
                )
                .frame(minHeight: 120)
            } else {
                ForEach(birthdayCompanions) { companion in
                    companionBirthdayRow(companion)
                }
            }
        }
    }

    private func companionBirthdayRow(_ companion: CompanionProfileSummary) -> some View {
        let draft = companionBirthdays[companion.id] ?? BirthdayDraft(
            month: companion.birthdayMonth ?? 0,
            day: companion.birthdayDay ?? 0
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CompanionAvatar(size: 40, name: companion.name, imageData: companion.avatarImageData)
                Text(companion.name)
                    .font(.body.weight(.medium))
                Spacer()
                if savingRoleID == companion.id {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            BirthdayMonthDayPicker(
                month: Binding(
                    get: { draft.month },
                    set: { updateCompanionDraft(companion.id, month: $0, day: draft.day) }
                ),
                day: Binding(
                    get: { draft.day },
                    set: { updateCompanionDraft(companion.id, month: draft.month, day: $0) }
                ),
                label: "\(companion.name)的生日月日"
            )
            HStack {
                Spacer()
                Button("保存") { saveCompanionBirthday(companion) }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)
                    .frame(minHeight: 44)
                    .disabled(savingRoleID != nil)
                    .accessibilityIdentifier("scheduled-tasks.birthday.companion-save.\(companion.id.uuidString)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scheduled-tasks.birthday.companion.\(companion.id.uuidString)")
    }

    private var timeZoneOptions: [String] {
        let preferred = [
            TimeZone.current.identifier,
            "Asia/Shanghai",
            "Asia/Tokyo",
            "Europe/London",
            "America/Los_Angeles",
            "UTC"
        ]
        return Array(Set(preferred + TimeZone.knownTimeZoneIdentifiers)).sorted {
            if $0 == TimeZone.current.identifier { return true }
            if $1 == TimeZone.current.identifier { return false }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func loadDraft() {
        userMonth = appModel.userProfile.birthdayMonth ?? 0
        userDay = appModel.userProfile.birthdayDay ?? 0
        timeZoneIdentifier = storedUserTimeZoneIdentifier
        companionBirthdays = Dictionary(uniqueKeysWithValues: birthdayCompanions.map { companion in
            (
                companion.id,
                BirthdayDraft(
                    month: companion.birthdayMonth ?? 0,
                    day: companion.birthdayDay ?? 0
                )
            )
        })
    }

    private var birthdayCompanions: [CompanionProfileSummary] {
        appModel.companions.filter(ScheduledTasksSupport.isBirthdayAutomationEligible)
    }

    private var storedUserTimeZoneIdentifier: String {
        let value = appModel.userProfile.birthdayTimeZoneIdentifier
        return TimeZone(identifier: value)?.identifier ?? TimeZone.current.identifier
    }

    private func saveUserBirthday() {
        errorText = nil
        do {
            try appModel.saveUserBirthday(
                month: userMonth == 0 ? nil : userMonth,
                day: userDay == 0 ? nil : userDay,
                timeZoneIdentifier: timeZoneIdentifier
            )
            statusText = "我的生日已保存。"
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveCompanionBirthday(_ companion: CompanionProfileSummary) {
        let draft = companionBirthdays[companion.id] ?? BirthdayDraft(month: 0, day: 0)
        savingRoleID = companion.id
        errorText = nil
        do {
            try appModel.saveCompanionBirthday(
                roleID: companion.id,
                month: draft.month == 0 ? nil : draft.month,
                day: draft.day == 0 ? nil : draft.day
            )
            statusText = "\(companion.name)的生日已保存。"
            savingRoleID = nil
        } catch {
            savingRoleID = nil
            errorText = error.localizedDescription
        }
    }

    private func updateCompanionDraft(_ roleID: UUID, month: Int, day: Int) {
        companionBirthdays[roleID] = BirthdayDraft(month: month, day: day)
    }
}

private struct BirthdayDraft: Equatable {
    var month: Int
    var day: Int
}

private struct BirthdayMonthDayPicker: View {
    @Binding var month: Int
    @Binding var day: Int
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Picker("月份", selection: $month) {
                Text("未设置").tag(0)
                ForEach(1...12, id: \.self) { value in
                    Text("\(value)月").tag(value)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("\(label)月份")

            Picker("日期", selection: $day) {
                Text("未设置").tag(0)
                ForEach(1...(month > 0 ? ScheduledTasksSupport.daysInMonth(month) : 31), id: \.self) { value in
                    Text("\(value)日").tag(value)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("\(label)日期")

            Spacer(minLength: 0)
            Button("清除") {
                month = 0
                day = 0
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(minHeight: 44)
            .accessibilityLabel("清除\(label)")
            .accessibilityIdentifier("scheduled-tasks.birthday.clear.\(label)")
        }
        .onChange(of: month) { _, newMonth in
            if newMonth > 0 {
                let maximumDay = ScheduledTasksSupport.daysInMonth(newMonth)
                if day > maximumDay { day = maximumDay }
            }
            if month == 0 { day = 0 }
        }
        .accessibilityElement(children: .contain)
    }
}

struct ScheduledTaskHistoryView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 0) {
            ScheduledTasksHeader(title: "执行记录")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if history.isEmpty {
                        ContentUnavailableView(
                            "还没有执行记录",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("已发布或取消的定时任务会显示在这里。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 100)
                    } else {
                        ForEach(history) { task in
                            historyRow(task)
                            if task.id != history.last?.id {
                                Rectangle()
                                    .fill(AppTheme.divider)
                                    .frame(height: 0.5)
                                    .padding(.leading, 76)
                            }
                        }
                    }
                }
                .background(AppTheme.secondarySurface)
            }
            .scrollIndicators(.hidden)
            .background(AppTheme.rootBackground)
        }
        .background(AppTheme.rootBackground.ignoresSafeArea())
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .restoresWeChatEdgeBackGesture()
        .wechatEdgeBackFallback()
        #else
        .navigationTitle("执行记录")
        #endif
        .onAppear {
            appModel.refreshFromStore()
        }
        .accessibilityIdentifier("scheduled-tasks.history")
    }

    private var history: [CompanionMomentTaskSummary] {
        appModel.momentTasks
            .filter { $0.state == .published || $0.state == .cancelled }
            .sorted {
                let lhs = $0.publishedAt ?? $0.scheduledAt
                let rhs = $1.publishedAt ?? $1.scheduledAt
                if lhs != rhs { return lhs > rhs }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private func historyRow(_ task: CompanionMomentTaskSummary) -> some View {
        let role = ScheduledTasksSupport.roleAvatar(task.roleID, in: appModel.companions)
        return HStack(spacing: 12) {
            CompanionAvatar(size: 56, name: role.name, imageData: role.imageData)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(role.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(task.state.title)
                        .font(.system(size: 13))
                        .foregroundStyle(task.state == .published ? AppTheme.accent : AppTheme.secondaryText)
                }
                Text(task.resultText.isEmpty ? task.instruction : task.resultText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(3)
                Text((task.publishedAt ?? task.scheduledAt).formatted(.dateTime.year().month().day().hour().minute()))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role.name)，\(task.state.title)")
        .accessibilityValue(task.resultText.isEmpty ? task.instruction : task.resultText)
        .accessibilityIdentifier("scheduled-tasks.history.row.\(task.id.uuidString)")
    }
}
