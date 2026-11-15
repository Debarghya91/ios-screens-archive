// UserProfile.swift
// PaymentForge iOS - Account and preference models for Supabase.
// These mirror the tables in supabase/migrations/0001_init.sql exactly.
// No em dashes in any user-facing text.

import Foundation

// MARK: - Signed-in user

/// The signed-in user, as the app sees them. Built from the Supabase
/// Auth session, never from a hardcoded name or email.
struct AuthUser: Codable, Equatable, Identifiable {
    let id: String
    let email: String?
    let displayName: String?
    let isEmailVerified: Bool

    /// Initials for the avatar placeholder circle, from the display
    /// name or the email. Falls back to "G" for a guest.
    var initials: String {
        let source = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? email?.components(separatedBy: "@").first
            ?? ""
        let words = source.split(separator: " ")
        if words.count >= 2 {
            let first = words[0].prefix(1)
            let second = words[1].prefix(1)
            return String(first + second).uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }
}

// MARK: - Profile row (profiles table)

/// One row of the profiles table. id is the Supabase auth user id.
struct UserProfile: Codable, Equatable {
    var id: String
    var fullName: String?
    var email: String?
    var designation: String?
    var organisation: String?
    var yearsExperience: Int?
    var avatarURL: String?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
        case designation
        case organisation
        case yearsExperience = "years_experience"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Display name for the Profile screen. Never a hardcoded name:
    /// nil means the user has not set one yet.
    var displayName: String? {
        guard let fullName, !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return fullName
    }
}

// MARK: - Learning preferences (user_preferences table)

/// Experience levels offered on the Learning Preferences screen.
enum ExperienceLevel: String, CaseIterable, Codable {
    case years0to2 = "0-2 yrs"
    case years3to5 = "3-5 yrs"
    case years5to10 = "5-10 yrs"
    case years10Plus = "10+ yrs"
}

/// The interest areas offered on the Learning Preferences screen.
enum InterestArea: String, CaseIterable, Codable {
    case upi = "UPI"
    case cardPayments = "Card Payments"
    case iso20022 = "ISO 20022"
    case paymentSwitches = "Payment Switches"
    case reconciliation = "Reconciliation"
    case disputes = "Disputes and Chargebacks"
    case regulations = "Regulations"
    case crossBorder = "Cross-border Payments"
}

/// One row of the user_preferences table, plus the local fallback.
/// Guests keep these in UserDefaults only; signed-in users also sync
/// them to Supabase through SyncService. Local storage is namespaced
/// per account through AccountScopedStorage, so one account's saved
/// preferences are never served to another.
/// The weekly goal lives in ONE place only: ProgressStore.weeklyGoal.
/// It used to be duplicated here as weeklyTarget (and synced through
/// SyncService); that duplicate is deleted, so there is one goal, one
/// store, one value everywhere.
struct LearningPreferences: Codable, Equatable {
    var userID: String?
    var experienceLevel: String?
    var domainInterests: [String]
    var includeAudio: Bool
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case experienceLevel = "experience_level"
        case domainInterests = "domain_interests"
        case includeAudio = "include_audio"
        case updatedAt = "updated_at"
    }

    static let `default` = LearningPreferences(
        userID: nil,
        experienceLevel: nil,
        domainInterests: [],
        includeAudio: true,
        updatedAt: nil
    )

    // MARK: - Local persistence (guests and offline fallback)

    private enum LocalKeys {
        static let experienceLevel = "pf.prefs.experienceLevel.v1"
        static let domainInterests = "pf.prefs.domainInterests.v1"
        static let includeAudio = "pf.prefs.includeAudio.v1"
        static let hasSaved = "pf.prefs.hasSaved.v1"
    }

    /// True once the user has explicitly saved preferences on this
    /// device. Local is authoritative once set: a stale server row
    /// must never overwrite it. Until set, the server row (if any)
    /// is used to restore preferences on a fresh device.
    static var hasSavedLocally: Bool {
        UserDefaults.standard.bool(forKey: AccountScopedStorage.currentKey(LocalKeys.hasSaved))
    }

    static func loadLocal() -> LearningPreferences {
        for baseKey in [LocalKeys.experienceLevel, LocalKeys.domainInterests, LocalKeys.includeAudio, LocalKeys.hasSaved] {
            AccountScopedStorage.adoptLegacyKey(baseKey)
        }
        let defaults = UserDefaults.standard
        return LearningPreferences(
            userID: nil,
            experienceLevel: defaults.string(forKey: AccountScopedStorage.currentKey(LocalKeys.experienceLevel)),
            domainInterests: defaults.stringArray(forKey: AccountScopedStorage.currentKey(LocalKeys.domainInterests)) ?? [],
            includeAudio: defaults.object(forKey: AccountScopedStorage.currentKey(LocalKeys.includeAudio)) as? Bool ?? true,
            updatedAt: nil
        )
    }

    func saveLocal() {
        let defaults = UserDefaults.standard
        defaults.set(experienceLevel, forKey: AccountScopedStorage.currentKey(LocalKeys.experienceLevel))
        defaults.set(domainInterests, forKey: AccountScopedStorage.currentKey(LocalKeys.domainInterests))
        defaults.set(includeAudio, forKey: AccountScopedStorage.currentKey(LocalKeys.includeAudio))
        defaults.set(true, forKey: AccountScopedStorage.currentKey(LocalKeys.hasSaved))
    }

    /// Clear the current namespace's saved preferences, including
    /// the has-saved flag, so a later sign-in can restore the
    /// account's server row. Before namespacing this left the flag
    /// set; clearing it is part of clearing. Other namespaces are
    /// untouched. Account deletion removes the whole namespace
    /// separately through AccountScopedStorage.
    static func clearLocal() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AccountScopedStorage.currentKey(LocalKeys.experienceLevel))
        defaults.removeObject(forKey: AccountScopedStorage.currentKey(LocalKeys.domainInterests))
        defaults.removeObject(forKey: AccountScopedStorage.currentKey(LocalKeys.includeAudio))
        defaults.removeObject(forKey: AccountScopedStorage.currentKey(LocalKeys.hasSaved))
    }
}

// MARK: - Server progress row (user_progress table)

/// One row of the user_progress table.
struct ServerProgressRow: Codable {
    var userID: String
    var lessonID: String
    var completed: Bool
    var completedAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case lessonID = "lesson_id"
        case completed
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
    }
}

/// One row of the quiz_attempts table.
struct QuizAttemptRow: Codable {
    var userID: String
    var lessonID: String
    var correct: Int
    var total: Int
    var score: Int
    var attemptedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case lessonID = "lesson_id"
        case correct
        case total
        case score
        case attemptedAt = "attempted_at"
    }
}

/// One row of the learning_activity table: one row per user per day.
/// The app aggregates local LearningEvents into this shape; the
/// unique (user_id, activity_date) key makes repeat pushes update
/// the same row instead of duplicating it.
struct LearningActivityRow: Codable {
    var userID: String
    var activityDate: String
    var lessonsCompleted: Int
    var minutes: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case activityDate = "activity_date"
        case lessonsCompleted = "lessons_completed"
        case minutes
    }
}

/// One row of the lesson_bookmarks table: one row per user per
/// bookmarked lesson. Situation bookmarks have no server table and
/// stay on the device only.
struct LessonBookmarkRow: Codable {
    var userID: String
    var lessonID: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case lessonID = "lesson_id"
    }
}

/// One row of the user_learning_paths table: one enrolment in a
/// guided path, with progress 0 to 100. The table has no updated_at
/// column, so the sync conflict rule for paths is highest progress
/// wins, never a regression (see SyncService). enrolled_at is only
/// encoded when present: the column defaults to now() on insert, and
/// an explicit null would be rejected.
struct UserLearningPathRow: Codable {
    var userID: String
    var pathID: String
    var enrolledAt: String?
    var progressPct: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case pathID = "path_id"
        case enrolledAt = "enrolled_at"
        case progressPct = "progress_pct"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(pathID, forKey: .pathID)
        try container.encodeIfPresent(enrolledAt, forKey: .enrolledAt)
        try container.encode(progressPct, forKey: .progressPct)
    }
}
