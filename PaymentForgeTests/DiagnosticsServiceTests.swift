// DiagnosticsServiceTests.swift
// PaymentForge iOS - Phase 7 unit tests: crash diagnostics and
// privacy-conscious analytics. The rules under test: events are
// capped, no personal data is ever stored (emails and tokens are
// scrubbed), analytics are off by default and record anonymous
// counts only, and nothing in the export can identify a learner.

import XCTest
@testable import PaymentForge

final class DiagnosticsServiceTests: XCTestCase {

    private var service: DiagnosticsService!

    override func setUp() {
        super.setUp()
        service = DiagnosticsService()
        service.clearAll()
        service.isAnalyticsEnabled = false
    }

    override func tearDown() {
        service.clearAll()
        service.isAnalyticsEnabled = false
        service = nil
        super.tearDown()
    }

    func testAnalyticsAreOffByDefault() {
        XCTAssertFalse(service.isAnalyticsEnabled)
        service.recordAnonymousCount("lessons_completed")
        XCTAssertTrue(service.anonymousCounts.isEmpty, "Counts must not be recorded while analytics are off.")
    }

    func testAnonymousCountsAreCountsOnly() {
        service.isAnalyticsEnabled = true
        service.recordAnonymousCount("lessons_completed")
        service.recordAnonymousCount("lessons_completed")
        service.recordAnonymousCount("practice_attempts")
        XCTAssertEqual(service.anonymousCounts["lessons_completed"], 2)
        XCTAssertEqual(service.anonymousCounts["practice_attempts"], 1)
    }

    func testDiagnosticEventsAreRecordedOnError() {
        service.recordNetworkFailure(operation: "supabase.request", detail: "failed after 3 attempts")
        service.recordError(operation: "lesson.load", detail: "bad response")
        XCTAssertEqual(service.eventCount, 2)
        XCTAssertEqual(service.events.first?.operation, "supabase.request")
        XCTAssertEqual(service.events.first?.kind, .networkFailure)
        XCTAssertEqual(service.events.last?.kind, .error)
    }

    func testEventsAreCappedAtOneHundred() {
        for i in 0..<120 {
            service.recordError(operation: "test.op", detail: "event \(i)")
        }
        XCTAssertEqual(service.eventCount, DiagnosticsService.maxStoredEvents)
        XCTAssertEqual(service.events.last?.detail, "event 119", "The newest event is kept.")
        XCTAssertEqual(service.events.first?.detail, "event 20", "The oldest 20 were dropped.")
    }

    func testSanitizeRemovesEmailAddresses() {
        let scrubbed = DiagnosticsService.sanitize("failed for learner@example.com on login")
        XCTAssertFalse(scrubbed.contains("learner@example.com"))
        XCTAssertTrue(scrubbed.contains("[redacted]"))
    }

    func testSanitizeRemovesBearerTokens() {
        let scrubbed = DiagnosticsService.sanitize("Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789")
        XCTAssertFalse(scrubbed.contains("Bearer abc"))
        XCTAssertTrue(scrubbed.contains("[redacted]"))
    }

    func testSanitizeRemovesLongTokenLikeRuns() {
        let token = String(repeating: "a", count: 50)
        let scrubbed = DiagnosticsService.sanitize("key=\(token)")
        XCTAssertFalse(scrubbed.contains(token))
    }

    func testRecordedEventsNeverContainPersonalData() {
        service.recordError(operation: "auth", detail: "failed for learner@example.com")
        let stored = service.events.first
        XCTAssertNotNil(stored)
        XCTAssertFalse(stored!.detail.contains("learner@example.com"))
        XCTAssertFalse(stored!.operation.contains("@"))
    }

    func testExportContainsCountsAndEventsButNoPersonalData() {
        service.isAnalyticsEnabled = true
        service.recordAnonymousCount("lessons_completed")
        service.recordNetworkFailure(operation: "content.searchIndex", detail: "failed after 3 attempts")
        let exported = service.exportDiagnostics()
        XCTAssertTrue(exported.contains("lessons_completed"))
        XCTAssertTrue(exported.contains("content.searchIndex"))
        XCTAssertFalse(exported.contains("@"))
        XCTAssertFalse(exported.lowercased().contains("bearer"))
    }

    func testClearAllRemovesEverything() {
        service.isAnalyticsEnabled = true
        service.recordAnonymousCount("lessons_completed")
        service.recordError(operation: "test", detail: "x")
        service.clearAll()
        XCTAssertEqual(service.eventCount, 0)
        XCTAssertTrue(service.anonymousCounts.isEmpty)
    }
}
