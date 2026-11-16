// Phase3StudioTests.swift
// TrainingHub iOS - Phase 3 tests: the BA and PO Studio
// (StudioExercises.swift, StudioDraftStore.swift). Covers the
// deterministic rubric rules, the 15 task types, and
// account-namespaced draft storage. Model and store logic only;
// no view tests.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the implementation files before writing.
//
// The store base key below mirrors the private key constant in
// StudioDraftStore and must be kept in step with that file.

import XCTest
@testable import TrainingHub

@MainActor
final class Phase3StudioTests: XCTestCase {

    private let namespaceA = "test-studio-a"
    private let namespaceB = "test-studio-b"
    private let draftsBaseKey = "pf.studioDrafts.v1"

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        UserDefaults.standard.removeObject(forKey: draftsBaseKey)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: draftsBaseKey)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
        AccountScopedStorage.setCurrentNamespace(nil)
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A fixture exercise with known rubric settings: word guidance
    /// 10 to 20 words, two required sections, a criteria minimum
    /// of 3, and no Gherkin requirement.
    private func fixtureExercise() -> StudioExercise {
        StudioExercise(
            id: "test-fixture",
            title: "Test exercise",
            taskType: .acceptanceCriteria,
            sourceKind: .lesson,
            sourceID: "ch1s1",
            sourceTitle: "Test lesson",
            brief: "Write a test draft.",
            groundingNote: "Grounded in the test lesson.",
            requiredSections: [
                StudioRequiredSection(title: "Background", keywords: ["background", "context"]),
                StudioRequiredSection(title: "Requirements", keywords: ["requirement", "must"])
            ],
            workedExampleTitle: "Worked example: test",
            workedExampleBody: "An example for a different task.",
            suggestedMinimumWords: 10,
            suggestedMaximumWords: 20,
            minimumAcceptanceCriteria: 3,
            requiresGherkin: false
        )
    }

    private func gherkinExercise() -> StudioExercise {
        StudioExercise(
            id: "test-gherkin",
            title: "Test Gherkin exercise",
            taskType: .gherkinScenarios,
            sourceKind: .lesson,
            sourceID: "ch1s1",
            sourceTitle: "Test lesson",
            brief: "Write Gherkin scenarios.",
            groundingNote: "Grounded in the test lesson.",
            requiredSections: [
                StudioRequiredSection(title: "Scenarios", keywords: ["scenario"])
            ],
            workedExampleTitle: "Worked example: test",
            workedExampleBody: "An example for a different task.",
            suggestedMinimumWords: 5,
            suggestedMaximumWords: 100,
            minimumAcceptanceCriteria: nil,
            requiresGherkin: true
        )
    }

    /// A draft of exactly the requested word count, built from
    /// repeated filler words plus the given opening words.
    private func draftWithWordCount(_ count: Int, opening: String = "") -> String {
        let openingWords = opening.split(separator: " ").map(String.init)
        let fillerCount = max(0, count - openingWords.count)
        return (openingWords + Array(repeating: "filler", count: fillerCount)).joined(separator: " ")
    }

    // MARK: - Task types and catalogue

    func testAllFifteenTaskTypesPresent() {
        XCTAssertEqual(StudioTaskType.allCases.count, 15)
        let expected: [StudioTaskType] = [
            .businessRequirements, .brdFsd, .functionalSpecifications,
            .userStories, .acceptanceCriteria, .gherkinScenarios,
            .apiRequirements, .isoMessageMapping, .fieldValidation,
            .exceptionHandling, .reconciliation, .testScenarios,
            .impactAssessment, .stakeholderManagement,
            .nonFunctionalRequirements
        ]
        XCTAssertEqual(Set(StudioTaskType.allCases), Set(expected))
        let displayNames = StudioTaskType.allCases.map(\.displayName)
        XCTAssertEqual(Set(displayNames).count, displayNames.count)
        for type in StudioTaskType.allCases {
            XCTAssertFalse(type.displayName.isEmpty)
            XCTAssertFalse(type.systemImage.isEmpty)
            XCTAssertEqual(type.id, type.rawValue)
        }
    }

    func testExerciseCatalogueHasOneExercisePerTaskType() {
        XCTAssertEqual(StudioExercise.all.count, 15)
        XCTAssertEqual(Set(StudioExercise.all.map(\.taskType)), Set(StudioTaskType.allCases))
        let ids = StudioExercise.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryExerciseIsWellFormed() {
        for exercise in StudioExercise.all {
            XCTAssertFalse(exercise.title.isEmpty)
            XCTAssertFalse(exercise.sourceID.isEmpty)
            XCTAssertFalse(exercise.sourceTitle.isEmpty)
            XCTAssertFalse(exercise.brief.isEmpty)
            XCTAssertFalse(exercise.groundingNote.isEmpty)
            XCTAssertFalse(exercise.requiredSections.isEmpty, "\(exercise.id) has no required sections.")
            XCTAssertFalse(exercise.workedExampleTitle.isEmpty)
            XCTAssertFalse(exercise.workedExampleBody.isEmpty)
            XCTAssertGreaterThan(exercise.suggestedMinimumWords, 0)
            XCTAssertGreaterThan(exercise.suggestedMaximumWords, exercise.suggestedMinimumWords)
            for section in exercise.requiredSections {
                XCTAssertFalse(section.title.isEmpty)
                XCTAssertFalse(section.keywords.isEmpty, "\(exercise.id) section \(section.title) has no keywords.")
                for keyword in section.keywords {
                    XCTAssertFalse(keyword.isEmpty)
                }
            }
            XCTAssertEqual(
                exercise.wordCountGuidance,
                "Suggested \(exercise.suggestedMinimumWords) to \(exercise.suggestedMaximumWords) words."
            )
        }
    }

    func testSourceCitationsNameKindIDAndTitle() {
        let exercise = fixtureExercise()
        XCTAssertEqual(exercise.sourceCitation, "Chapter 1, Lesson 1: Test lesson")
        for exercise in StudioExercise.all {
            XCTAssertTrue(exercise.sourceCitation.contains(exercise.sourceTitle))
            switch exercise.sourceKind {
            case .lesson:
                // Book numbers only: the internal lesson id never shows.
                XCTAssertTrue(
                    exercise.sourceCitation.hasPrefix("Chapter "),
                    "Unexpected citation: \(exercise.sourceCitation)"
                )
                XCTAssertFalse(
                    exercise.sourceCitation.contains(exercise.sourceID),
                    "Raw lesson id in citation: \(exercise.sourceCitation)"
                )
            case .situation:
                XCTAssertTrue(exercise.sourceCitation.contains(exercise.sourceID))
                XCTAssertTrue(
                    exercise.sourceCitation.hasPrefix("Situation "),
                    "Unexpected citation: \(exercise.sourceCitation)"
                )
            }
        }
        XCTAssertEqual(StudioExerciseSource.lesson.displayName, "Lesson")
        XCTAssertEqual(StudioExerciseSource.situation.displayName, "Situation")
    }

    func testOnlyTheGherkinExerciseRequiresGherkin() {
        let gherkinExercises = StudioExercise.all.filter(\.requiresGherkin)
        XCTAssertEqual(gherkinExercises.count, 1)
        XCTAssertEqual(gherkinExercises.first?.taskType, .gherkinScenarios)
    }

    func testCriteriaMinimumExistsOnlyWhereTheCatalogueSetsIt() {
        let withCriteria = StudioExercise.all.filter { $0.minimumAcceptanceCriteria != nil }
        XCTAssertEqual(withCriteria.count, 2)
        XCTAssertEqual(
            StudioExercise.all.first { $0.taskType == .userStories }?.minimumAcceptanceCriteria,
            3
        )
        XCTAssertEqual(
            StudioExercise.all.first { $0.taskType == .acceptanceCriteria }?.minimumAcceptanceCriteria,
            4
        )
    }

    func testAIReviewPromptCarriesTitleBriefDraftAndNoRewriteInstruction() {
        let exercise = fixtureExercise()
        let prompt = exercise.aiReviewPrompt(draft: "My draft text.")
        XCTAssertTrue(prompt.contains("Test exercise"))
        XCTAssertTrue(prompt.contains("Acceptance criteria"))
        XCTAssertTrue(prompt.contains("Write a test draft."))
        XCTAssertTrue(prompt.contains("My draft text."))
        XCTAssertTrue(prompt.contains("Do not rewrite the draft for me."))
    }

    // MARK: - Word count

    func testWordCountCountsRunsOfNonWhitespace() {
        XCTAssertEqual(StudioRubricReview.wordCount(""), 0)
        XCTAssertEqual(StudioRubricReview.wordCount("   "), 0)
        XCTAssertEqual(StudioRubricReview.wordCount("one"), 1)
        XCTAssertEqual(StudioRubricReview.wordCount("one two three"), 3)
        XCTAssertEqual(StudioRubricReview.wordCount("one  two\nthree\ttab"), 4)
        XCTAssertEqual(StudioRubricReview.wordCount("  leading and trailing  "), 3)
    }

    func testWordCountCheckFollowsTheGuidanceBounds() {
        let exercise = fixtureExercise()
        let below = StudioRubricReview.checks(for: exercise, draft: draftWithWordCount(9))
        XCTAssertEqual(below.first?.id, "words")
        XCTAssertEqual(below.first?.passed, false)

        let atMinimum = StudioRubricReview.checks(for: exercise, draft: draftWithWordCount(10))
        XCTAssertEqual(atMinimum.first?.passed, true)
        XCTAssertTrue(atMinimum.first?.detail.contains("10 words") ?? false)

        // Above the suggested maximum still passes the word-count
        // check; the detail says the draft is above the maximum.
        // The check is guidance, not a failure.
        let above = StudioRubricReview.checks(for: exercise, draft: draftWithWordCount(25))
        XCTAssertEqual(above.first?.passed, true)
        XCTAssertTrue(above.first?.detail.contains("above the suggested maximum") ?? false)
        XCTAssertTrue(above.first?.detail.contains(exercise.wordCountGuidance) ?? false)
    }

    func testEmptyDraftReturnsOnlyTheWordCountCheckUnpassed() {
        let exercise = fixtureExercise()
        for empty in ["", "   ", "\n\n"] {
            let checks = StudioRubricReview.checks(for: exercise, draft: empty)
            XCTAssertEqual(checks.count, 1, "Empty draft must return only the word-count check.")
            XCTAssertEqual(checks.first?.id, "words")
            XCTAssertEqual(checks.first?.passed, false)
            XCTAssertTrue(checks.first?.detail.contains("No words yet.") ?? false)
        }
    }

    // MARK: - Section keyword checks

    func testSectionCheckPassesWhenAnyKeywordAppearsCaseInsensitively() {
        let exercise = fixtureExercise()
        let draft = draftWithWordCount(12, opening: "The BACKGROUND is clear and the requirement must hold.")
        let checks = StudioRubricReview.checks(for: exercise, draft: draft)
        let background = checks.first { $0.id == "section-Background" }
        let requirements = checks.first { $0.id == "section-Requirements" }
        XCTAssertEqual(background?.passed, true)
        XCTAssertEqual(requirements?.passed, true)
        XCTAssertTrue(background?.detail.contains("only checks that the section is mentioned") ?? false)
    }

    func testSectionCheckFailsWhenNoKeywordAppears() {
        let exercise = fixtureExercise()
        let draft = draftWithWordCount(12, opening: "A draft about payments and ledgers and nothing else here.")
        let checks = StudioRubricReview.checks(for: exercise, draft: draft)
        XCTAssertEqual(checks.first { $0.id == "section-Background" }?.passed, false)
        XCTAssertEqual(checks.first { $0.id == "section-Requirements" }?.passed, false)
        XCTAssertTrue(
            checks.first { $0.id == "section-Background" }?.detail.contains("Not found yet.") ?? false
        )
    }

    func testSectionMatchingIsSubstringMatchingAsDocumented() {
        // The review looks for a keyword substring in the lowercased
        // draft, so a section word inside a longer word still
        // matches. This locks the documented behaviour.
        let exercise = fixtureExercise()
        let draft = draftWithWordCount(12, opening: "The backgrounding notes mention a requiremental scope.")
        let checks = StudioRubricReview.checks(for: exercise, draft: draft)
        XCTAssertEqual(checks.first { $0.id == "section-Background" }?.passed, true)
        XCTAssertEqual(checks.first { $0.id == "section-Requirements" }?.passed, true)
    }

    // MARK: - Criteria counting rule

    func testCriteriaLineCountCountsBulletsNumbersAndACLines() {
        let text = """
            - first
            * second
            • third
            1. fourth
            2) fifth
            AC1 sixth
            AC 7 seventh
            AC: eighth
            """
        XCTAssertEqual(StudioRubricReview.criteriaLineCount(text), 8)
    }

    func testCriteriaLineCountIgnoresPlainLinesAndHeadings() {
        let text = """
            Plain sentence with no marker.
            1 item without punctuation after the number
            Acceptance criteria heading
            ACX not a numbered line
            """
        XCTAssertEqual(StudioRubricReview.criteriaLineCount(text), 0)
    }

    func testCriteriaLineCountIgnoresBlankLinesAndCountsIndentedLines() {
        let text = """
            - one

              - two indented
            """
        XCTAssertEqual(StudioRubricReview.criteriaLineCount(text), 2)
    }

    func testCriteriaCheckUsesTheExerciseMinimum() {
        let exercise = fixtureExercise()
        let passing = "- one\n- two\n- three\n" + draftWithWordCount(10)
        let passingChecks = StudioRubricReview.checks(for: exercise, draft: passing)
        let passingCriteria = passingChecks.first { $0.id == "criteria" }
        XCTAssertEqual(passingCriteria?.passed, true)
        XCTAssertTrue(passingCriteria?.detail.contains("Counted 3 list lines") ?? false)
        XCTAssertTrue(passingCriteria?.detail.contains("At least 3 expected") ?? false)

        let failing = "- one\n- two\n" + draftWithWordCount(10)
        let failingChecks = StudioRubricReview.checks(for: exercise, draft: failing)
        XCTAssertEqual(failingChecks.first { $0.id == "criteria" }?.passed, false)
    }

    func testNoCriteriaCheckWhenTheExerciseHasNoMinimum() {
        let exercise = gherkinExercise()
        let checks = StudioRubricReview.checks(for: exercise, draft: draftWithWordCount(10))
        XCTAssertNil(checks.first { $0.id == "criteria" })
    }

    // MARK: - Gherkin keyword checks

    func testContainsWordMatchesWholeWordsCaseInsensitively() {
        XCTAssertTrue(StudioRubricReview.containsWord("Given", in: "Given a payment"))
        XCTAssertTrue(StudioRubricReview.containsWord("Given", in: "GIVEN a payment"))
        XCTAssertTrue(StudioRubricReview.containsWord("Given", in: "First, Given, a payment"))
        XCTAssertFalse(StudioRubricReview.containsWord("Given", in: "The forgiven payment"))
        XCTAssertFalse(StudioRubricReview.containsWord("Then", in: "Something else"))
    }

    func testGherkinChecksRequireAllThreeKeywords() {
        let exercise = gherkinExercise()
        let complete = "Given a valid payment scenario When the bank processes it Then it settles."
        let completeChecks = StudioRubricReview.checks(for: exercise, draft: complete)
        XCTAssertEqual(completeChecks.first { $0.id == "gherkin-Given" }?.passed, true)
        XCTAssertEqual(completeChecks.first { $0.id == "gherkin-When" }?.passed, true)
        XCTAssertEqual(completeChecks.first { $0.id == "gherkin-Then" }?.passed, true)

        let partial = "Given a valid payment scenario, the payment settles."
        let partialChecks = StudioRubricReview.checks(for: exercise, draft: partial)
        XCTAssertEqual(partialChecks.first { $0.id == "gherkin-Given" }?.passed, true)
        XCTAssertEqual(partialChecks.first { $0.id == "gherkin-When" }?.passed, false)
        XCTAssertEqual(partialChecks.first { $0.id == "gherkin-Then" }?.passed, false)

        // "forgiven" must not satisfy the Given check: whole-word
        // matching only.
        let forgiven = "The forgiven payment scenario was reviewed when it failed."
        let forgivenChecks = StudioRubricReview.checks(for: exercise, draft: forgiven)
        XCTAssertEqual(forgivenChecks.first { $0.id == "gherkin-Given" }?.passed, false)
    }

    func testNoGherkinChecksWhenTheExerciseDoesNotRequireThem() {
        let exercise = fixtureExercise()
        let checks = StudioRubricReview.checks(for: exercise, draft: "Given When Then " + draftWithWordCount(10))
        XCTAssertNil(checks.first { $0.id == "gherkin-Given" })
        XCTAssertNil(checks.first { $0.id == "gherkin-When" })
        XCTAssertNil(checks.first { $0.id == "gherkin-Then" })
    }

    func testCheckOrderIsWordsThenSectionsThenCriteriaThenGherkin() {
        let exercise = fixtureExercise()
        let ids = StudioRubricReview.checks(for: exercise, draft: draftWithWordCount(12)).map(\.id)
        XCTAssertEqual(ids, ["words", "section-Background", "section-Requirements", "criteria"])
    }

    // MARK: - Draft model

    func testStudioDraftWordCountAndAIReviewFlag() {
        var draft = StudioDraft(exerciseID: "test-fixture", text: "one two three")
        XCTAssertEqual(draft.wordCount, 3)
        XCTAssertFalse(draft.hasRequestedAIReview)
        draft.aiReviewRequestedAt = Date()
        XCTAssertTrue(draft.hasRequestedAIReview)
    }

    // MARK: - Draft store namespacing

    func testDraftStoreKeysAreAccountNamespaced() {
        let store = StudioDraftStore()
        store.saveDraft(exerciseID: "studio-business-requirements", text: "A draft.", completedSections: [])
        XCTAssertTrue(store.hasDraft(for: "studio-business-requirements"))
        XCTAssertNotNil(
            UserDefaults.standard.data(forKey: AccountScopedStorage.key(draftsBaseKey, namespace: namespaceA)),
            "Drafts must be stored under the current account namespace."
        )
        XCTAssertNil(
            UserDefaults.standard.object(forKey: draftsBaseKey),
            "Drafts must never be stored under the bare, unnamespaced key."
        )
        XCTAssertNil(
            UserDefaults.standard.object(forKey: AccountScopedStorage.key(draftsBaseKey, namespace: namespaceB)),
            "Drafts must not leak into another namespace."
        )
    }

    func testEmptyDraftCreatesNothing() {
        let store = StudioDraftStore()
        store.saveDraft(exerciseID: "studio-business-requirements", text: "   ", completedSections: [])
        XCTAssertFalse(store.hasDraft(for: "studio-business-requirements"))
        XCTAssertTrue(store.drafts.isEmpty)
    }

    func testSaveDraftCreatesAndUpdatesOneDraftPerExercise() {
        let store = StudioDraftStore()
        store.saveDraft(exerciseID: "studio-business-requirements", text: "First version.", completedSections: ["Background"])
        store.saveDraft(exerciseID: "studio-business-requirements", text: "Second version.", completedSections: ["Background", "Requirements"])
        XCTAssertEqual(store.drafts.count, 1)
        XCTAssertEqual(store.draft(for: "studio-business-requirements")?.text, "Second version.")
        XCTAssertEqual(store.draft(for: "studio-business-requirements")?.completedSections, ["Background", "Requirements"])
    }

    func testDeleteDraftRemovesOnlyThatExercise() {
        let store = StudioDraftStore()
        store.saveDraft(exerciseID: "studio-business-requirements", text: "One.", completedSections: [])
        store.saveDraft(exerciseID: "studio-brd-fsd", text: "Two.", completedSections: [])
        store.deleteDraft(for: "studio-business-requirements")
        XCTAssertFalse(store.hasDraft(for: "studio-business-requirements"))
        XCTAssertTrue(store.hasDraft(for: "studio-brd-fsd"))
        XCTAssertEqual(store.drafts.count, 1)
    }

    func testMarkAIReviewRequestedFlagsTheDraft() {
        let store = StudioDraftStore()
        store.saveDraft(exerciseID: "studio-business-requirements", text: "A draft.", completedSections: [])
        XCTAssertFalse(store.draft(for: "studio-business-requirements")?.hasRequestedAIReview ?? true)
        store.markAIReviewRequested(exerciseID: "studio-business-requirements", text: "A draft.", completedSections: [])
        XCTAssertTrue(store.draft(for: "studio-business-requirements")?.hasRequestedAIReview ?? false)
    }

    func testReloadForCurrentAccountClearsInMemoryState() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let store = StudioDraftStore()
        store.saveDraft(exerciseID: "studio-business-requirements", text: "A draft.", completedSections: [])
        XCTAssertEqual(store.drafts.count, 1)

        AccountScopedStorage.setCurrentNamespace(namespaceB)
        store.reloadForCurrentAccount()
        XCTAssertTrue(store.drafts.isEmpty, "Reloading for a new namespace must clear the previous account's drafts from memory.")

        AccountScopedStorage.setCurrentNamespace(namespaceA)
        store.reloadForCurrentAccount()
        XCTAssertEqual(store.drafts.count, 1)
        XCTAssertEqual(store.draft(for: "studio-business-requirements")?.text, "A draft.")
    }

    func testDraftStoreDoesNotLeakAcrossNamespaces() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let firstStore = StudioDraftStore()
        firstStore.saveDraft(exerciseID: "studio-business-requirements", text: "A draft.", completedSections: [])

        AccountScopedStorage.setCurrentNamespace(namespaceB)
        let secondStore = StudioDraftStore()
        XCTAssertTrue(secondStore.drafts.isEmpty, "The second namespace must not see the first namespace's drafts.")
    }
}

// MARK: - Teaching content tests (Studio rebuild, 13 Nov 2026;
// coverage expansion, 13 Nov 2026: key concepts and individual
// competencies added, counts and ordering updated to match.)
//
// Covers the BABOK-based teaching model added in the rebuild:
// StudioLevel, StudioLessonKind, StudioKnowledgeArea,
// StudioLesson catalogues, StudioDisclaimer, and
// StudioCareerGuide. Model logic only; no view tests.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the implementation files before writing.

@MainActor
final class StudioTeachingTests: XCTestCase {

    private let namespaceA = "test-studio-teaching-a"
    private let namespaceB = "test-studio-teaching-b"
    private let draftsBaseKey = "pf.studioDrafts.v1"

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        UserDefaults.standard.removeObject(forKey: draftsBaseKey)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: draftsBaseKey)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
        AccountScopedStorage.setCurrentNamespace(nil)
        super.tearDown()
    }

    // MARK: - Levels

    func testThreeLevelsInOrderWithDistinctNames() {
        XCTAssertEqual(StudioLevel.allCases, [.foundation, .practitioner, .advanced])
        XCTAssertEqual(StudioLevel.foundation.rawValue, 1)
        XCTAssertEqual(StudioLevel.practitioner.rawValue, 2)
        XCTAssertEqual(StudioLevel.advanced.rawValue, 3)
        XCTAssertEqual(StudioLevel.foundation.displayName, "Level 1: Foundations")
        XCTAssertEqual(StudioLevel.practitioner.displayName, "Level 2: Practitioner")
        XCTAssertEqual(StudioLevel.advanced.displayName, "Level 3: Advanced")
        for level in StudioLevel.allCases {
            XCTAssertFalse(level.shortName.isEmpty)
            XCTAssertFalse(level.blurb.isEmpty)
            XCTAssertFalse(level.systemImage.isEmpty)
            XCTAssertEqual(level.id, level.rawValue)
        }
    }

    func testLessonKindsHaveDistinctNamesAndImages() {
        XCTAssertEqual(StudioLessonKind.allCases.count, 6)
        let names = StudioLessonKind.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        for kind in StudioLessonKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertFalse(kind.systemImage.isEmpty)
        }
        XCTAssertLessThan(StudioLessonKind.concept.sortOrder, StudioLessonKind.task.sortOrder)
        XCTAssertLessThan(StudioLessonKind.task.sortOrder, StudioLessonKind.technique.sortOrder)
        XCTAssertLessThan(StudioLessonKind.technique.sortOrder, StudioLessonKind.competency.sortOrder)
        XCTAssertLessThan(StudioLessonKind.competency.sortOrder, StudioLessonKind.perspective.sortOrder)
        XCTAssertLessThan(StudioLessonKind.perspective.sortOrder, StudioLessonKind.orientation.sortOrder)
    }

    // MARK: - Knowledge areas and tasks

    func testSixKnowledgeAreasInBabokOrder() {
        XCTAssertEqual(StudioKnowledgeArea.allCases.count, 6)
        XCTAssertEqual(
            StudioKnowledgeArea.allCases.map(\.displayName),
            [
                "Business Analysis Planning and Monitoring",
                "Elicitation and Collaboration",
                "Requirements Life Cycle Management",
                "Strategy Analysis",
                "Requirements Analysis and Design Definition",
                "Solution Evaluation"
            ]
        )
        for area in StudioKnowledgeArea.allCases {
            XCTAssertEqual(area.introduction.count, 2, "\(area.displayName) must have two introduction paragraphs.")
            for paragraph in area.introduction {
                XCTAssertFalse(paragraph.isEmpty)
            }
        }
    }

    func testAllThirtyTasksPresentWithExactNames() {
        XCTAssertEqual(StudioLesson.tasks.count, 30)
        XCTAssertEqual(
            Set(StudioLesson.tasks.map(\.title)),
            Set([
                "Plan Business Analysis Approach",
                "Plan Stakeholder Engagement",
                "Plan Business Analysis Governance",
                "Plan Business Analysis Information Management",
                "Identify Business Analysis Performance Improvements",
                "Prepare for Elicitation",
                "Conduct Elicitation",
                "Confirm Elicitation Results",
                "Communicate Business Analysis Information",
                "Manage Stakeholder Collaboration",
                "Trace Requirements",
                "Maintain Requirements",
                "Prioritize Requirements",
                "Assess Requirements Changes",
                "Approve Requirements",
                "Analyze Current State",
                "Define Future State",
                "Assess Risks",
                "Define Change Strategy",
                "Specify and Model Requirements",
                "Verify Requirements",
                "Validate Requirements",
                "Define Requirements Architecture",
                "Define Design Options",
                "Analyze Potential Value and Recommend Solution",
                "Measure Solution Performance",
                "Analyze Performance Measures",
                "Assess Solution Limitations",
                "Assess Enterprise Limitations",
                "Recommend Actions to Increase Solution Value"
            ])
        )
        for lesson in StudioLesson.tasks {
            XCTAssertEqual(lesson.kind, .task)
            XCTAssertNotNil(lesson.knowledgeArea, "\(lesson.title) must belong to a knowledge area.")
            XCTAssertNotNil(lesson.babokReference, "\(lesson.title) must carry a BABOK reference.")
        }
    }

    func testTaskCountsPerKnowledgeArea() {
        XCTAssertEqual(StudioLesson.tasks(for: .planning).count, 5)
        XCTAssertEqual(StudioLesson.tasks(for: .elicitation).count, 5)
        XCTAssertEqual(StudioLesson.tasks(for: .lifecycle).count, 5)
        XCTAssertEqual(StudioLesson.tasks(for: .strategy).count, 4)
        XCTAssertEqual(StudioLesson.tasks(for: .analysisDesign).count, 6)
        XCTAssertEqual(StudioLesson.tasks(for: .solutionEvaluation).count, 5)
    }

    // MARK: - Techniques, competencies, perspectives

    func testAllFiftyTechniquesPresentWithExactNames() {
        XCTAssertEqual(StudioLesson.techniques.count, 50)
        XCTAssertEqual(
            StudioLesson.techniques.map(\.title),
            [
                "Acceptance and Evaluation Criteria",
                "Backlog Management",
                "Balanced Scorecard",
                "Benchmarking and Market Analysis",
                "Brainstorming",
                "Business Capability Analysis",
                "Business Cases",
                "Business Model Canvas",
                "Business Rules Analysis",
                "Collaborative Games",
                "Concept Modelling",
                "Data Dictionary",
                "Data Flow Diagrams",
                "Data Mining",
                "Data Modelling",
                "Decision Analysis",
                "Decision Modelling",
                "Document Analysis",
                "Estimation",
                "Financial Analysis",
                "Focus Groups",
                "Functional Decomposition",
                "Glossary",
                "Interface Analysis",
                "Interviews",
                "Item Tracking",
                "Lessons Learned",
                "Metrics and Key Performance Indicators (KPIs)",
                "Mind Mapping",
                "Non-Functional Requirements Analysis",
                "Observation",
                "Organizational Modelling",
                "Prioritization",
                "Process Analysis",
                "Process Modelling",
                "Prototyping",
                "Reviews",
                "Risk Analysis and Management",
                "Roles and Permissions Matrix",
                "Root Cause Analysis",
                "Scope Modelling",
                "Sequence Diagrams",
                "Stakeholder List, Map, or Personas",
                "State Modelling",
                "Survey or Questionnaire",
                "SWOT Analysis",
                "Use Cases and Scenarios",
                "User Stories",
                "Vendor Assessment",
                "Workshops"
            ]
        )
        for (index, lesson) in StudioLesson.techniques.enumerated() {
            XCTAssertEqual(lesson.kind, .technique)
            XCTAssertNil(lesson.knowledgeArea)
            XCTAssertEqual(lesson.babokReference, "10.\(index + 1)", "\(lesson.title) must carry its chapter reference.")
        }
    }

    func testAllSixCompetencyGroupsPresent() {
        XCTAssertEqual(StudioLesson.competencies.count, 6)
        XCTAssertEqual(
            StudioLesson.competencies.map(\.title),
            [
                "Analytical Thinking and Problem Solving",
                "Behavioural Characteristics",
                "Business Knowledge",
                "Communication Skills",
                "Interaction Skills",
                "Tools and Technology"
            ]
        )
        for (index, lesson) in StudioLesson.competencies.enumerated() {
            XCTAssertEqual(lesson.kind, .competency)
            XCTAssertEqual(lesson.babokReference, "9.\(index + 1)")
        }
    }

    func testAllTwentyNineIndividualCompetenciesPresent() {
        XCTAssertEqual(StudioLesson.individualCompetencies.count, 29)
        XCTAssertEqual(
            StudioLesson.individualCompetencies.map(\.title),
            [
                "Creative Thinking",
                "Decision Making",
                "Learning",
                "Problem Solving",
                "Systems Thinking",
                "Conceptual Thinking",
                "Visual Thinking",
                "Ethics",
                "Personal Accountability",
                "Trustworthiness",
                "Organization and Time Management",
                "Adaptability",
                "Business Acumen",
                "Industry Knowledge",
                "Organization Knowledge",
                "Solution Knowledge",
                "Methodology Knowledge",
                "Verbal Communication",
                "Non-Verbal Communication",
                "Written Communication",
                "Listening",
                "Facilitation",
                "Leadership and Influencing",
                "Teamwork",
                "Negotiation and Conflict Resolution",
                "Teaching",
                "Office Productivity Tools and Technology",
                "Business Analysis Tools and Technology",
                "Communication Tools and Technology"
            ]
        )
        XCTAssertEqual(
            StudioLesson.individualCompetencies.map(\.babokReference),
            [
                "9.1.1", "9.1.2", "9.1.3", "9.1.4", "9.1.5", "9.1.6", "9.1.7",
                "9.2.1", "9.2.2", "9.2.3", "9.2.4", "9.2.5",
                "9.3.1", "9.3.2", "9.3.3", "9.3.4", "9.3.5",
                "9.4.1", "9.4.2", "9.4.3", "9.4.4",
                "9.5.1", "9.5.2", "9.5.3", "9.5.4", "9.5.5",
                "9.6.1", "9.6.2", "9.6.3"
            ]
        )
        // Each individual unit names its parent group in its
        // subtitle and carries the same level as its parent
        // group unit, so group and individuals sit together.
        let groupByPrefix: [String: String] = [
            "9.1": "Analytical Thinking and Problem Solving",
            "9.2": "Behavioural Characteristics",
            "9.3": "Business Knowledge",
            "9.4": "Communication Skills",
            "9.5": "Interaction Skills",
            "9.6": "Tools and Technology"
        ]
        for lesson in StudioLesson.individualCompetencies {
            XCTAssertEqual(lesson.kind, .competency)
            XCTAssertNil(lesson.knowledgeArea)
            let prefix = String(lesson.babokReference?.prefix(3) ?? "")
            let groupTitle = groupByPrefix[prefix] ?? ""
            XCTAssertTrue(
                lesson.subtitle.hasPrefix(groupTitle),
                "\(lesson.title) must name its parent group \(groupTitle) in its subtitle."
            )
            let group = StudioLesson.competencies.first { $0.babokReference == prefix }
            XCTAssertNotNil(group, "No group unit for prefix \(prefix).")
            XCTAssertEqual(
                lesson.level, group?.level,
                "\(lesson.title) must carry the same level as its parent group."
            )
        }
    }

    func testCompetencyGroupsPrecedeTheirIndividualUnits() {
        let all = StudioLesson.all
        for group in StudioLesson.competencies {
            guard let groupIndex = all.firstIndex(of: group) else {
                XCTFail("Group unit \(group.title) missing from StudioLesson.all.")
                continue
            }
            let individuals = StudioLesson.individualCompetencies.filter {
                $0.subtitle.hasPrefix(group.title)
            }
            XCTAssertFalse(individuals.isEmpty, "\(group.title) must have individual units.")
            for individual in individuals {
                guard let individualIndex = all.firstIndex(of: individual) else {
                    XCTFail("Individual unit \(individual.title) missing from StudioLesson.all.")
                    continue
                }
                XCTAssertLessThan(
                    groupIndex, individualIndex,
                    "\(group.title) must precede \(individual.title) in learning order."
                )
            }
        }
    }

    func testAllFivePerspectivesPresentIncludingAgile() {
        XCTAssertEqual(StudioLesson.perspectives.count, 5)
        XCTAssertEqual(
            StudioLesson.perspectives.map(\.title),
            [
                "Agile Perspective",
                "Business Intelligence Perspective",
                "Information Technology Perspective",
                "Business Architecture Perspective",
                "Business Process Management Perspective"
            ]
        )
        XCTAssertEqual(StudioLesson.perspectives.first?.title, "Agile Perspective")
        for lesson in StudioLesson.perspectives {
            XCTAssertEqual(lesson.kind, .perspective)
            XCTAssertNotNil(lesson.babokReference)
        }
    }

    func testOrientationLessonsPresentWithoutBabokReferences() {
        XCTAssertEqual(StudioLesson.orientations.count, 2)
        XCTAssertEqual(
            StudioLesson.orientations.map(\.title),
            ["Choosing the Right Technique", "Techniques for the Wider Picture"]
        )
        for lesson in StudioLesson.orientations {
            XCTAssertEqual(lesson.kind, .orientation)
            XCTAssertNil(lesson.babokReference, "Orientation lessons teach choosing techniques, not one BABOK item.")
        }
    }

    func testAllThirtyFourKeyConceptsPresentInChapterOrder() {
        XCTAssertEqual(StudioLesson.keyConcepts.count, 34)
        XCTAssertEqual(
            StudioLesson.keyConcepts.map(\.title),
            [
                "The Business Analysis Core Concept Model (BACCM)",
                "Change",
                "Need",
                "Solution",
                "Stakeholder",
                "Value",
                "Context",
                "Business Analysis",
                "Business Analysis Information",
                "Design",
                "Enterprise",
                "Organization",
                "Plan",
                "Requirement",
                "Risk",
                "Requirements Classification Schema",
                "Business Requirements",
                "Stakeholder Requirements",
                "Functional Requirements",
                "Non-Functional Requirements",
                "Transition Requirements",
                "Stakeholders",
                "Business Analyst",
                "Customer",
                "Domain Subject Matter Expert",
                "End User",
                "Implementation Subject Matter Expert",
                "Operational Support",
                "Project Manager",
                "Regulator",
                "Sponsor",
                "Supplier",
                "Tester",
                "Requirements and Designs"
            ]
        )
        let expectedReferences: [String?] = [
            "2.1", "2.1", "2.1", "2.1", "2.1", "2.1", "2.1",
            "2.2", "2.2", "2.2", "2.2", "2.2", "2.2", "2.2", "2.2",
            "2.3", "2.3", "2.3", "2.3", "2.3", "2.3",
            "2.4", "2.4", "2.4", "2.4", "2.4", "2.4", "2.4", "2.4", "2.4", "2.4", "2.4", "2.4",
            "2.5"
        ]
        XCTAssertEqual(StudioLesson.keyConcepts.map(\.babokReference), expectedReferences)
        for lesson in StudioLesson.keyConcepts {
            XCTAssertEqual(lesson.kind, .concept)
            XCTAssertEqual(lesson.level, .foundation, "\(lesson.title) must be a Level 1 unit.")
            XCTAssertNil(lesson.knowledgeArea)
            XCTAssertNotNil(lesson.babokReference)
        }
        // Concepts open Level 1: every concept precedes every
        // task in learning order.
        let all = StudioLesson.all
        let lastConceptIndex = all.lastIndex { $0.kind == .concept } ?? -1
        let firstTaskIndex = all.firstIndex { $0.kind == .task } ?? all.count
        XCTAssertLessThan(lastConceptIndex, firstTaskIndex)
    }

    // MARK: - Level ordering and counts

    func testAllLessonsTotalOneHundredFiftySix() {
        XCTAssertEqual(StudioLesson.all.count, 156)
        let ids = StudioLesson.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Lesson ids must be unique.")
    }

    func testAllLessonsOrderedLevelOneThenTwoThenThree() {
        let levels = StudioLesson.all.map(\.level.rawValue)
        XCTAssertEqual(levels, levels.sorted(), "StudioLesson.all must present Level 1, then Level 2, then Level 3.")
        XCTAssertEqual(StudioLesson.lessons(for: .foundation).count, 72)
        XCTAssertEqual(StudioLesson.lessons(for: .practitioner).count, 44)
        XCTAssertEqual(StudioLesson.lessons(for: .advanced).count, 40)
    }

    func testKindOrderWithinEachLevel() {
        for level in StudioLevel.allCases {
            let orders = StudioLesson.lessons(for: level).map(\.kind.sortOrder)
            XCTAssertEqual(orders, orders.sorted(), "\(level.displayName) must order concepts, tasks, techniques, competencies, perspectives, then orientation.")
        }
    }

    // MARK: - Lesson shape: teaching, then practice

    func testEveryLessonTeachesWhatHowAndOneWorkedExample() {
        for lesson in StudioLesson.all {
            XCTAssertFalse(lesson.title.isEmpty, "\(lesson.id) has no title.")
            XCTAssertFalse(lesson.subtitle.isEmpty, "\(lesson.id) has no subtitle.")
            XCTAssertGreaterThanOrEqual(lesson.explanation.count, 2, "\(lesson.id) must explain what the item is in at least two paragraphs.")
            XCTAssertFalse(lesson.outputName.isEmpty, "\(lesson.id) must name the output it teaches.")
            XCTAssertGreaterThanOrEqual(lesson.outputStructure.count, 3, "\(lesson.id) must show the output structure in at least three sections.")
            XCTAssertGreaterThanOrEqual(lesson.howToWrite.count, 1, "\(lesson.id) must teach how to write the output.")
            XCTAssertFalse(lesson.workedExampleTitle.isEmpty, "\(lesson.id) must have a worked example title.")
            XCTAssertGreaterThanOrEqual(lesson.workedExample.count, 2, "\(lesson.id) must carry one worked example in at least two paragraphs.")
            XCTAssertGreaterThan(lesson.suggestedMinimumWords, 0)
            XCTAssertGreaterThan(lesson.suggestedMaximumWords, lesson.suggestedMinimumWords)
            for section in lesson.outputStructure {
                XCTAssertFalse(section.title.isEmpty)
                XCTAssertFalse(section.guidance.isEmpty)
            }
        }
    }

    func testEveryParagraphIsNonEmptyAndNotAWallOfText() {
        for lesson in StudioLesson.all {
            for paragraph in lesson.explanation + lesson.howToWrite + lesson.workedExample {
                XCTAssertFalse(paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(lesson.id) has an empty paragraph.")
                XCTAssertLessThan(paragraph.count, 1500, "\(lesson.id) has a paragraph over 1500 characters; paragraphs must stay to one idea.")
                XCTAssertFalse(paragraph.contains("\n\n"), "\(lesson.id) paragraph contains a paragraph break; content must be split into paragraph strings.")
            }
        }
    }

    func testEveryTaskHasSupportingPracticeAfterTheTeaching() {
        for lesson in StudioLesson.tasks {
            XCTAssertFalse(lesson.practiceScenarios.isEmpty, "\(lesson.title) must carry practice scenarios.")
            XCTAssertFalse(lesson.practiceQuestions.isEmpty, "\(lesson.title) must carry practice questions.")
            for scenario in lesson.practiceScenarios {
                XCTAssertFalse(scenario.title.isEmpty)
                XCTAssertFalse(scenario.takeaway.isEmpty)
                XCTAssertFalse(scenario.story.isEmpty, "\(scenario.id) must carry its story as paragraphs.")
            }
            for question in lesson.practiceQuestions {
                XCTAssertFalse(question.question.isEmpty)
            }
        }
        let scenarioIDs = StudioLesson.all.flatMap(\.practiceScenarios).map(\.id)
        XCTAssertEqual(Set(scenarioIDs).count, scenarioIDs.count, "Practice scenario ids must be unique.")
        XCTAssertEqual(scenarioIDs.count, 120, "All 120 staged scenarios must be ported as practice.")
    }

    func testLinkedExerciseIDsResolveToRealExercises() {
        let exerciseIDs = Set(StudioExercise.all.map(\.id))
        for lesson in StudioLesson.all {
            for exerciseID in lesson.linkedExerciseIDs {
                XCTAssertTrue(exerciseIDs.contains(exerciseID), "\(lesson.id) links to unknown exercise \(exerciseID).")
            }
        }
    }

    func testLessonAIReviewPromptCarriesTitleOutputDraftAndNoRewriteInstruction() {
        let lesson = StudioLesson.tasks.first!
        let prompt = lesson.aiReviewPrompt(draft: "My draft text.")
        XCTAssertTrue(prompt.contains(lesson.title))
        XCTAssertTrue(prompt.contains(lesson.outputName))
        XCTAssertTrue(prompt.contains("My draft text."))
        XCTAssertTrue(prompt.contains("Do not rewrite the draft for me."))
    }

    // MARK: - Disclaimer and text rules

    func testDisclaimerStatesNoIIBAEndorsementAndOriginalAuthorship() {
        XCTAssertTrue(StudioDisclaimer.text.contains("not affiliated with, sponsored, or endorsed by IIBA"))
        XCTAssertTrue(StudioDisclaimer.text.contains("original Payments Training Hub authorship"))
        XCTAssertTrue(StudioDisclaimer.text.contains("BABOK"))
    }

    func testNoEmDashInAnyTeachingOrGuideText() {
        for lesson in StudioLesson.all {
            var texts = [lesson.title, lesson.subtitle, lesson.outputName, lesson.workedExampleTitle]
            texts += lesson.explanation + lesson.howToWrite + lesson.workedExample + lesson.keyPoints
            texts += lesson.outputStructure.flatMap { [$0.title, $0.guidance] }
            texts += lesson.practiceScenarios.flatMap { [$0.title, $0.takeaway] + $0.story }
            texts += lesson.practiceQuestions.flatMap { [$0.question] + $0.answer }
            for text in texts {
                XCTAssertFalse(text.contains("\u{2014}"), "Em dash in \(lesson.id): \(text.prefix(60))")
                XCTAssertFalse(text.contains("\u{2013}"), "En dash in \(lesson.id): \(text.prefix(60))")
            }
        }
        for guide in StudioCareerGuide.all {
            var texts = [guide.title, guide.audience, guide.timeframe]
            texts += guide.description + guide.skills + guide.tools + guide.portfolio + guide.mistakes
            texts += guide.sections.flatMap { [$0.heading] + $0.paragraphs + $0.keyPoints }
            texts += guide.sections.flatMap(\.steps).flatMap { [$0.title, $0.action, $0.timeframe] }
            texts += guide.certifications.flatMap { [$0.name, $0.body, $0.note] }
            for text in texts {
                XCTAssertFalse(text.contains("\u{2014}"), "Em dash in guide \(guide.id).")
                XCTAssertFalse(text.contains("\u{2013}"), "En dash in guide \(guide.id).")
            }
        }
        XCTAssertFalse(StudioDisclaimer.text.contains("\u{2014}"))
        XCTAssertFalse(StudioCareerGuide.certificationNote.contains("\u{2014}"))
    }

    // MARK: - Career guides

    func testAllFiveCareerGuidesPresentAndWellFormed() {
        XCTAssertEqual(StudioCareerGuide.all.count, 5)
        XCTAssertEqual(
            StudioCareerGuide.all.map(\.title),
            [
                "How to Become a Business Analyst",
                "How to Become a Payments and Banking BA",
                "How to Become a Product Owner",
                "How to Become a Product Manager",
                "How to Become a Successful Business Analyst"
            ]
        )
        for guide in StudioCareerGuide.all {
            XCTAssertFalse(guide.description.isEmpty)
            XCTAssertFalse(guide.audience.isEmpty)
            XCTAssertEqual(guide.sections.count, 6, "\(guide.id) must have six sections.")
            XCTAssertFalse(guide.skills.isEmpty)
            XCTAssertFalse(guide.tools.isEmpty)
            XCTAssertFalse(guide.certifications.isEmpty)
            XCTAssertFalse(guide.portfolio.isEmpty)
            XCTAssertFalse(guide.mistakes.isEmpty)
            for section in guide.sections {
                XCTAssertFalse(section.heading.isEmpty)
                XCTAssertFalse(section.paragraphs.isEmpty, "\(guide.id) section \(section.heading) must carry paragraphs.")
                XCTAssertFalse(section.steps.isEmpty)
                for step in section.steps {
                    XCTAssertFalse(step.title.isEmpty)
                    XCTAssertFalse(step.action.isEmpty)
                }
            }
        }
        XCTAssertTrue(StudioCareerGuide.certificationNote.contains("not affiliated with, sponsored, or endorsed by"))
    }

    // MARK: - Lesson drafts share the draft store

    func testLessonDraftRoundTripThroughTheSameStore() {
        let lessonID = StudioLesson.tasks.first!.id
        let store = StudioDraftStore()
        store.saveDraft(exerciseID: lessonID, text: "My lesson draft.", completedSections: ["Change summary"])
        XCTAssertTrue(store.hasDraft(for: lessonID))
        XCTAssertEqual(store.draft(for: lessonID)?.text, "My lesson draft.")
        XCTAssertEqual(store.draft(for: lessonID)?.completedSections, ["Change summary"])
        XCTAssertNotNil(
            UserDefaults.standard.data(forKey: AccountScopedStorage.key(draftsBaseKey, namespace: namespaceA)),
            "Lesson drafts must be stored under the current account namespace."
        )
        store.deleteDraft(for: lessonID)
        XCTAssertFalse(store.hasDraft(for: lessonID))
    }

    func testLessonDraftDoesNotLeakAcrossNamespaces() {
        let lessonID = StudioLesson.tasks.first!.id
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let firstStore = StudioDraftStore()
        firstStore.saveDraft(exerciseID: lessonID, text: "A draft.", completedSections: [])

        AccountScopedStorage.setCurrentNamespace(namespaceB)
        let secondStore = StudioDraftStore()
        XCTAssertTrue(secondStore.drafts.isEmpty, "The second namespace must not see the first namespace's lesson drafts.")
    }
}
