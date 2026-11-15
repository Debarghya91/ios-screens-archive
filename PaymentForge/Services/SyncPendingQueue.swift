// SyncPendingQueue.swift
// PaymentForge iOS - Durable record of local changes still waiting to
// sync to the signed-in account.
//
// The local stores (ProgressStore, PracticeStore, PFBookmarkStore and
// the learning preferences) are the durable record of a learner's
// progress. This queue records only THAT a sync is owed, plus the
// kinds of change and the identifiers involved (for example lesson
// IDs completed or quiz attempt identities), so a temporary network
// failure or an app restart cannot lose the "sync needed" signal.
// A sync run re-reads the local stores; it never trusts this queue
// as the source of the data itself.
//
// Persistence: one JSON array in UserDefaults under an account-scoped
// key resolved through AccountScopedStorage.currentKey, so one
// account's pending state is never read as another account's. The
// queue is safe to use from any thread: every access is serialised
// with a lock, and noteLocalChange() records here before hopping to
// the main actor.
//
// Removal rules: a table's entry is removed only when that table's
// sync step succeeds, and only when the entry was recorded before
// the sync run started, so a change made mid-run is never dropped.
// A corrupt stored payload degrades to one general pending entry,
// which forces a full re-read of the local stores on the next sync;
// nothing is lost, because the stores hold the data.
// No em dashes in any user-facing text.

import Foundation

/// The kinds of local change that can wait for a sync. The raw values
/// are persisted, so never rename an existing case.
enum SyncChangeKind: String, Codable, CaseIterable {
    /// A change with no recorded kind. Recorded by the plain
    /// noteLocalChange() call; cleared only by a fully successful
    /// sync run or by clearPendingOperations().
    case general
    /// Lesson completions (user_progress).
    case progress
    /// Quiz attempts (quiz_attempts).
    case quizAttempts
    /// Lesson bookmarks (lesson_bookmarks).
    case bookmarks
    /// Daily learning activity (learning_activity).
    case learningActivity
    /// Learning preferences (user_preferences).
    case preferences
    /// Learning path enrolments (user_learning_paths).
    case learningPaths
    /// Practice attempts (practice_attempts, owned by PracticeStore).
    case practiceAttempts
    /// Path certificate backfill.
    case certificates
}

/// One pending entry: a change kind, the identifiers involved (empty
/// when only the kind is known), and when it was first and last
/// recorded. Identifiers are informational: the sync itself re-reads
/// the local stores, so an identifier list is never the data source.
struct SyncPendingChange: Codable, Equatable {
    var kind: SyncChangeKind
    var identifiers: [String]
    var firstRecordedAt: Date
    var lastRecordedAt: Date
}

/// Thread-safe durable store for pending sync work. All state lives
/// in UserDefaults under one account-scoped key.
final class SyncPendingQueue {
    static let shared = SyncPendingQueue()

    private let baseKey = "pf.syncPendingQueue.v1"
    private let lock = NSLock()

    private init() {}

    private var storageKey: String {
        AccountScopedStorage.currentKey(baseKey)
    }

    // MARK: - Recording

    /// Record a pending change, merging identifiers into the existing
    /// entry for the kind when there is one. Safe from any thread.
    func record(kind: SyncChangeKind, identifiers: [String] = []) {
        lock.lock()
        defer { lock.unlock() }
        var changes = loadLocked()
        let now = Date()
        if let index = changes.firstIndex(where: { $0.kind == kind }) {
            var merged = Set(changes[index].identifiers)
            merged.formUnion(identifiers)
            changes[index].identifiers = merged.sorted()
            changes[index].lastRecordedAt = now
        } else {
            changes.append(SyncPendingChange(
                kind: kind,
                identifiers: Array(Set(identifiers)).sorted(),
                firstRecordedAt: now,
                lastRecordedAt: now
            ))
        }
        saveLocked(changes)
    }

    // MARK: - Reading

    /// True when any pending change is recorded.
    var hasPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !loadLocked().isEmpty
    }

    /// A snapshot of every pending entry, sorted by kind.
    var snapshot: [SyncPendingChange] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked().sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    /// The kinds with pending work.
    var pendingKinds: Set<SyncChangeKind> {
        lock.lock()
        defer { lock.unlock() }
        return Set(loadLocked().map { $0.kind })
    }

    // MARK: - Removal

    /// Remove every pending entry for a kind, whatever its age.
    /// Prefer the date-bounded variant from sync runs, so a change
    /// recorded mid-run is not dropped.
    func remove(kind: SyncChangeKind) {
        lock.lock()
        defer { lock.unlock() }
        var changes = loadLocked()
        changes.removeAll { $0.kind == kind }
        saveLocked(changes)
    }

    /// Remove the entry for a kind, but only when it was last recorded
    /// on or before the given date (the start of the sync run that
    /// just synced that table). An entry touched after the run started
    /// means a newer local change arrived mid-run, and it stays.
    func remove(kind: SyncChangeKind, onlyIfLastRecordedOnOrBefore date: Date) {
        lock.lock()
        defer { lock.unlock() }
        var changes = loadLocked()
        changes.removeAll { $0.kind == kind && $0.lastRecordedAt <= date }
        saveLocked(changes)
    }

    /// Remove specific identifiers from a kind's entry. When the entry
    /// carried identifiers and every one of them is removed, the entry
    /// itself is dropped. A kind-only entry (no identifiers) is left
    /// alone: it still means "this kind needs a sync", and only a
    /// successful table sync clears it.
    func remove(kind: SyncChangeKind, identifiers: [String]) {
        lock.lock()
        defer { lock.unlock() }
        var changes = loadLocked()
        guard let index = changes.firstIndex(where: { $0.kind == kind }) else { return }
        guard !changes[index].identifiers.isEmpty else { return }
        let remaining = Set(changes[index].identifiers).subtracting(identifiers)
        if remaining.isEmpty {
            changes.remove(at: index)
        } else {
            changes[index].identifiers = remaining.sorted()
        }
        saveLocked(changes)
    }

    /// Remove every entry recorded on or before the given date (the
    /// start of a fully successful sync run). Entries recorded after
    /// the run started stay pending for the next run.
    func removeAll(onlyIfLastRecordedOnOrBefore date: Date) {
        lock.lock()
        defer { lock.unlock() }
        let changes = loadLocked().filter { $0.lastRecordedAt > date }
        saveLocked(changes)
    }

    /// Drop the whole queue, whatever its age. Used by
    /// SyncService.clearPendingOperations() for account deletion.
    /// This drops only the "sync needed" record, never local progress.
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Storage (call with the lock held)

    private func loadLocked() -> [SyncPendingChange] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([SyncPendingChange].self, from: data)
        } catch {
            // Our own payload is unreadable. Degrade to one general
            // pending entry so the next sync re-reads the local
            // stores in full; the stores hold the data, so nothing
            // is lost by discarding the unreadable queue record.
            NSLog("%@", "[SyncPendingQueue] Stored pending queue could not be decoded; treating it as one general pending change. Error: \(String(describing: error))")
            let now = Date()
            return [SyncPendingChange(
                kind: .general,
                identifiers: [],
                firstRecordedAt: now,
                lastRecordedAt: now
            )]
        }
    }

    private func saveLocked(_ changes: [SyncPendingChange]) {
        let sorted = changes.sorted { $0.kind.rawValue < $1.kind.rawValue }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
