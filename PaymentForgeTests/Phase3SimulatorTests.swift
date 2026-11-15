// Phase3SimulatorTests.swift
// PaymentForge iOS - Phase 3 tests: the payment lifecycle simulator
// model (PaymentLifecycle.swift). Covers the 14 stages in journey
// order, the required fields on every stage, the 6 injected faults
// and their applicable stages, the journey record, and the
// fictional labelling of the sample payments. Model logic only;
// no view tests.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the implementation files before writing.

import XCTest
@testable import PaymentForge

final class Phase3SimulatorTests: XCTestCase {

    // MARK: - The 14 stages

    func testExactlyFourteenStagesInBriefedOrder() {
        XCTAssertEqual(PaymentLifecycleStage.allCases.count, 14)
        XCTAssertEqual(
            PaymentLifecycleStage.orderedStages,
            [
                .initiation, .gateway, .validation, .enrichment,
                .sanctionsScreening, .fraudChecks, .accountChecks,
                .processing, .routing, .clearing, .settlement,
                .ledgerUpdates, .notifications, .reconciliation
            ]
        )
        XCTAssertEqual(PaymentLifecycleStage.orderedStages.map(\.rawValue), Array(1...14))
        XCTAssertEqual(PaymentLifecycleStage.allCases, PaymentLifecycleStage.orderedStages)
    }

    func testStageNumbersRunOneToFourteen() {
        for stage in PaymentLifecycleStage.orderedStages {
            XCTAssertEqual(stage.number, stage.rawValue)
            XCTAssertEqual(stage.id, stage.rawValue)
        }
        XCTAssertEqual(PaymentLifecycleStage.initiation.number, 1)
        XCTAssertEqual(PaymentLifecycleStage.reconciliation.number, 14)
    }

    func testStageTitlesAreUniqueAndNonEmpty() {
        let titles = PaymentLifecycleStage.orderedStages.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        for title in titles {
            XCTAssertFalse(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        XCTAssertEqual(PaymentLifecycleStage.initiation.title, "Payment initiation")
        XCTAssertEqual(PaymentLifecycleStage.reconciliation.title, "Reconciliation")
    }

    func testPreviousAndNextStageChain() {
        XCTAssertNil(PaymentLifecycleStage.initiation.previousStage)
        XCTAssertNil(PaymentLifecycleStage.reconciliation.nextStage)
        let stages = PaymentLifecycleStage.orderedStages
        for index in stages.indices {
            if index > 0 {
                XCTAssertEqual(stages[index].previousStage, stages[index - 1])
            }
            if index < stages.count - 1 {
                XCTAssertEqual(stages[index].nextStage, stages[index + 1])
            }
        }
    }

    // MARK: - Required fields on every stage

    func testEveryStageCarriesAllRequiredFields() {
        for stage in PaymentLifecycleStage.orderedStages {
            let fields: [(String, String)] = [
                ("explanation", stage.explanation),
                ("incomingEvent", stage.incomingEvent),
                ("processingComponent", stage.processingComponent),
                ("stateTransition", stage.stateTransition),
                ("dataTransformation", stage.dataTransformation),
                ("outgoingEvent", stage.outgoingEvent),
                ("expectedResult", stage.expectedResult),
                ("failureOutcome", stage.failureOutcome)
            ]
            for (name, value) in fields {
                XCTAssertFalse(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Stage \(stage.number) (\(stage.title)) has an empty \(name)."
                )
            }
            XCTAssertFalse(stage.systemImage.isEmpty, "Stage \(stage.number) has no system image name.")
        }
    }

    func testStageFieldTextContainsNoEmDash() {
        // The model file states that no em dashes appear in any
        // user-facing text or comments. The check below guards the
        // user-facing strings directly.
        for stage in PaymentLifecycleStage.orderedStages {
            let texts = [
                stage.title, stage.explanation, stage.incomingEvent,
                stage.processingComponent, stage.stateTransition,
                stage.dataTransformation, stage.outgoingEvent,
                stage.expectedResult, stage.failureOutcome
            ]
            for text in texts {
                // The em dash is written as a Unicode escape so
                // this file contains no literal em dash character.
                XCTAssertFalse(text.unicodeScalars.contains("\u{2014}"), "Stage \(stage.number) text contains an em dash: \(text)")
            }
        }
    }

    // MARK: - Faults

    func testExactlySixFaults() {
        XCTAssertEqual(LifecycleFault.allCases.count, 6)
        XCTAssertEqual(
            Set(LifecycleFault.allCases),
            Set([
                LifecycleFault.validationFailure, .sanctionsHold,
                .insufficientFunds, .duplicatePayment,
                .downstreamTimeout, .clearingRejection
            ])
        )
    }

    func testEveryFaultCarriesTitleDescriptionStepsAndLesson() {
        for fault in LifecycleFault.allCases {
            XCTAssertFalse(fault.title.isEmpty)
            XCTAssertFalse(fault.description.isEmpty)
            XCTAssertFalse(fault.learnerNote.isEmpty)
            XCTAssertFalse(fault.systemImage.isEmpty)
            XCTAssertFalse(fault.operatorNextSteps.isEmpty, "Fault \(fault.title) has no operator next steps.")
            for step in fault.operatorNextSteps {
                XCTAssertFalse(step.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    func testFaultEffectsMatchTheDocumentedEffects() {
        XCTAssertEqual(LifecycleFault.validationFailure.effect, .stopped)
        XCTAssertEqual(LifecycleFault.sanctionsHold.effect, .held)
        XCTAssertEqual(LifecycleFault.insufficientFunds.effect, .stopped)
        XCTAssertEqual(LifecycleFault.duplicatePayment.effect, .held)
        XCTAssertEqual(LifecycleFault.downstreamTimeout.effect, .waitingRetry)
        XCTAssertEqual(LifecycleFault.clearingRejection.effect, .stopped)
    }

    func testFaultApplicableStagesAreValidAndNonEmpty() {
        XCTAssertEqual(LifecycleFault.validationFailure.applicableStages, [.validation])
        XCTAssertEqual(LifecycleFault.sanctionsHold.applicableStages, [.sanctionsScreening])
        XCTAssertEqual(LifecycleFault.insufficientFunds.applicableStages, [.accountChecks])
        XCTAssertEqual(LifecycleFault.duplicatePayment.applicableStages, [.validation, .processing])
        XCTAssertEqual(
            LifecycleFault.downstreamTimeout.applicableStages,
            [.routing, .clearing, .settlement]
        )
        XCTAssertEqual(LifecycleFault.clearingRejection.applicableStages, [.clearing])
        for fault in LifecycleFault.allCases {
            XCTAssertFalse(fault.applicableStages.isEmpty)
            for stage in fault.applicableStages {
                XCTAssertTrue(fault.canInject(at: stage))
            }
        }
    }

    func testCanInjectRejectsNonApplicableStages() {
        XCTAssertFalse(LifecycleFault.validationFailure.canInject(at: .settlement))
        XCTAssertFalse(LifecycleFault.sanctionsHold.canInject(at: .validation))
        XCTAssertFalse(LifecycleFault.insufficientFunds.canInject(at: .processing))
        XCTAssertFalse(LifecycleFault.duplicatePayment.canInject(at: .clearing))
        XCTAssertFalse(LifecycleFault.downstreamTimeout.canInject(at: .validation))
        XCTAssertFalse(LifecycleFault.clearingRejection.canInject(at: .settlement))
        for fault in LifecycleFault.allCases {
            for stage in PaymentLifecycleStage.orderedStages {
                XCTAssertEqual(
                    fault.canInject(at: stage),
                    fault.applicableStages.contains(stage),
                    "canInject and applicableStages disagree for \(fault.title) at \(stage.title)."
                )
            }
        }
    }

    func testFaultEffectTitlesAndDownstreamWordingAreNonEmpty() {
        for effect in [LifecycleFaultEffect.stopped, .held, .waitingRetry] {
            XCTAssertFalse(effect.title.isEmpty)
            XCTAssertFalse(effect.systemImage.isEmpty)
            XCTAssertFalse(effect.downstreamWording.isEmpty)
        }
        XCTAssertEqual(LifecycleFaultEffect.stopped.title, "Payment stops")
        XCTAssertEqual(LifecycleFaultEffect.held.title, "Payment held for review")
    }

    // MARK: - Sample payments

    func testSamplePaymentsAreFictionalLabelled() {
        XCTAssertEqual(SamplePaymentCatalogue.samples.count, 3)
        XCTAssertEqual(SamplePaymentCatalogue.defaultSample, SamplePaymentCatalogue.samples[0])
        let ids = SamplePaymentCatalogue.samples.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for sample in SamplePaymentCatalogue.samples {
            XCTAssertTrue(sample.label.hasPrefix("Sample "), "Label is not sample-labelled: \(sample.label)")
            XCTAssertTrue(sample.payerName.contains("(fictional)"), "Payer name is not fictional-labelled: \(sample.payerName)")
            XCTAssertTrue(sample.payeeName.contains("(fictional)"), "Payee name is not fictional-labelled: \(sample.payeeName)")
            XCTAssertTrue(sample.payerAccountReference.hasPrefix("SAMPLE-"), "Payer account reference: \(sample.payerAccountReference)")
            XCTAssertTrue(sample.payeeAccountReference.hasPrefix("SAMPLE-"), "Payee account reference: \(sample.payeeAccountReference)")
            XCTAssertTrue(sample.paymentReference.hasPrefix("SAMPLE-"), "Payment reference: \(sample.paymentReference)")
            XCTAssertTrue(sample.amountText.contains("sample units"), "Amount is not in sample units: \(sample.amountText)")
            XCTAssertTrue(sample.purpose.contains("Sample"), "Purpose is not sample-labelled: \(sample.purpose)")
            XCTAssertTrue(sample.channel.contains("Sample"), "Channel is not sample-labelled: \(sample.channel)")
        }
    }

    // MARK: - Journey record

    func testFreshJourneyIsInProgressWithNoEnding() {
        let journey = LifecycleJourney()
        XCTAssertTrue(journey.visitedStages.isEmpty)
        XCTAssertNil(journey.injection)
        XCTAssertTrue(journey.blockedStages.isEmpty)
        XCTAssertEqual(journey.unvisitedStages, PaymentLifecycleStage.orderedStages)
        XCTAssertEqual(journey.outcome, .inProgress)
        XCTAssertFalse(journey.hasEnding)
    }

    func testVisitRecordsStagesOnceInFirstVisitOrder() {
        var journey = LifecycleJourney()
        journey.visit(.validation)
        journey.visit(.initiation)
        journey.visit(.validation)
        XCTAssertEqual(journey.visitedStages, [.validation, .initiation])
        XCTAssertEqual(journey.unvisitedStages.count, 12)
        XCTAssertFalse(journey.unvisitedStages.contains(.validation))
        XCTAssertFalse(journey.unvisitedStages.contains(.initiation))
    }

    func testInjectRecordsFaultAndVisitsTheStage() {
        var journey = LifecycleJourney()
        journey.inject(.sanctionsHold, at: .sanctionsScreening)
        XCTAssertEqual(journey.injection, LifecycleFaultInjection(fault: .sanctionsHold, stage: .sanctionsScreening))
        XCTAssertEqual(journey.visitedStages, [.sanctionsScreening])
        XCTAssertTrue(journey.hasEnding)
    }

    func testBlockedStagesAreThoseAfterTheFaultStage() {
        var journey = LifecycleJourney()
        journey.inject(.validationFailure, at: .validation)
        XCTAssertEqual(
            journey.blockedStages,
            PaymentLifecycleStage.orderedStages.filter { $0.rawValue > PaymentLifecycleStage.validation.rawValue }
        )
        XCTAssertEqual(journey.blockedStages.count, 11)
        XCTAssertFalse(journey.blockedStages.contains(.validation))
    }

    func testFaultAtLastStageBlocksNothing() {
        var journey = LifecycleJourney()
        journey.inject(.downstreamTimeout, at: .reconciliation)
        XCTAssertTrue(journey.blockedStages.isEmpty)
    }

    func testClearInjectionKeepsVisitedStagesAndRemovesEnding() {
        var journey = LifecycleJourney()
        journey.visit(.initiation)
        journey.inject(.sanctionsHold, at: .sanctionsScreening)
        journey.clearInjection()
        XCTAssertNil(journey.injection)
        XCTAssertEqual(journey.visitedStages, [.initiation, .sanctionsScreening])
        XCTAssertTrue(journey.blockedStages.isEmpty)
        XCTAssertEqual(journey.outcome, .inProgress)
        XCTAssertFalse(journey.hasEnding)
    }

    func testOutcomeFollowsFaultEffect() {
        var stopped = LifecycleJourney()
        stopped.inject(.validationFailure, at: .validation)
        XCTAssertEqual(stopped.outcome, .stoppedByFault)

        var held = LifecycleJourney()
        held.inject(.sanctionsHold, at: .sanctionsScreening)
        XCTAssertEqual(held.outcome, .heldByFault)

        var waiting = LifecycleJourney()
        waiting.inject(.downstreamTimeout, at: .routing)
        XCTAssertEqual(waiting.outcome, .waitingAfterFault)
    }

    func testOutcomeForHappyPathAndEarlyEnd() {
        var happy = LifecycleJourney()
        for stage in PaymentLifecycleStage.orderedStages {
            happy.visit(stage)
        }
        happy.markReachedEnd()
        XCTAssertEqual(happy.outcome, .happyPathComplete)
        XCTAssertTrue(happy.hasEnding)
        XCTAssertTrue(happy.unvisitedStages.isEmpty)

        var early = LifecycleJourney()
        early.visit(.initiation)
        early.markEndedEarly()
        XCTAssertEqual(early.outcome, .endedEarly)
        XCTAssertTrue(early.hasEnding)
    }

    func testInjectionOutcomeWinsOverReachedEndAndEarlyEnd() {
        var journey = LifecycleJourney()
        journey.markReachedEnd()
        journey.markEndedEarly()
        journey.inject(.clearingRejection, at: .clearing)
        XCTAssertEqual(journey.outcome, .stoppedByFault)
    }

    func testResetClearsTheWholeRun() {
        var journey = LifecycleJourney()
        journey.visit(.initiation)
        journey.inject(.sanctionsHold, at: .sanctionsScreening)
        journey.markEndedEarly()
        journey.reset()
        XCTAssertTrue(journey.visitedStages.isEmpty)
        XCTAssertNil(journey.injection)
        XCTAssertTrue(journey.blockedStages.isEmpty)
        XCTAssertEqual(journey.outcome, .inProgress)
        XCTAssertFalse(journey.hasEnding)
    }

    func testJourneyOutcomeTitlesAndDetailsAreNonEmpty() {
        let outcomes: [LifecycleJourneyOutcome] = [
            .inProgress, .happyPathComplete, .stoppedByFault,
            .heldByFault, .waitingAfterFault, .endedEarly
        ]
        for outcome in outcomes {
            XCTAssertFalse(outcome.title.isEmpty)
            XCTAssertFalse(outcome.detail.isEmpty)
            XCTAssertFalse(outcome.systemImage.isEmpty)
        }
        XCTAssertEqual(LifecycleJourneyOutcome.happyPathComplete.title, "Happy path complete")
    }
}
