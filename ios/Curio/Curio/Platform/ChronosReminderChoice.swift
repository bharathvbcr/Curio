import Foundation

/// Preset "remind me to read later" times offered when handing a bookmark to ChronosFlow. Port of
/// `interop/ChronosReminderChoice.kt`. The app has no time picker; these cover the common cases.
/// Each maps to an absolute epoch-millis instant that ChronosFlow schedules a reminder for.
enum ChronosReminderChoice: CaseIterable, Sendable {
    case none
    case inOneHour
    case tonight
    case tomorrow

    /// User-facing label (EXACT Android strings — CONVENTIONS §4).
    var label: String {
        switch self {
        case .none: return "No reminder"
        case .inOneHour: return "In 1 hour"
        case .tonight: return "Tonight, 8 PM"
        case .tomorrow: return "Tomorrow, 9 AM"
        }
    }

    /// The reminder instant in epoch millis, or `nil` for `.none`. `.tonight` and `.tomorrow`
    /// always resolve to a future time (rolling forward a day if the wall-clock target has already
    /// passed). Calendar-based day arithmetic (not raw +24h) so DST transitions don't shift the
    /// time — the Swift analogue of Kotlin `LocalDate.plusDays(1).atTime(...)`.
    func toEpochMillis(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int64? {
        switch self {
        case .none:
            return nil
        case .inOneHour:
            return Int64(now.timeIntervalSince1970 * 1000) + Self.oneHourMs
        case .tonight:
            return Self.millis(nextOccurrenceOf: DateComponents(hour: 20, minute: 0), after: now, calendar: calendar)
        case .tomorrow:
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            let at9 = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: startOfTomorrow)!
            return Int64(at9.timeIntervalSince1970 * 1000)
        }
    }

    /// The next wall-clock occurrence of `time` strictly after `now` (today if still ahead, else
    /// the same time tomorrow). Port of `nextOccurrenceOf`.
    private static func millis(nextOccurrenceOf time: DateComponents, after now: Date, calendar: Calendar) -> Int64 {
        let todayTarget = calendar.date(
            bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: now
        )!
        let target: Date
        if todayTarget > now {
            target = todayTarget
        } else {
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            target = calendar.date(
                bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: startOfTomorrow
            )!
        }
        return Int64(target.timeIntervalSince1970 * 1000)
    }

    private static let oneHourMs: Int64 = 60 * 60 * 1000
}
