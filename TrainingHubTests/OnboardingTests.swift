// OnboardingTests.swift
// TrainingHub iOS - Phase 2 unit tests: optional first-time
// onboarding. Covers the profile encode/decode round trip, the
// intensity weekly targets, the enum raw values the persisted
// profile depends on, the store save/skip/reload semantics across
// account namespaces, the route recommendation mapping, and the
// diagnostic score helpers. Views are not tested: there is no UI
// test harness in this suite for them.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
//
// Test namespaces ("test-onboarding-a" and friends) are removed in
// tearDown, the guest onboarding keys are removed too, and the
// current namespace is reset to guest, so no test leaks state into
// another test file sharing the process. Tests use fresh
// OnboardingStore instances, never OnboardingStore.shared.

import XCTest
@testable import TrainingHub

@MainActor
final class OnboardingTests: XCTestCase {

    private let namespaceA = "test-onboarding-a"
    private let namespaceB = "test-onboarding-b"

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(nil)
        removeOnboardingKeys(in: AccountScopedStorage.guestNamespace)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
    }

    override func tearDown() {
        removeOnboardingKeys(in: AccountScopedStorage.guestNamespace)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
        AccountScopedStorage.setCurrentNamespace(nil)
        super.tearDown()
    }

    private func removeOnboardingKeys(in namespace: String) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AccountScopedStorage.key(OnboardingStore.profileBaseKey, namespace: namespace))
        defaults.removeObject(forKey: AccountScopedStorage.key(OnboardingStore.completedBaseKey, namespace: namespace))
        // The completed flag is install-level (plain key, no namespace);
        // remove it too or it leaks between tests.
        defaults.removeObject(forKey: OnboardingStore.completedBaseKey)
    }

    private func sampleProfile(score: Double? = 0.75) -> OnboardingProfile {
        OnboardingProfile(
            role: .businessAnalyst,
            knowledgeLevel: .intermediate,
            objective: .doTheJobBetter,
            intensity: .steady,
            weeklyTarget: 5,
            diagnosticScore: score,
            diagnosticTakenAt: score == nil ? nil : Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_100),
            wasSkipped: false
        )
    }

    // MARK: - Base keys

    func testBaseKeysMatchTheContract() {
        XCTAssertEqual(OnboardingStore.profileBaseKey, "pf.onboarding.profile.v1")
        XCTAssertEqual(OnboardingStore.completedBaseKey, "pf.onboarding.completed.v1")
        XCTAssertNotEqual(OnboardingStore.profileBaseKey, OnboardingStore.completedBaseKey)
    }

    func testBaseKeysAreNamespacedPerAccount() {
        let profileA = AccountScopedStorage.key(OnboardingStore.profileBaseKey, namespace: namespaceA)
        let profileB = AccountScopedStorage.key(OnboardingStore.profileBaseKey, namespace: namespaceB)
        let profileGuest = AccountScopedStorage.key(OnboardingStore.profileBaseKey, namespace: AccountScopedStorage.guestNamespace)
        XCTAssertEqual(profileA, "pf.account.\(namespaceA).pf.onboarding.profile.v1")
        XCTAssertNotEqual(profileA, profileB)
        XCTAssertNotEqual(profileA, profileGuest)
    }

    // MARK: - Profile round trip

    func testProfileEncodeDecodeRoundTripWithDiagnosticScore() throws {
        let profile = sampleProfile(score: 0.75)
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(OnboardingProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.diagnosticScore, 0.75)
        XCTAssertEqual(decoded.diagnosticTakenAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testProfileEncodeDecodeRoundTripWithSkippedDiagnostic() throws {
        let profile = sampleProfile(score: nil)
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(OnboardingProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
        XCTAssertNil(decoded.diagnosticScore)
        XCTAssertNil(decoded.diagnosticTakenAt)
    }

    func testProfileRoundTripsEveryRoleAndObjective() throws {
        for role in LearnerRole.allCases {
            for objective in LearningObjective.allCases {
                var profile = sampleProfile(score: nil)
                profile.role = role
                profile.objective = objective
                let data = try JSONEncoder().encode(profile)
                let decoded = try JSONDecoder().decode(OnboardingProfile.self, from: data)
                XCTAssertEqual(decoded.role, role)
                XCTAssertEqual(decoded.objective, objective)
            }
        }
    }

    // MARK: - Enums

    func testRoleRawValues() {
        XCTAssertEqual(LearnerRole.newToPayments.rawValue, "new-to-payments")
        XCTAssertEqual(LearnerRole.businessAnalyst.rawValue, "business-analyst")
        XCTAssertEqual(LearnerRole.technicalAnalyst.rawValue, "technical-analyst")
        XCTAssertEqual(LearnerRole.productOwner.rawValue, "product-owner")
        XCTAssertEqual(LearnerRole.tester.rawValue, "tester")
        XCTAssertEqual(LearnerRole.crossBorderSpecialist.rawValue, "cross-border-specialist")
        XCTAssertEqual(LearnerRole.sme.rawValue, "sme")
        XCTAssertEqual(LearnerRole.solutionArchitect.rawValue, "solution-architect")
        XCTAssertEqual(LearnerRole.allCases.count, 8)
    }

    func testObjectiveRawValues() {
        XCTAssertEqual(LearningObjective.buildFoundations.rawValue, "build-foundations")
        XCTAssertEqual(LearningObjective.prepareForInterviews.rawValue, "prepare-for-interviews")
        XCTAssertEqual(LearningObjective.doTheJobBetter.rawValue, "do-the-job-better")
        XCTAssertEqual(LearningObjective.specialise.rawValue, "specialise")
        XCTAssertEqual(LearningObjective.leadAndDesign.rawValue, "lead-and-design")
        XCTAssertEqual(LearningObjective.allCases.count, 5)
    }

    func testKnowledgeLevels() {
        XCTAssertEqual(LearnerKnowledgeLevel.allCases.count, 3)
        XCTAssertEqual(LearnerKnowledgeLevel.beginner.displayTitle, "Beginner")
        XCTAssertEqual(LearnerKnowledgeLevel.intermediate.displayTitle, "Intermediate")
        XCTAssertEqual(LearnerKnowledgeLevel.advanced.displayTitle, "Advanced")
    }

    func testIntensityTargets() {
        XCTAssertEqual(LearningIntensity.light.weeklyLessonTarget, 2)
        XCTAssertEqual(LearningIntensity.steady.weeklyLessonTarget, 5)
        XCTAssertEqual(LearningIntensity.intensive.weeklyLessonTarget, 7)
        XCTAssertEqual(LearningIntensity.allCases.count, 3)
    }

    func testDisplayTextIsPresentForEveryCase() {
        for role in LearnerRole.allCases {
            XCTAssertFalse(role.displayTitle.isEmpty)
            XCTAssertFalse(role.displayDescription.isEmpty)
        }
        for level in LearnerKnowledgeLevel.allCases {
            XCTAssertFalse(level.displayTitle.isEmpty)
        }
        for objective in LearningObjective.allCases {
            XCTAssertFalse(objective.displayTitle.isEmpty)
        }
        for intensity in LearningIntensity.allCases {
            XCTAssertFalse(intensity.displayTitle.isEmpty)
            XCTAssertGreaterThan(intensity.weeklyLessonTarget, 0)
        }
    }

    // MARK: - Store save, skip and reload

    func testFreshStoreHasNoProfileAndIsNotComplete() {
        let store = OnboardingStore()
        XCTAssertNil(store.profile)
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    func testSaveProfilePersistsProfileNamespacedAndFlagPlain() {
        let store = OnboardingStore()
        let profile = sampleProfile()
        store.saveProfile(profile)
        XCTAssertEqual(store.profile, profile)
        XCTAssertTrue(store.hasCompletedOnboarding)
        let key = AccountScopedStorage.currentKey(OnboardingStore.profileBaseKey)
        let data = UserDefaults.standard.data(forKey: key)
        XCTAssertNotNil(data, "The profile is persisted as data under the namespaced key.")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: OnboardingStore.completedBaseKey), "The completed flag is install-level: stored under its plain key, no namespace.")
        XCTAssertNil(UserDefaults.standard.object(forKey: AccountScopedStorage.currentKey(OnboardingStore.completedBaseKey)), "No namespaced completed key is written.")
        let reloaded = OnboardingStore()
        XCTAssertEqual(reloaded.profile, profile)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }

    func testMarkSkippedKeepsNoProfileButMarksComplete() {
        let store = OnboardingStore()
        store.saveProfile(sampleProfile())
        XCTAssertNotNil(store.profile)
        store.markSkipped()
        XCTAssertNil(store.profile)
        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertNil(UserDefaults.standard.data(forKey: AccountScopedStorage.currentKey(OnboardingStore.profileBaseKey)))
        let reloaded = OnboardingStore()
        XCTAssertNil(reloaded.profile)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }

    func testSaveProfileClampsDiagnosticScoreIntoRange() {
        let store = OnboardingStore()
        store.saveProfile(sampleProfile(score: 1.5))
        XCTAssertEqual(store.profile?.diagnosticScore, 1.0)
        store.saveProfile(sampleProfile(score: -0.5))
        XCTAssertEqual(store.profile?.diagnosticScore, 0.0)
        store.saveProfile(sampleProfile(score: nil))
        XCTAssertNil(store.profile?.diagnosticScore)
    }

    func testReloadAcrossNamespacesKeepsProfilesSeparateButCompletionInstallLevel() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let storeA = OnboardingStore()
        storeA.saveProfile(sampleProfile())
        XCTAssertTrue(storeA.hasCompletedOnboarding)

        AccountScopedStorage.setCurrentNamespace(namespaceB)
        storeA.reloadForCurrentAccount()
        XCTAssertNil(storeA.profile, "A new account sees no profile: no profile leaks across namespaces.")
        XCTAssertTrue(storeA.hasCompletedOnboarding, "Completion is install-level: signing in never re-shows onboarding.")

        AccountScopedStorage.setCurrentNamespace(namespaceA)
        storeA.reloadForCurrentAccount()
        XCTAssertEqual(storeA.profile, sampleProfile())
        XCTAssertTrue(storeA.hasCompletedOnboarding)
    }

    func testReloadDoesNotWriteEmptyValuesIntoAnEmptyNamespace() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let store = OnboardingStore()
        store.saveProfile(sampleProfile())
        AccountScopedStorage.setCurrentNamespace(namespaceB)
        store.reloadForCurrentAccount()
        XCTAssertNil(UserDefaults.standard.object(forKey: AccountScopedStorage.key(OnboardingStore.profileBaseKey, namespace: namespaceB)), "Reloading into an empty namespace must not create a profile key there, or guest migration for it would be blocked.")
        XCTAssertNil(UserDefaults.standard.object(forKey: AccountScopedStorage.key(OnboardingStore.completedBaseKey, namespace: namespaceB)), "Reloading into an empty namespace must not create a completed key there.")
    }

    func testGuestProfileMigratesThroughTheSharedMigrationPath() {
        AccountScopedStorage.setCurrentNamespace(nil)
        let guestStore = OnboardingStore()
        guestStore.saveProfile(sampleProfile())
        let migrated = AccountScopedStorage.migrateGuestKeys(
            [OnboardingStore.profileBaseKey, OnboardingStore.completedBaseKey],
            to: namespaceA
        )
        // Only the profile migrates: the completed flag is install-level
        // (plain key), so it needs no migration and no namespaced copy.
        XCTAssertEqual(Set(migrated), [OnboardingStore.profileBaseKey])
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let accountStore = OnboardingStore()
        XCTAssertEqual(accountStore.profile, sampleProfile())
        XCTAssertTrue(accountStore.hasCompletedOnboarding)
    }

    // MARK: - Route recommendation

    func testBeginnersAreRoutedToFundamentals() {
        for role in LearnerRole.allCases {
            for objective in LearningObjective.allCases {
                let path = OnboardingRecommendation.path(for: role, objective: objective, knowledgeLevel: .beginner)
                XCTAssertEqual(path.id, "fundamentals", "Beginner \(role) aiming at \(objective) should start at fundamentals.")
            }
        }
    }

    func testInterviewObjectiveRoutesToInterviewPreparation() {
        let path = OnboardingRecommendation.path(for: .businessAnalyst, objective: .prepareForInterviews, knowledgeLevel: .intermediate)
        XCTAssertEqual(path.id, "interview-preparation")
    }

    func testBuildFoundationsRoutesToFundamentals() {
        let path = OnboardingRecommendation.path(for: .sme, objective: .buildFoundations, knowledgeLevel: .advanced)
        XCTAssertEqual(path.id, "fundamentals")
    }

    func testBusinessAnalystRoutesToBusinessAnalystPath() {
        let path = OnboardingRecommendation.path(for: .businessAnalyst, objective: .doTheJobBetter, knowledgeLevel: .intermediate)
        XCTAssertEqual(path.id, "business-analyst")
        let ownerPath = OnboardingRecommendation.path(for: .productOwner, objective: .leadAndDesign, knowledgeLevel: .advanced)
        XCTAssertEqual(ownerPath.id, "business-analyst")
    }

    func testTechnicalRolesRouteToOperationsAndReconciliation() {
        for role in [LearnerRole.technicalAnalyst, .tester, .crossBorderSpecialist, .sme, .solutionArchitect] {
            let path = OnboardingRecommendation.path(for: role, objective: .specialise, knowledgeLevel: .intermediate)
            XCTAssertEqual(path.id, "operations-reconciliation")
        }
    }

    func testRecommendationAlwaysReturnsARealPath() {
        for role in LearnerRole.allCases {
            for objective in LearningObjective.allCases {
                for level in LearnerKnowledgeLevel.allCases {
                    let path = OnboardingRecommendation.path(for: role, objective: objective, knowledgeLevel: level)
                    XCTAssertTrue(LearningPath.all.contains(path), "Every recommendation must be one of the real guided paths.")
                }
            }
        }
    }

    // MARK: - Diagnostic score helpers

    func testQuizScoreIsTheFractionCorrect() {
        XCTAssertEqual(DiagnosticOutcome.quizScore(correct: 4, total: 6) ?? -1, 4.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(DiagnosticOutcome.quizScore(correct: 0, total: 6), 0.0)
        XCTAssertEqual(DiagnosticOutcome.quizScore(correct: 6, total: 6), 1.0)
        XCTAssertNil(DiagnosticOutcome.quizScore(correct: 0, total: 0), "No score is computed from zero questions.")
        XCTAssertNil(DiagnosticOutcome.quizScore(correct: 7, total: 6))
        XCTAssertNil(DiagnosticOutcome.quizScore(correct: -1, total: 6))
    }

    func testSelfAssessmentScoreMapsRatingsToFractions() {
        XCTAssertEqual(DiagnosticOutcome.selfAssessmentScore(ratings: [1, 1, 1, 1, 1]), 0.0)
        XCTAssertEqual(DiagnosticOutcome.selfAssessmentScore(ratings: [5, 5, 5, 5, 5]), 1.0)
        XCTAssertEqual(DiagnosticOutcome.selfAssessmentScore(ratings: [3, 3, 3, 3, 3]), 0.5)
        XCTAssertEqual(DiagnosticOutcome.selfAssessmentScore(ratings: [1, 5]) ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertNil(DiagnosticOutcome.selfAssessmentScore(ratings: []))
        XCTAssertNil(DiagnosticOutcome.selfAssessmentScore(ratings: [0, 3]))
        XCTAssertNil(DiagnosticOutcome.selfAssessmentScore(ratings: [3, 6]))
    }
}
