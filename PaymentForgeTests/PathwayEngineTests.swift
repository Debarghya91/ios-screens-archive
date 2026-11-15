// PathwayEngineTests.swift
// PaymentForge iOS - Phase 2 unit tests: role routes, the active
// path store, the recommendation engine's mastered-exclusion rule,
// and estimated-weeks maths.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only.
//
// No test loads the catalogue, so catalogue-dependent behaviour is
// asserted as invariants that hold for any catalogue state (no
// duplicates, limits respected, completed lessons excluded from
// continue, next and fresh start kinds), never as specific lesson
// picks. setUp and tearDown pin a dedicated namespace and clear
// it, so no test leaks progress or selections into another test.

import XCTest
@testable import PaymentForge

@MainActor
final class PathwayEngineTests: XCTestCase {

    private let namespace = "test-pathway-engine"
    private let otherNamespace = "test-pathway-engine-other"

    private var progress: ProgressStore!
    private var competency: CompetencyStore!

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(namespace)
        AccountScopedStorage.removeAllKeys(in: namespace)
        AccountScopedStorage.removeAllKeys(in: otherNamespace)
        progress = ProgressStore()
        progress.resetAll()
        progress.weeklyGoal = 5
        competency = CompetencyStore()
    }

    override func tearDown() {
        progress.resetAll()
        progress = nil
        competency = nil
        AccountScopedStorage.removeAllKeys(in: namespace)
        AccountScopedStorage.removeAllKeys(in: otherNamespace)
        AccountScopedStorage.setCurrentNamespace(nil)
        super.tearDown()
    }

    private func sampleProfile(role: LearnerRole, score: Double? = nil, skipped: Bool = false) -> OnboardingProfile {
        OnboardingProfile(
            role: role,
            knowledgeLevel: .intermediate,
            objective: .doTheJobBetter,
            intensity: .steady,
            weeklyTarget: 5,
            diagnosticScore: score,
            diagnosticTakenAt: score == nil ? nil : Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_100),
            wasSkipped: skipped
        )
    }

    // MARK: - Route catalogue

    func testAllEightRolesHaveExactlyOneRoute() {
        XCTAssertEqual(LearnerRole.allCases.count, 8)
        XCTAssertEqual(RoleRouteCatalogue.routes.count, 8)
        let roles = RoleRouteCatalogue.routes.map(\.role)
        XCTAssertEqual(Set(roles).count, 8, "Each role maps to exactly one route.")
        XCTAssertEqual(Set(roles), Set(LearnerRole.allCases))
        let ids = RoleRouteCatalogue.routes.map(\.id)
        XCTAssertEqual(Set(ids).count, 8, "Route ids are unique.")
        for role in LearnerRole.allCases {
            XCTAssertEqual(RoleRouteCatalogue.route(for: role).role, role)
        }
    }

    func testRoutesReferenceOnlyRealSessionAndPathIDs() {
        let realSessionIDs = Set(ContentService.guidedSessions.map(\.id))
        XCTAssertEqual(realSessionIDs, Set(1...8))
        let realPathIDs = Set(LearningPath.all.map(\.id))
        XCTAssertEqual(LearningPath.all.count, 6)
        for route in RoleRouteCatalogue.routes {
            XCTAssertFalse(route.sessionIDs.isEmpty, "Every route names at least one session.")
            XCTAssertTrue(
                Set(route.sessionIDs).isSubset(of: realSessionIDs),
                "Route \(route.id) names only real session ids."
            )
            if let pathID = route.pathID {
                XCTAssertTrue(realPathIDs.contains(pathID), "Route \(route.id) names a real path id.")
                let found = RoleRouteCatalogue.route(forPathID: pathID)
                XCTAssertNotNil(found)
                XCTAssertEqual(found?.pathID, pathID)
            }
        }
        XCTAssertNil(RoleRouteCatalogue.route(forPathID: "no-such-path"))
    }

    func testRouteMappingMatchesBrief() {
        let expected: [(LearnerRole, String?, [Int])] = [
            (.newToPayments, "fundamentals", [1, 2]),
            (.businessAnalyst, "business-analyst", [8]),
            (.technicalAnalyst, nil, [1, 2, 4, 6]),
            (.productOwner, "business-analyst", [1, 5]),
            (.tester, "operations-reconciliation", [1, 6, 8]),
            (.crossBorderSpecialist, "interview-preparation", [2, 3, 4]),
            (.sme, "interview-preparation", [1, 2, 3, 4, 5, 6, 7, 8]),
            (.solutionArchitect, "operations-reconciliation", [2, 4, 6])
        ]
        for (role, pathID, sessionIDs) in expected {
            let route = RoleRouteCatalogue.route(for: role)
            XCTAssertEqual(route.pathID, pathID, "Route for \(role) names the briefed path.")
            XCTAssertEqual(route.sessionIDs, sessionIDs, "Route for \(role) names the briefed sessions, in order.")
            XCTAssertEqual(route.displayTitle, route.title)
        }
    }

    func testRouteForPathIDFindsFirstRouteForSharedPaths() {
        XCTAssertEqual(RoleRouteCatalogue.route(forPathID: "fundamentals")?.role, .newToPayments)
        XCTAssertEqual(RoleRouteCatalogue.route(forPathID: "business-analyst")?.role, .businessAnalyst)
        XCTAssertEqual(RoleRouteCatalogue.route(forPathID: "operations-reconciliation")?.role, .tester)
        XCTAssertEqual(RoleRouteCatalogue.route(forPathID: "interview-preparation")?.role, .crossBorderSpecialist)
        XCTAssertNil(RoleRouteCatalogue.route(forPathID: "upi-specialist"), "No route names the UPI path.")
        XCTAssertNil(RoleRouteCatalogue.route(forPathID: "cards-digital"), "No route names the cards path.")
    }

    func testRouteLessonsHaveNoDuplicates() {
        for route in RoleRouteCatalogue.routes {
            let lessons = route.lessons(in: ContentService.shared)
            XCTAssertEqual(Set(lessons.map(\.id)).count, lessons.count, "Route \(route.id) lists each lesson once.")
            XCTAssertTrue(lessons.allSatisfy { $0.type == .lesson }, "Route lessons are lessons, never labs or guides.")
        }
    }

    func testRouteSessionsResolveInOrder() {
        let route = RoleRouteCatalogue.route(for: .technicalAnalyst)
        XCTAssertEqual(route.sessions().map(\.id), [1, 2, 4, 6])
        XCTAssertNil(RoleRouteCatalogue.route(for: .technicalAnalyst).learningPath())
        XCTAssertEqual(RoleRouteCatalogue.route(for: .newToPayments).learningPath()?.id, "fundamentals")
    }

    // MARK: - Learning path additions

    func testLearningPathEntryExpectationsAndCriteriaArePresent() {
        for path in LearningPath.all {
            XCTAssertFalse(path.entryExpectations.isEmpty, "Path \(path.id) states entry expectations.")
            XCTAssertFalse(path.completionCriteria.isEmpty, "Path \(path.id) states completion criteria.")
            XCTAssertTrue(
                path.completionCriteria.lowercased().contains("no exam or assessment is required"),
                "Path \(path.id) never claims an exam is required."
            )
            if let certificateTitle = path.certificateTitle {
                XCTAssertTrue(
                    path.completionCriteria.contains(certificateTitle),
                    "Path \(path.id) names its certificate in the completion criteria."
                )
            } else {
                XCTAssertTrue(
                    path.completionCriteria.lowercased().contains("no certificate"),
                    "Path \(path.id) states it has no certificate."
                )
            }
        }
    }

    func testLearningPathLabsAreLabTypeInPathChapters() {
        for path in LearningPath.all {
            for lab in path.labs(in: ContentService.shared) {
                XCTAssertEqual(lab.type, .lab)
                XCTAssertNotNil(lab.chapterNumber)
                XCTAssertTrue(path.chapterNumbers.contains(lab.chapterNumber!), "Lab \(lab.id) belongs to a chapter of path \(path.id).")
            }
        }
    }

    func testEstimatedWeeksMaths() {
        XCTAssertEqual(LearningPath.estimatedWeeks(totalLessons: 10, weeklyTarget: 5), 2)
        XCTAssertEqual(LearningPath.estimatedWeeks(totalLessons: 11, weeklyTarget: 5), 3, "Partial weeks round up.")
        XCTAssertEqual(LearningPath.estimatedWeeks(totalLessons: 1, weeklyTarget: 5), 1)
        XCTAssertEqual(LearningPath.estimatedWeeks(totalLessons: 5, weeklyTarget: 5), 1)
        XCTAssertEqual(LearningPath.estimatedWeeks(totalLessons: 6, weeklyTarget: 5), 2)
        XCTAssertEqual(LearningPath.estimatedWeeks(totalLessons: 7, weeklyTarget: 7), 1)
        XCTAssertNil(LearningPath.estimatedWeeks(totalLessons: 0, weeklyTarget: 5))
        XCTAssertNil(LearningPath.estimatedWeeks(totalLessons: 10, weeklyTarget: 0))
        XCTAssertNil(LearningPath.estimatedWeeks(totalLessons: 10, weeklyTarget: -2))
        XCTAssertNil(LearningPath.estimatedWeeks(totalLessons: 0, weeklyTarget: 0))
    }

    func testEstimatedWeeksInstanceReturnsNilForInvalidTarget() {
        for path in LearningPath.all {
            XCTAssertNil(path.estimatedWeeks(weeklyTarget: 0), "Path \(path.id) returns nil for a zero target whatever the catalogue holds.")
            XCTAssertNil(path.estimatedWeeks(weeklyTarget: -3))
        }
    }

    // MARK: - Mastered exclusion

    func testMasteredRulePureHelper() {
        XCTAssertTrue(RecommendationEngine.isMastered(isComplete: true, bestQuizFraction: nil), "Complete with no quiz evidence counts as mastered.")
        XCTAssertTrue(RecommendationEngine.isMastered(isComplete: true, bestQuizFraction: 0.8), "80 percent is mastered.")
        XCTAssertTrue(RecommendationEngine.isMastered(isComplete: true, bestQuizFraction: 1.0))
        XCTAssertFalse(RecommendationEngine.isMastered(isComplete: true, bestQuizFraction: 0.79))
        XCTAssertFalse(RecommendationEngine.isMastered(isComplete: true, bestQuizFraction: 0.0))
        XCTAssertFalse(RecommendationEngine.isMastered(isComplete: false, bestQuizFraction: 1.0), "An incomplete lesson is never mastered.")
        XCTAssertFalse(RecommendationEngine.isMastered(isComplete: false, bestQuizFraction: nil))
    }

    func testMasteredRuleWithProgressStore() {
        progress.markLessonComplete(id: "ch1s1", title: "Lesson 1")
        progress.recordQuizScore(lessonID: "ch1s1", correct: 3, total: 3)
        XCTAssertTrue(RecommendationEngine.isMastered(lessonID: "ch1s1", progress: progress))

        progress.markLessonComplete(id: "ch1s2", title: "Lesson 2")
        progress.recordQuizScore(lessonID: "ch1s2", correct: 2, total: 3)
        XCTAssertFalse(RecommendationEngine.isMastered(lessonID: "ch1s2", progress: progress), "Two of three is below 80 percent.")

        progress.markLessonComplete(id: "ch1s3", title: "Lesson 3")
        XCTAssertTrue(RecommendationEngine.isMastered(lessonID: "ch1s3", progress: progress), "Complete with no quiz attempt counts as mastered.")

        progress.recordQuizScore(lessonID: "ch1s4", correct: 3, total: 3)
        XCTAssertFalse(RecommendationEngine.isMastered(lessonID: "ch1s4", progress: progress), "A perfect quiz without completion is not mastered.")
    }

    // MARK: - Active path store

    func testActivePathStorePersistsSelection() {
        let store = ActivePathStore()
        XCTAssertNil(store.activePathID)
        store.select("fundamentals")
        XCTAssertEqual(store.activePathID, "fundamentals")
        XCTAssertEqual(store.activePath?.id, "fundamentals")

        let reloaded = ActivePathStore()
        XCTAssertEqual(reloaded.activePathID, "fundamentals", "A fresh instance reads the stored selection.")

        reloaded.select(nil)
        XCTAssertNil(reloaded.activePathID)
        XCTAssertNil(ActivePathStore().activePathID, "Clearing the selection removes the stored id.")
    }

    func testActivePathResolvesLiveAndIgnoresUnknownIDs() {
        let store = ActivePathStore()
        store.select("no-such-path")
        XCTAssertEqual(store.activePathID, "no-such-path", "The id is stored as given.")
        XCTAssertNil(store.activePath, "An unknown id resolves to no path.")
        store.select("business-analyst")
        XCTAssertEqual(store.activePath?.title, "Payments Business Analyst")
    }

    func testActivePathStoreReloadIsolatesAccounts() {
        AccountScopedStorage.setCurrentNamespace(namespace)
        let firstStore = ActivePathStore()
        firstStore.select("fundamentals")
        XCTAssertEqual(firstStore.activePathID, "fundamentals")

        AccountScopedStorage.setCurrentNamespace(otherNamespace)
        let secondStore = ActivePathStore()
        XCTAssertNil(secondStore.activePathID, "The second namespace must not see the first namespace's selection.")

        secondStore.select("cards-digital")
        firstStore.reloadForCurrentAccount()
        XCTAssertEqual(firstStore.activePathID, "cards-digital", "Reload adopts the current namespace.")

        AccountScopedStorage.setCurrentNamespace(namespace)
        firstStore.reloadForCurrentAccount()
        XCTAssertEqual(firstStore.activePathID, "fundamentals", "Returning to the first namespace restores its selection.")
        AccountScopedStorage.setCurrentNamespace(namespace)
    }

    func testActivePathSwitchingDoesNotClearProgress() {
        progress.markLessonComplete(id: "ch1s1", title: "Lesson 1")
        progress.recordQuizScore(lessonID: "ch1s1", correct: 3, total: 3)
        let store = ActivePathStore()
        store.select("fundamentals")
        store.select("business-analyst")
        store.select(nil)
        store.reloadForCurrentAccount()
        XCTAssertTrue(progress.isLessonComplete("ch1s1"), "Switching the active path never clears completed lessons.")
        XCTAssertEqual(progress.quizScore(for: "ch1s1"), 3)
    }

    // MARK: - Recommendation engine invariants

    func testRecommendationsRespectLimitAndExcludeCompleted() {
        progress.markLessonComplete(id: "ch1s1", title: "Lesson 1")
        let service = ContentService.shared
        for profile: OnboardingProfile? in [nil, sampleProfile(role: .businessAnalyst), sampleProfile(role: .technicalAnalyst, score: 0.5)] {
            XCTAssertTrue(
                RecommendationEngine.recommendations(for: profile, progress: progress, competency: competency, service: service, limit: 0).isEmpty,
                "A zero limit returns nothing."
            )
            let recs = RecommendationEngine.recommendations(for: profile, progress: progress, competency: competency, service: service, limit: 3)
            XCTAssertLessThanOrEqual(recs.count, 3)
            XCTAssertEqual(Set(recs.map(\.lesson.id)).count, recs.count, "No lesson appears twice.")
            XCTAssertEqual(Set(recs.map(\.id)).count, recs.count, "Recommendation ids are unique.")
            for rec in recs {
                XCTAssertFalse(rec.reason.isEmpty, "Every recommendation names its evidence.")
                if rec.kind == .continuePath || rec.kind == .nextInPath || rec.kind == .freshStart {
                    XCTAssertFalse(
                        progress.isLessonComplete(rec.lesson.id),
                        "A completed lesson is never recommended as \(rec.kind)."
                    )
                }
            }
        }
    }

    func testNextLessonMatchesFirstRecommendation() {
        let service = ContentService.shared
        for profile: OnboardingProfile? in [nil, sampleProfile(role: .sme)] {
            let next = RecommendationEngine.nextLesson(for: profile, progress: progress, competency: competency, service: service)
            let first = RecommendationEngine.recommendations(for: profile, progress: progress, competency: competency, service: service, limit: 1).first
            XCTAssertEqual(next, first)
        }
    }

    func testSkippedProfileFallsBackToGuidedOrder() {
        let service = ContentService.shared
        let skipped = sampleProfile(role: .businessAnalyst, skipped: true)
        let skippedRecs = RecommendationEngine.recommendations(for: skipped, progress: progress, competency: competency, service: service, limit: 5)
        let guestRecs = RecommendationEngine.recommendations(for: nil, progress: progress, competency: competency, service: service, limit: 5)
        XCTAssertEqual(skippedRecs, guestRecs, "A skipped profile behaves exactly like no profile.")
    }

    func testRecommendationKindsCoverTheContract() {
        XCTAssertEqual(RecommendationKind.continuePath.rawValue, "continuePath")
        XCTAssertEqual(RecommendationKind.nextInPath.rawValue, "nextInPath")
        XCTAssertEqual(RecommendationKind.weakArea.rawValue, "weakArea")
        XCTAssertEqual(RecommendationKind.revision.rawValue, "revision")
        XCTAssertEqual(RecommendationKind.diagnosticGap.rawValue, "diagnosticGap")
        XCTAssertEqual(RecommendationKind.freshStart.rawValue, "freshStart")
    }
}

// MARK: - Wave 2: journey selection and course audience derivation
//
// UNEXECUTED: written on a Linux VM with no Xcode. Never compiled
// or run. Statically checked only.
//
// The Home "Continue learning" block shows the chosen journey's
// next lesson first, and the course detail derives "Who it is for"
// from journey chapter overlap. These tests exercise the rules
// behind both with the real journey and catalogue data: selection
// resolves live, chapter lists are valid, and every course but
// the last in reading order belongs to at least one journey.
// The SwiftUI blocks themselves are statically checked only.

@MainActor
final class Wave2JourneyRuleTests: XCTestCase {

    private let namespace = "test-wave2-journey-rule"

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(namespace)
        AccountScopedStorage.removeAllKeys(in: namespace)
    }

    override func tearDown() {
        AccountScopedStorage.removeAllKeys(in: namespace)
        AccountScopedStorage.setCurrentNamespace(nil)
        super.tearDown()
    }

    func testJourneySelectionResolvesAndClears() {
        let store = ActivePathStore()
        XCTAssertNil(store.activePathID)
        XCTAssertNil(store.activePath)

        store.select("business-analyst")
        XCTAssertEqual(store.activePathID, "business-analyst")
        XCTAssertEqual(store.activePath?.id, "business-analyst")

        store.select("upi-specialist")
        XCTAssertEqual(store.activePath?.id, "upi-specialist")

        store.select(nil)
        XCTAssertNil(store.activePathID)
        XCTAssertNil(store.activePath)
    }

    func testUnknownJourneyIDResolvesToNil() {
        let store = ActivePathStore()
        store.select("no-such-journey")
        XCTAssertEqual(store.activePathID, "no-such-journey")
        XCTAssertNil(store.activePath)
    }

    func testJourneyChapterListsAreValidAndUnique() {
        XCTAssertEqual(LearningPath.all.count, 6)
        for path in LearningPath.all {
            XCTAssertFalse(path.chapterNumbers.isEmpty, "\(path.id) has no chapters")
            XCTAssertTrue(
                path.chapterNumbers.allSatisfy { (1...ContentManifest.chapterCount).contains($0) },
                "\(path.id) names a chapter outside 1...\(ContentManifest.chapterCount)"
            )
            XCTAssertEqual(
                Set(path.chapterNumbers).count, path.chapterNumbers.count,
                "\(path.id) repeats a chapter"
            )
        }
        XCTAssertEqual(Set(LearningPath.all.map(\.id)).count, LearningPath.all.count)
    }

    func testJourneyOrderAndTitlesAreStable() {
        // The Continue block and the journeys list both read
        // LearningPath.all in order; the declared order is the
        // contract. firstIncompleteLesson itself needs a loaded
        // ContentService (private init, shared singleton, no
        // injectable seam), so it stays statically checked only.
        XCTAssertEqual(
            LearningPath.all.map(\.id),
            ["fundamentals", "business-analyst", "upi-specialist", "cards-digital", "operations-reconciliation", "interview-preparation"]
        )
        for path in LearningPath.all {
            XCTAssertFalse(path.title.isEmpty)
        }
    }

    func testEveryCourseButTheLastBelongsToAJourney() {
        let products = ProductCatalogue.partProducts
        XCTAssertFalse(products.isEmpty)
        var uncovered: [CourseProduct] = []
        for product in products {
            let wanted = Set(PFChapterHelper.readingOrderChapterNumbers(for: product))
            XCTAssertFalse(wanted.isEmpty, "\(product.productID) names no chapters")
            let overlaps = LearningPath.all.filter { !Set($0.chapterNumbers).isDisjoint(with: wanted) }
            if overlaps.isEmpty { uncovered.append(product) }
        }
        XCTAssertLessThanOrEqual(uncovered.count, 1)
        if let only = uncovered.first {
            XCTAssertEqual(only.productID, products.last?.productID)
        }
    }

    func testEveryJourneyOverlapsAtLeastOneCourse() {
        let products = ProductCatalogue.partProducts
        for path in LearningPath.all {
            let wanted = Set(path.chapterNumbers)
            let overlaps = products.filter {
                !Set(PFChapterHelper.readingOrderChapterNumbers(for: $0)).isDisjoint(with: wanted)
            }
            XCTAssertFalse(overlaps.isEmpty, "\(path.id) overlaps no course")
        }
    }
}
