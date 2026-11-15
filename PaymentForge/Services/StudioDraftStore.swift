// StudioDraftStore.swift
// Payments Training Hub iOS - BA and PO Studio draft storage.
//
// Drafts live in UserDefaults, namespaced per account through
// AccountScopedStorage, mirroring PracticeStore: the studio works
// fully for guests and offline, and one account's drafts are never
// served to another. Drafts are device-only: there is no server
// table for studio drafts, so nothing here is mirrored to any
// server, and no sync is flagged. The UI labels drafts device-only
// with the copy "Your drafts stay on this device."
//
// The store is keyed by one string id per draft. Practice
// exercise drafts use the exercise id, and teaching lesson
// write-your-own drafts use the lesson id (StudioLesson.id); the
// stored field keeps its historical name, exerciseID, so existing
// drafts stay readable. Both kinds share this store, its
// namespacing, and its device-only rule. No behaviour changed in
// the teaching rebuild: the lesson workspace calls the same
// save, read, AI-review flag, and delete methods as the exercise
// workspace.
// No em dashes in any user-facing text.

import Foundation
import Combine

/// Stores studio drafts locally, one draft per exercise, under the
/// current account namespace.
@MainActor
final class StudioDraftStore: ObservableObject {
    static let shared = StudioDraftStore()

    private enum Keys {
        static let drafts = "pf.studioDrafts.v1"
    }

    /// All drafts on this device for the current account, newest
    /// updated first.
    @Published private(set) var drafts: [StudioDraft] = []

    init() {
        load()
    }

    /// Reload for the current account namespace, clearing the
    /// previous account's drafts from memory first. Guest drafts
    /// reach an account only through the guest-to-account migration
    /// offer, which copies the namespaced key; this reload then
    /// loads them.
    func reloadForCurrentAccount() {
        drafts = []
        load()
    }

    // MARK: - Reading

    /// The draft for one exercise or one lesson, if the learner has
    /// saved one. The id is an exercise id (StudioExercise.id) or
    /// a lesson id (StudioLesson.id); see the file header.
    func draft(for exerciseID: String) -> StudioDraft? {
        drafts.first { $0.exerciseID == exerciseID }
    }

    /// True when the learner has saved a draft for this exercise.
    func hasDraft(for exerciseID: String) -> Bool {
        draft(for: exerciseID) != nil
    }

    /// All drafts, newest updated first.
    func allDrafts() -> [StudioDraft] {
        drafts.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Writing

    /// Save the draft for one exercise, creating it when there is
    /// none yet and updating it when there is. The created date
    /// and any AI-review flag on an existing draft are kept.
    /// Saving an empty draft with no ticked sections and no
    /// AI-review flag removes nothing and creates nothing: an
    /// empty workspace is not a draft.
    func saveDraft(exerciseID: String, text: String, completedSections: [String]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = draft(for: exerciseID) {
            var updated = existing
            updated.text = text
            updated.completedSections = completedSections
            updated.updatedAt = Date()
            if let index = drafts.firstIndex(where: { $0.id == existing.id }) {
                drafts[index] = updated
            }
            save()
            return
        }
        guard !trimmed.isEmpty || !completedSections.isEmpty else { return }
        let draft = StudioDraft(
            exerciseID: exerciseID,
            text: text,
            completedSections: completedSections
        )
        drafts.append(draft)
        save()
    }

    /// Record that the learner asked for an AI review of the
    /// draft for one exercise. Kept for stored drafts and tests;
    /// no UI in the app presents it. When no draft exists yet,
    /// the current text is saved with it.
    func markAIReviewRequested(exerciseID: String, text: String, completedSections: [String]) {
        saveDraft(exerciseID: exerciseID, text: text, completedSections: completedSections)
        guard let existing = draft(for: exerciseID),
              let index = drafts.firstIndex(where: { $0.id == existing.id }) else { return }
        drafts[index].aiReviewRequestedAt = Date()
        drafts[index].updatedAt = Date()
        save()
    }

    /// Delete the draft for one exercise. The learner's text is
    /// removed from this device; there is no copy anywhere else.
    func deleteDraft(for exerciseID: String) {
        drafts.removeAll { $0.exerciseID == exerciseID }
        save()
    }

    /// Delete one draft by id.
    func deleteDraft(id: UUID) {
        drafts.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        AccountScopedStorage.adoptLegacyKey(Keys.drafts)
        guard let data = UserDefaults.standard.data(forKey: AccountScopedStorage.currentKey(Keys.drafts)),
              let decoded = try? JSONDecoder().decode([StudioDraft].self, from: data) else {
            return
        }
        drafts = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(drafts) {
            UserDefaults.standard.set(data, forKey: AccountScopedStorage.currentKey(Keys.drafts))
        }
    }
}
