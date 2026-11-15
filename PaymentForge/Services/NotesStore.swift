// NotesStore.swift
// Payments Training Hub iOS - Learner notes, stored locally as one flat list.
// Stored locally with UserDefaults, namespaced per account through
// AccountScopedStorage. Notes are never synced to any server: they
// stay on this device, under the namespace that owns them.
// Notes are the learner's own text about real lessons; nothing is
// invented by the app. There are no collections: every note lives
// in one list, newest first. Notes stored by earlier builds under
// a grouping are kept: the stored grouping value is ignored on
// load, so notes from every old grouping land in the flat list
// with their text, lesson link, quoted text and date intact.
// No em dashes in any user-facing text.

import Foundation
import Combine

/// Local notes about lessons, kept as one flat list.
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    struct Note: Identifiable, Codable {
        let id: UUID
        let lessonID: String
        let lessonTitle: String
        let text: String
        let highlightedText: String?
        let createdAt: Date

        /// Only these keys are read. Stored notes from earlier builds
        /// carry one extra key for the old grouping; decoding ignores
        /// unknown keys, so those notes load unchanged into the flat
        /// list instead of being dropped.
        enum CodingKeys: String, CodingKey {
            case id, lessonID, lessonTitle, text, highlightedText, createdAt
        }
    }

    private enum Keys {
        static let notes = "pf.notes.v1"
        /// Old grouping names, kept only so load can delete the
        /// obsolete key. The names are never read back.
        static let legacyCustomCollections = "pf.noteCollections.v1"
    }

    @Published private(set) var notes: [Note] = [] {
        didSet { saveNotes() }
    }

    /// Suppresses saveNotes() while reloading, so clearing the
    /// previous account's notes from memory does not write an empty
    /// list into the new namespace (which would block guest
    /// migration for it).
    private var suppressSave = false

    private func withoutSaving(_ work: () -> Void) {
        let previous = suppressSave
        suppressSave = true
        defer { suppressSave = previous }
        work()
    }

    init() {
        load()
    }

    /// Reload for the current account namespace, clearing the
    /// previous account's notes from memory first.
    func reloadForCurrentAccount() {
        withoutSaving { notes = [] }
        load()
    }

    func addNote(lessonID: String, lessonTitle: String, text: String, highlightedText: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = Note(
            id: UUID(),
            lessonID: lessonID,
            lessonTitle: lessonTitle,
            text: trimmed,
            highlightedText: highlightedText,
            createdAt: Date()
        )
        notes.insert(note, at: 0)
    }

    func notes(for lessonID: String) -> [Note] {
        notes.filter { $0.lessonID == lessonID }
    }

    func allNotes() -> [Note] {
        notes.sorted { $0.createdAt > $1.createdAt }
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
    }

    /// Search notes by text or lesson title.
    func searchNotes(query: String) -> [Note] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return allNotes() }
        return allNotes().filter {
            $0.text.lowercased().contains(needle)
            || $0.lessonTitle.lowercased().contains(needle)
        }
    }

    private func load() {
        AccountScopedStorage.adoptLegacyKey(Keys.notes)
        if let data = UserDefaults.standard.data(forKey: AccountScopedStorage.currentKey(Keys.notes)) {
            if let decoded = try? JSONDecoder().decode([Note].self, from: data) {
                notes = decoded
                // Property observers do not fire during init, so
                // persist the flattened form explicitly. This drops
                // the obsolete grouping key from stored notes.
                saveNotes()
            } else if let recovered = recoverNotes(from: data), !recovered.isEmpty {
                notes = recovered
                saveNotes()
            }
            // If nothing decoded, the stored data is left untouched
            // so a later build can still recover it. No note is
            // overwritten with an empty list.
        }
        // The obsolete grouping key was never namespaced and is
        // never read; removing the raw key once is the whole cleanup.
        UserDefaults.standard.removeObject(forKey: Keys.legacyCustomCollections)
    }

    /// Recover notes one by one when the stored array does not decode
    /// as a whole, so one damaged entry cannot lose every note.
    /// Each entry is tried strictly first, then leniently: a note
    /// with readable text is kept even when its id or date is
    /// missing or damaged.
    private func recoverNotes(from data: Data) -> [Note]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let items = raw as? [[String: Any]] else { return nil }
        var recovered: [Note] = []
        let decoder = JSONDecoder()
        for item in items {
            if let itemData = try? JSONSerialization.data(withJSONObject: item),
               let note = try? decoder.decode(Note.self, from: itemData) {
                recovered.append(note)
                continue
            }
            if let note = lenientNote(from: item) {
                recovered.append(note)
            }
        }
        return recovered
    }

    private func lenientNote(from dict: [String: Any]) -> Note? {
        guard let text = dict["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let id: UUID
        if let idString = dict["id"] as? String, let parsed = UUID(uuidString: idString) {
            id = parsed
        } else {
            id = UUID()
        }
        return Note(
            id: id,
            lessonID: dict["lessonID"] as? String ?? "",
            lessonTitle: dict["lessonTitle"] as? String ?? "",
            text: text,
            highlightedText: dict["highlightedText"] as? String,
            createdAt: recoveredDate(from: dict["createdAt"]) ?? Date()
        )
    }

    /// Dates are stored as seconds since the reference date by the
    /// default JSON encoder; ISO8601 text is accepted as a fallback.
    private func recoveredDate(from value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSinceReferenceDate: number.doubleValue)
        }
        if let text = value as? String,
           let parsed = ISO8601DateFormatter().date(from: text) {
            return parsed
        }
        return nil
    }

    private func saveNotes() {
        guard !suppressSave else { return }
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: AccountScopedStorage.currentKey(Keys.notes))
        }
    }
}
