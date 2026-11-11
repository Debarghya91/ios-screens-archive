// NotesStore.swift
// PaymentForge iOS - Learner notes and collections, stored locally.
// Stored locally with UserDefaults, guest by default, no sign-in.
// Notes are the learner's own text about real lessons; nothing is
// invented by the app. Default collections are "My UPI Notes" and
// "Interview Preparation"; the learner can add more.
// No em dashes in any user-facing text.

import Foundation
import Combine

/// Local notes about lessons, grouped into collections.
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    struct Note: Identifiable, Codable {
        let id: UUID
        let lessonID: String
        let lessonTitle: String
        let text: String
        let highlightedText: String?
        let createdAt: Date
        var collection: String
    }

    private enum Keys {
        static let notes = "pf.notes.v1"
        static let customCollections = "pf.noteCollections.v1"
    }

    static let defaultCollections: [String] = ["My UPI Notes", "Interview Preparation"]

    @Published private(set) var notes: [Note] = [] {
        didSet { saveNotes() }
    }

    @Published private(set) var customCollections: [String] = [] {
        didSet { saveCollections() }
    }

    init() {
        load()
    }

    func addNote(lessonID: String, lessonTitle: String, text: String, highlightedText: String?, collection: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let chosen = collection.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCollection = chosen.isEmpty ? Self.defaultCollections[0] : chosen
        if !collections().contains(finalCollection) {
            customCollections.append(finalCollection)
        }
        let note = Note(
            id: UUID(),
            lessonID: lessonID,
            lessonTitle: lessonTitle,
            text: trimmed,
            highlightedText: highlightedText,
            createdAt: Date(),
            collection: finalCollection
        )
        notes.insert(note, at: 0)
    }

    func notes(for lessonID: String) -> [Note] {
        notes.filter { $0.lessonID == lessonID }
    }

    func allNotes() -> [Note] {
        notes.sorted { $0.createdAt > $1.createdAt }
    }

    func collections() -> [String] {
        Self.defaultCollections + customCollections
    }

    /// Add a user-created collection. Returns false when the name is
    /// empty or already exists.
    @discardableResult
    func createCollection(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !collections().contains(trimmed) else { return false }
        customCollections.append(trimmed)
        return true
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
    }

    /// Search notes by text, lesson title or collection.
    func searchNotes(query: String) -> [Note] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return allNotes() }
        return allNotes().filter {
            $0.text.lowercased().contains(needle)
            || $0.lessonTitle.lowercased().contains(needle)
            || $0.collection.lowercased().contains(needle)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Keys.notes),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
        }
        customCollections = UserDefaults.standard.stringArray(forKey: Keys.customCollections) ?? []
    }

    private func saveNotes() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: Keys.notes)
        }
    }

    private func saveCollections() {
        UserDefaults.standard.set(customCollections, forKey: Keys.customCollections)
    }
}
