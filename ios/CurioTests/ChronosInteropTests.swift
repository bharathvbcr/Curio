import Foundation
import Testing
@testable import Curio

/// Unit tests for the Curio side of the ChronosFlow handoff: the reminder-time presets and the
/// mirrored contract literals (which MUST stay byte-for-byte equal to ChronosFlow's reader, or
/// handoffs silently no-op).
///
/// Port of `app/src/test/java/com/example/interop/ChronosInteropTest.kt` (JUnit + Robolectric —
/// Robolectric only supplied `android.net.Uri` there; nothing platform-bound remains on iOS).
///
/// Mapping notes:
/// - Kotlin `toEpochMillis(now: Long, zone: ZoneId)` is `toEpochMillis(now: Date, calendar:
///   Calendar)` on iOS; the Kotlin `ZoneOffset.UTC` becomes a fixed-UTC Gregorian `Calendar`.
/// - Enum case names follow Swift style (`NONE` → `.none`, `IN_ONE_HOUR` → `.inOneHour`,
///   `TONIGHT` → `.tonight`, `TOMORROW` → `.tomorrow`); the semantics are identical.
/// - The contract-literal test is adapted to the platform substitution documented on
///   `ChronosInteropContract`: iOS has no ContentProvider, so the Android `CHRONOSFLOW_PACKAGE` /
///   `PROVIDER_AUTHORITY` / `PATH_HANDOFF` / `HANDOFF_URI` literals have no counterpart. What IS
///   pinned instead: the App-Group / queue-file / peer / URL-scheme literals (the iOS trust +
///   rendezvous surface), the byte-identical `KIND_*` values, and the wire keys of
///   `ChronosHandoffEntry` — whose JSON field names deliberately reuse the Android `HANDOFF_*`
///   column names (`kind`/`url`/`title`/`text`/`notes`/`reminder_at_epoch_ms`).
@Suite("ChronosInterop (mirrors ChronosInteropTest.kt)")
struct ChronosInteropTests {

    /// Kotlin `ZoneOffset.UTC` → fixed-UTC Gregorian calendar (never the machine-local zone, so the
    /// wall-clock assertions are deterministic on any CI box).
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Kotlin `Instant.parse(iso)` → `Date`.
    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// Kotlin `ms(iso)`: `Instant.parse(iso).toEpochMilli()`.
    private func ms(_ iso: String) -> Int64 {
        Int64(date(iso).timeIntervalSince1970 * 1000)
    }

    /// Kotlin: `NONE has no reminder time`.
    @Test("NONE has no reminder time")
    func noneHasNoReminderTime() {
        #expect(ChronosReminderChoice.none.toEpochMillis() == nil)
    }

    /// Kotlin: `IN_ONE_HOUR is exactly one hour from now`.
    @Test("IN_ONE_HOUR is exactly one hour from now")
    func inOneHourIsExactlyOneHourFromNow() {
        let now = date("2026-06-22T18:00:00Z")
        #expect(
            ChronosReminderChoice.inOneHour.toEpochMillis(now: now, calendar: utc)
                == ms("2026-06-22T18:00:00Z") + 3_600_000
        )
    }

    /// Kotlin: `TONIGHT is 8pm today when it has not yet passed`.
    @Test("TONIGHT is 8pm today when it has not yet passed")
    func tonightIs8pmTodayWhenNotYetPassed() {
        let now = date("2026-06-22T18:00:00Z")
        #expect(
            ChronosReminderChoice.tonight.toEpochMillis(now: now, calendar: utc)
                == ms("2026-06-22T20:00:00Z")
        )
    }

    /// Kotlin: `TONIGHT rolls to tomorrow when 8pm already passed`.
    @Test("TONIGHT rolls to tomorrow when 8pm already passed")
    func tonightRollsToTomorrowWhen8pmPassed() {
        let now = date("2026-06-22T21:00:00Z")
        #expect(
            ChronosReminderChoice.tonight.toEpochMillis(now: now, calendar: utc)
                == ms("2026-06-23T20:00:00Z")
        )
    }

    /// Kotlin: `TOMORROW is 9am the next day`.
    @Test("TOMORROW is 9am the next day")
    func tomorrowIs9amTheNextDay() {
        let now = date("2026-06-22T18:00:00Z")
        #expect(
            ChronosReminderChoice.tomorrow.toEpochMillis(now: now, calendar: utc)
                == ms("2026-06-23T09:00:00Z")
        )
    }

    /// Kotlin: `every concrete reminder time is in the future` (23:30 so `.inOneHour` and
    /// `.tonight` both cross midnight). Kotlin `values()` → `allCases`.
    @Test("every concrete reminder time is in the future")
    func everyConcreteReminderTimeIsInTheFuture() {
        let now = date("2026-06-22T23:30:00Z")
        let nowMs = ms("2026-06-22T23:30:00Z")
        for reminder in ChronosReminderChoice.allCases.compactMap({ $0.toEpochMillis(now: now, calendar: utc) }) {
            #expect(reminder > nowMs, "reminder must be in the future")
        }
    }

    /// Guards the cross-app contract (Kotlin: `handoff contract literals match the ChronosFlow
    /// provider schema`, adapted to the iOS rendezvous surface — see the suite doc comment). These
    /// literals are mirrored (not shared) with ChronosFlow's reader; if either side changes a
    /// string, handoffs stop matching and silently no-op — so pin the exact values here.
    @Test("handoff contract literals match the ChronosFlow reader")
    func handoffContractLiteralsMatchTheChronosFlowReader() {
        #expect(ChronosInteropContract.chronosFlowScheme == "chronosflow")
        #expect(ChronosInteropContract.appGroup == "group.com.chronosflow.shared")
        #expect(ChronosInteropContract.handoffFileName == "curio-handoff.json")
        #expect(ChronosInteropContract.curioPeer == "com.curio.app")
        // KIND_* — byte-identical to the Android contract.
        #expect(ChronosInteropContract.kindReading == "reading")
        #expect(ChronosInteropContract.kindInbox == "inbox")
        #expect(ChronosInteropContract.kindTask == "task")
        // The payload envelope self-identifies with the pinned peer id by default.
        #expect(ChronosHandoffPayload(handoffs: []).peer == "com.curio.app")
    }

    /// Pins the wire keys of one handoff row — the iOS analogue of the Android `HANDOFF_*` column
    /// literals (`kind`/`url`/`title`/`text`/`notes`/`reminder_at_epoch_ms` are the SAME strings the
    /// Kotlin test asserted, carried here as `CodingKeys`; `id`/`created_at_epoch_ms` are the iOS
    /// dedup additions).
    @Test("handoff wire keys match the Android handoff column names")
    func handoffWireKeysMatchTheAndroidHandoffColumnNames() throws {
        let entry = ChronosHandoffEntry(
            id: "e1",
            kind: ChronosInteropContract.kindReading,
            createdAtEpochMillis: 1,
            url: "https://example.com/paper",
            title: "title",
            text: "text",
            notes: "notes",
            reminderAtEpochMillis: 2
        )
        let data = try JSONEncoder().encode(entry)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(
            Set(object.keys) == Set([
                "id", "kind", "created_at_epoch_ms",
                "url", "title", "text", "notes", "reminder_at_epoch_ms"
            ])
        )
        #expect(object["kind"] as? String == "reading")
        #expect((object["reminder_at_epoch_ms"] as? NSNumber)?.int64Value == 2)
        #expect((object["created_at_epoch_ms"] as? NSNumber)?.int64Value == 1)
    }
}
