// OnboardingProfile.swift
// PaymentForge iOS - Optional first-time onboarding: the learner's
// role, knowledge level, objective and pace, plus the store that
// keeps the profile on this device.
//
// Onboarding is optional and never gates browsing: the learner can
// skip it in one tap from any step, and skipping is recorded so the
// flow is not shown again on this install. It never forces
// sign-in. The profile is stored per account namespace through
// AccountScopedStorage, following the PathBookmarkStore pattern:
// saves are suppressed while loading, legacy un-namespaced keys are
// adopted once, and reload clears in-memory state first. The
// completion flag is different: it is install level, stored under
// its plain key with no account namespace, so signing in, signing
// out, or a crash and relaunch never shows onboarding again. The
// flag is written the moment onboarding completes or is skipped.
//
// The knowledge level here is self described payments knowledge
// (beginner, intermediate, advanced). It is NOT the years of
// experience bands in LearningPreferences experienceLevel
// (ExperienceLevel, in UserProfile.swift). The two concepts are
// deliberately never conflated: onboarding does not write
// experienceLevel.
// No em dashes in any user-facing text.

import Foundation
import Combine

// MARK: - Role

/// What the learner does, in their own terms. Raw values are stored
/// in the persisted profile, so never rename an existing case.
enum LearnerRole: String, CaseIterable, Codable, Hashable {
    case newToPayments = "new-to-payments"
    case businessAnalyst = "business-analyst"
    case technicalAnalyst = "technical-analyst"
    case productOwner = "product-owner"
    case tester = "tester"
    case crossBorderSpecialist = "cross-border-specialist"
    case sme = "sme"
    case solutionArchitect = "solution-architect"

    var displayTitle: String {
        switch self {
        case .newToPayments: return "New to payments"
        case .businessAnalyst: return "Business analyst"
        case .technicalAnalyst: return "Technical analyst"
        case .productOwner: return "Product owner"
        case .tester: return "Tester"
        case .crossBorderSpecialist: return "Cross-border specialist"
        case .sme: return "Subject matter expert"
        case .solutionArchitect: return "Solution architect"
        }
    }

    var displayDescription: String {
        switch self {
        case .newToPayments: return "You are starting out and want the foundations first."
        case .businessAnalyst: return "You gather requirements and shape how payments work."
        case .technicalAnalyst: return "You work with payment systems, data and integrations."
        case .productOwner: return "You own a payments product and decide what gets built."
        case .tester: return "You test payment flows and check they behave as expected."
        case .crossBorderSpecialist: return "You work on international payments and investigations."
        case .sme: return "You already know payments deeply and want depth in new areas."
        case .solutionArchitect: return "You design payment systems and their architecture."
        }
    }
}

// MARK: - Knowledge level

/// Self described payments knowledge. This is a statement about
/// payments knowledge, not years of experience: it is never written
/// into LearningPreferences experienceLevel, which holds years of
/// experience bands.
enum LearnerKnowledgeLevel: String, CaseIterable, Codable, Hashable {
    case beginner
    case intermediate
    case advanced

    var displayTitle: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }
}

// MARK: - Objective

/// The learner's primary reason for learning. Raw values are stored
/// in the persisted profile, so never rename an existing case.
enum LearningObjective: String, CaseIterable, Codable, Hashable {
    case buildFoundations = "build-foundations"
    case prepareForInterviews = "prepare-for-interviews"
    case doTheJobBetter = "do-the-job-better"
    case specialise = "specialise"
    case leadAndDesign = "lead-and-design"

    var displayTitle: String {
        switch self {
        case .buildFoundations: return "Build foundations"
        case .prepareForInterviews: return "Prepare for interviews"
        case .doTheJobBetter: return "Do the job better"
        case .specialise: return "Specialise in one area"
        case .leadAndDesign: return "Lead and design payments work"
        }
    }
}

// MARK: - Intensity

/// How much the learner plans to study each week. The weekly lesson
/// target is the intensity's target: the onboarding flow writes it
/// into ProgressStore.weeklyGoal as well, so Home and Learning
/// Preferences agree, because ProgressStore is the single home of
/// the weekly goal.
enum LearningIntensity: String, CaseIterable, Codable, Hashable {
    case light
    case steady
    case intensive

    var displayTitle: String {
        switch self {
        case .light: return "Light"
        case .steady: return "Steady"
        case .intensive: return "Intensive"
        }
    }

    var weeklyLessonTarget: Int {
        switch self {
        case .light: return 2
        case .steady: return 5
        case .intensive: return 7
        }
    }
}

// MARK: - Profile

/// The completed onboarding profile. diagnosticScore is a fraction
/// from 0 to 1, nil when the diagnostic was skipped. diagnosticTakenAt
/// is set only when a diagnostic score was recorded. wasSkipped is
/// false for a completed profile; a skipped onboarding stores no
/// profile at all (see OnboardingStore.markSkipped), so a stored
/// profile with wasSkipped true never occurs.
struct OnboardingProfile: Codable, Hashable, Equatable {
    var role: LearnerRole
    var knowledgeLevel: LearnerKnowledgeLevel
    var objective: LearningObjective
    var intensity: LearningIntensity
    var weeklyTarget: Int
    var diagnosticScore: Double?
    var diagnosticTakenAt: Date?
    var completedAt: Date
    var wasSkipped: Bool
}

// MARK: - Store

/// Keeps the onboarding profile for the current account namespace
/// and the install-level completed flag. Follows the
/// PathBookmarkStore pattern for the profile: suppress-save while
/// loading, adoptLegacyKey on load, reload clears in-memory state
/// first. Reload never touches the completed flag: it belongs to
/// the install, not to any account.
final class OnboardingStore: ObservableObject {
    static let shared = OnboardingStore()

    /// The profile key, namespaced per account by
    /// AccountScopedStorage. AuthService duplicates this literal
    /// in its guest migration list; keep the two in step.
    static let profileBaseKey = "pf.onboarding.profile.v1"
    /// The completed flag key, used PLAIN, with no account
    /// namespace: onboarding shows exactly once per install. The
    /// constant name is kept for the existing key contract (see
    /// OnboardingTests testBaseKeysMatchTheContract); only its
    /// use changed. AuthService still lists this literal in its
    /// guest migration list; that entry is now inert, because no
    /// namespaced completed key is ever written or read. Never
    /// pass this key through AccountScopedStorage: the
    /// adoptLegacyKey helper would delete the plain key.
    static let completedBaseKey = "pf.onboarding.completed.v1"

    @Published private(set) var profile: OnboardingProfile? = nil {
        didSet { save() }
    }

    /// True once onboarding has finished or been skipped on this
    /// install. Install level, not per account: signing in,
    /// signing out, switching accounts, or a crash and relaunch
    /// never resets it. A fresh install starts false.
    @Published private(set) var hasCompletedOnboarding: Bool = false {
        didSet { save() }
    }

    /// Suppresses save() while loading, so a reload into an account
    /// with no stored profile does not write empty values into that
    /// namespace (which would block guest migration for it).
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

    /// Save a completed profile and mark onboarding complete on
    /// this install. The flag is written to its plain key first,
    /// before the profile is stored, so completion survives even
    /// if the app crashes before the profile write finishes. A
    /// diagnostic score outside 0 to 1 is clamped into range; no
    /// other value is rewritten.
    func saveProfile(_ profile: OnboardingProfile) {
        UserDefaults.standard.set(true, forKey: Self.completedBaseKey)
        var stored = profile
        if let score = stored.diagnosticScore {
            stored.diagnosticScore = min(1, max(0, score))
        }
        hasCompletedOnboarding = true
        self.profile = stored
    }

    /// Record that onboarding was skipped: no profile is kept, and
    /// onboarding is marked complete on this install so the flow
    /// is not shown again, on any account. The flag is written to
    /// its plain key first, before the profile is cleared, so a
    /// skip survives a crash. The weekly goal is untouched: a skip
    /// must not change ProgressStore.weeklyGoal.
    func markSkipped() {
        UserDefaults.standard.set(true, forKey: Self.completedBaseKey)
        hasCompletedOnboarding = true
        profile = nil
    }

    /// Reload the profile for the current account namespace,
    /// clearing the previous account's profile first. The
    /// completed flag is deliberately untouched: it is install
    /// level, so a sign-in, sign-out, or session restore never
    /// shows onboarding again.
    func reloadForCurrentAccount() {
        withoutSaving {
            profile = nil
        }
        loadProfile()
    }

    private func load() {
        loadProfile()
        loadCompletedFlag()
    }

    /// Load the profile for the current account namespace,
    /// adopting a legacy un-namespaced profile once. The
    /// completed flag is never adopted here: its plain key IS
    /// the install-level key, and adoptLegacyKey would delete it.
    private func loadProfile() {
        withoutSaving {
            AccountScopedStorage.adoptLegacyKey(Self.profileBaseKey)
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: AccountScopedStorage.currentKey(Self.profileBaseKey)),
               let decoded = try? JSONDecoder().decode(OnboardingProfile.self, from: data) {
                profile = decoded
            } else {
                profile = nil
            }
        }
    }

    /// Load the install-level completed flag from its plain key.
    /// When the plain key has never been written, a true value in
    /// any pre-fix account-namespaced copy is adopted once into
    /// the plain key, so learners who already completed onboarding
    /// under the old per-account flag are not shown it again after
    /// updating. Namespaced copies are read only for this one-time
    /// adoption and are never written.
    private func loadCompletedFlag() {
        withoutSaving {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: Self.completedBaseKey) != nil {
                hasCompletedOnboarding = defaults.bool(forKey: Self.completedBaseKey)
                return
            }
            hasCompletedOnboarding = Self.hasNamespacedCompletedFlag()
            if hasCompletedOnboarding {
                defaults.set(true, forKey: Self.completedBaseKey)
            }
        }
    }

    /// True when any account-namespaced copy of the completed flag
    /// is true. Pre-fix builds wrote one copy per namespace under
    /// "pf.account.<namespace>.pf.onboarding.completed.v1"; the
    /// scan covers the guest copy, the current account copy, and
    /// any other account that completed onboarding on this
    /// install. The plain key itself never matches: it carries no
    /// "pf.account." prefix.
    private static func hasNamespacedCompletedFlag() -> Bool {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            guard key.hasPrefix("pf.account."), key.hasSuffix(Self.completedBaseKey) else { continue }
            if defaults.bool(forKey: key) { return true }
        }
        return false
    }

    private func save() {
        guard !suppressSave else { return }
        let defaults = UserDefaults.standard
        if let profile, let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: AccountScopedStorage.currentKey(Self.profileBaseKey))
        } else {
            defaults.removeObject(forKey: AccountScopedStorage.currentKey(Self.profileBaseKey))
        }
        // The flag writes to its plain key: install level, no
        // account namespace. It is written on every save, so the
        // published value and the stored value can never drift.
        defaults.set(hasCompletedOnboarding, forKey: Self.completedBaseKey)
    }
}

// MARK: - Route recommendation

/// Picks one guided learning path from the onboarding answers. This
/// is a recommendation only: browsing is never gated, and the
/// learner can follow any path. Beginners are always routed to
/// Payments Fundamentals, because the other paths assume
/// foundations. The UPI Specialist and Cards and Digital Banking
/// paths are never recommended: onboarding asks no question that
/// distinguishes them, so no honest mapping reaches them. They stay
/// available under Learning Paths.
enum OnboardingRecommendation {
    static func path(for role: LearnerRole, objective: LearningObjective, knowledgeLevel: LearnerKnowledgeLevel) -> LearningPath {
        let pathID: String
        if knowledgeLevel == .beginner {
            pathID = "fundamentals"
        } else {
            switch objective {
            case .buildFoundations:
                pathID = "fundamentals"
            case .prepareForInterviews:
                pathID = "interview-preparation"
            case .doTheJobBetter, .specialise, .leadAndDesign:
                switch role {
                case .businessAnalyst, .productOwner:
                    pathID = "business-analyst"
                case .newToPayments:
                    pathID = "fundamentals"
                case .technicalAnalyst, .tester, .crossBorderSpecialist, .sme, .solutionArchitect:
                    pathID = "operations-reconciliation"
                }
            }
        }
        return LearningPath.all.first(where: { $0.id == pathID }) ?? LearningPath.all[0]
    }
}
