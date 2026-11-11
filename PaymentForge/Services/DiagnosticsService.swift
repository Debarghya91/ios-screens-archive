// DiagnosticsService.swift
// PaymentForge iOS - Phase 7: lightweight, privacy-conscious crash
// diagnostics and anonymous analytics. Local only: nothing is ever
// sent anywhere, there is no third-party SDK, and there is no network
// call in this file. Diagnostics (uncaught errors and failed network
// calls) are recorded on error only, with a timestamp and a
// non-identifying context (screen or operation name). They NEVER
// contain personal data: no email, no user ID, no payment details,
// no question text, no tokens. Any string passed in is scrubbed for
// email-like text and bearer tokens before it is stored. Analytics
// are anonymous counts only (for example lessons completed, practice
// attempts), with no user identifier, and are OFF by default: the
// learner must opt in before any count is recorded.
// No em dashes in any user-facing text.

import Foundation

/// One recorded diagnostic event: when it happened, what kind of
/// failure it was, and where. The detail is a short generic note
/// ("failed after 3 attempts"), never a payload, message or identifier.
struct DiagnosticsEvent: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, Equatable {
        case error
        case networkFailure
    }

    let id: UUID
    let timestamp: Date
    let kind: Kind
    let operation: String
    let detail: String

    init(id: UUID = UUID(), timestamp: Date = Date(), kind: Kind, operation: String, detail: String) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.operation = operation
        self.detail = detail
    }
}

/// Local-only diagnostics and anonymous analytics. Nothing leaves
/// the device. Use DiagnosticsService.shared from anywhere; the
/// service is safe to call from any thread.
final class DiagnosticsService {
    static let shared = DiagnosticsService()

    private enum Keys {
        static let events = "pf.diagnostics.events.v1"
        static let analyticsCounts = "pf.analytics.counts.v1"
        static let analyticsEnabled = "pf.analytics.enabled.v1"
    }

    /// The most diagnostic events kept on device. Oldest drop first.
    static let maxStoredEvents = 100

    /// Analytics are off by default. Counts are recorded only while
    /// this is true; diagnostics (errors) are recorded regardless,
    /// because they are local-only and contain no personal data.
    var isAnalyticsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.analyticsEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.analyticsEnabled) }
    }

    private let lock = NSLock()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Diagnostics (error only, always local)

    /// Record an uncaught error or failed operation. The operation
    /// is a short code name such as "supabase.request" or
    /// "lesson.load"; the detail is a generic note, never a payload.
    func recordError(operation: String, detail: String = "") {
        record(kind: .error, operation: operation, detail: detail)
    }

    /// Record a failed network call after retries are exhausted.
    /// The operation names the call ("supabase.request",
    /// "content.searchIndex"); the detail says only that it failed
    /// and after how many attempts.
    func recordNetworkFailure(operation: String, detail: String = "") {
        record(kind: .networkFailure, operation: operation, detail: detail)
    }

    private func record(kind: DiagnosticsEvent.Kind, operation: String, detail: String) {
        let event = DiagnosticsEvent(
            kind: kind,
            operation: Self.sanitize(operation),
            detail: Self.sanitize(detail)
        )
        lock.lock()
        defer { lock.unlock() }
        var events = storedEventsLocked()
        events.append(event)
        if events.count > Self.maxStoredEvents {
            events.removeFirst(events.count - Self.maxStoredEvents)
        }
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: Keys.events)
        }
    }

    /// All stored diagnostic events, oldest first.
    var events: [DiagnosticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEventsLocked()
    }

    /// The number of stored diagnostic events.
    var eventCount: Int { events.count }

    // MARK: - Anonymous analytics (counts only, opt-in)

    /// Increment one anonymous counter, for example
    /// "lessons_completed" or "practice_attempts". No-op while
    /// analytics are off. The counter name is the only thing stored:
    /// no timestamp, no lesson or question text, no user identifier.
    func recordAnonymousCount(_ name: String) {
        guard isAnalyticsEnabled else { return }
        let key = Self.sanitize(name)
        guard !key.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var counts = storedCountsLocked()
        counts[key, default: 0] += 1
        defaults.set(counts, forKey: Keys.analyticsCounts)
    }

    /// All anonymous counters recorded so far.
    var anonymousCounts: [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return storedCountsLocked()
    }

    // MARK: - Export and clearing

    /// A plain-text export of diagnostics and anonymous counts, for
    /// debugging. Contains only timestamps, operation names and
    /// counts: no personal data, by construction and by scrubbing.
    /// The user chooses whether to share it; the app never sends it.
    func exportDiagnostics() -> String {
        var lines: [String] = []
        lines.append("Payments Training Hub diagnostics export")
        lines.append("Exported: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Events stored: \(eventCount) (max \(Self.maxStoredEvents))")
        lines.append("Analytics enabled: \(isAnalyticsEnabled ? "yes" : "no")")
        lines.append("")
        if anonymousCounts.isEmpty {
            lines.append("Anonymous counts: none recorded")
        } else {
            lines.append("Anonymous counts:")
            for key in anonymousCounts.keys.sorted() {
                lines.append("- \(key): \(anonymousCounts[key] ?? 0)")
            }
        }
        lines.append("")
        if events.isEmpty {
            lines.append("Diagnostic events: none recorded")
        } else {
            lines.append("Diagnostic events:")
            let formatter = ISO8601DateFormatter()
            for event in events {
                lines.append("- \(formatter.string(from: event.timestamp)) [\(event.kind.rawValue)] \(event.operation): \(event.detail)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Clear all stored diagnostics and anonymous counts.
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Keys.events)
        defaults.removeObject(forKey: Keys.analyticsCounts)
    }

    // MARK: - Scrubbing (never store personal data)

    /// Strip anything that could identify a person from a string
    /// before it is stored: email addresses, bearer tokens and
    /// long token-like runs. Operation names and generic notes pass
    /// through unchanged.
    static func sanitize(_ value: String) -> String {
        var result = value
        let patterns = [
            "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
            "(?i)bearer\\s+[A-Za-z0-9._\\-]+",
            "[A-Za-z0-9_\\-]{40,}"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[redacted]")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private storage (called with the lock held)

    private func storedEventsLocked() -> [DiagnosticsEvent] {
        guard let data = defaults.data(forKey: Keys.events),
              let decoded = try? JSONDecoder().decode([DiagnosticsEvent].self, from: data) else {
            return []
        }
        return decoded
    }

    private func storedCountsLocked() -> [String: Int] {
        (defaults.dictionary(forKey: Keys.analyticsCounts) as? [String: Int]) ?? [:]
    }
}
