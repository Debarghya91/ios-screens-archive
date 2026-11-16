// Phase3ISOExplorerTests.swift
// TrainingHub iOS - Phase 3 tests: the ISO 20022 message explorer
// model (ISO20022Messages.swift). Covers the 10-message catalogue,
// field id uniqueness and requirement labels, relationship
// resolution, the follow-the-payment journey, and the mapping
// workbench. Model logic only; no view tests.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the implementation files before writing.

import XCTest
@testable import TrainingHub

final class Phase3ISOExplorerTests: XCTestCase {

    // MARK: - Helpers

    /// Every field in a tree, top-level blocks and all descendants,
    /// in document order.
    private func flattened(_ fields: [ISO20022Field]) -> [ISO20022Field] {
        var out: [ISO20022Field] = []
        for field in fields {
            out.append(field)
            out.append(contentsOf: flattened(field.children))
        }
        return out
    }

    private func catalogueIDs() -> Set<String> {
        Set(ISO20022Catalogue.messages.map(\.id))
    }

    // MARK: - The 10 messages

    func testExactlyTenMessagesInTeachingOrderEachPresentOnce() {
        let expected = [
            "pain.001", "pain.002", "pacs.008", "pacs.009", "pacs.002",
            "pacs.004", "pacs.007", "camt.052", "camt.053", "camt.054"
        ]
        XCTAssertEqual(ISO20022Catalogue.messages.map(\.id), expected)
        XCTAssertEqual(Set(ISO20022Catalogue.messages.map(\.id)).count, 10)
    }

    func testMessageLookupIsCaseInsensitiveAndTrimsWhitespace() {
        XCTAssertEqual(ISO20022Catalogue.message(id: "pacs.008")?.displayName, "FI to FI Customer Credit Transfer")
        XCTAssertEqual(ISO20022Catalogue.message(id: "PACS.008")?.id, "pacs.008")
        XCTAssertEqual(ISO20022Catalogue.message(id: "  camt.053  ")?.id, "camt.053")
        XCTAssertNil(ISO20022Catalogue.message(id: "pacs.028"))
        XCTAssertNil(ISO20022Catalogue.message(id: "mt103"))
        XCTAssertNil(ISO20022Catalogue.message(id: ""))
        XCTAssertNil(ISO20022Catalogue.message(id: "   "))
    }

    func testEveryMessageCarriesPurposeRootElementAndAbbreviatedSample() {
        for message in ISO20022Catalogue.messages {
            XCTAssertFalse(message.isoName.isEmpty, "\(message.id) has no ISO name.")
            XCTAssertFalse(message.displayName.isEmpty, "\(message.id) has no display name.")
            XCTAssertFalse(message.purpose.isEmpty, "\(message.id) has no purpose.")
            XCTAssertFalse(message.rootElement.isEmpty, "\(message.id) has no root element.")
            XCTAssertFalse(message.fields.isEmpty, "\(message.id) has no fields.")
            XCTAssertTrue(
                message.sampleXML.contains("<Document>"),
                "\(message.id) sample is not wrapped in a Document element."
            )
            XCTAssertTrue(
                message.sampleXML.contains("<\(message.rootElement)>"),
                "\(message.id) sample does not contain its root element \(message.rootElement)."
            )
        }
    }

    func testMessageFamiliesMatchTheirCodePrefixes() {
        for message in ISO20022Catalogue.messages {
            switch message.family {
            case .pain:
                XCTAssertTrue(message.id.hasPrefix("pain."), "\(message.id) is in the pain family.")
            case .pacs:
                XCTAssertTrue(message.id.hasPrefix("pacs."), "\(message.id) is in the pacs family.")
            case .camt:
                XCTAssertTrue(message.id.hasPrefix("camt."), "\(message.id) is in the camt family.")
            }
        }
        XCTAssertEqual(ISO20022Catalogue.messages.filter { $0.family == .pain }.count, 2)
        XCTAssertEqual(ISO20022Catalogue.messages.filter { $0.family == .pacs }.count, 5)
        XCTAssertEqual(ISO20022Catalogue.messages.filter { $0.family == .camt }.count, 3)
        XCTAssertEqual(ISO20022Family.allCases.count, 3)
        XCTAssertEqual(ISO20022Family.pain.displayName, "Payment initiation")
        XCTAssertEqual(ISO20022Family.pacs.displayName, "Payments clearing and settlement")
        XCTAssertEqual(ISO20022Family.camt.displayName, "Cash management")
    }

    // MARK: - Fields and requirement labels

    func testFieldIDsAreUniqueWithinEachMessage() {
        for message in ISO20022Catalogue.messages {
            let ids = flattened(message.fields).map(\.id)
            XCTAssertEqual(
                Set(ids).count, ids.count,
                "\(message.id) has duplicate field ids."
            )
            for id in ids {
                XCTAssertTrue(
                    id.hasPrefix(message.id),
                    "\(message.id) field id does not carry its message prefix: \(id)"
                )
            }
        }
    }

    func testEveryFieldCarriesElementDefinitionAndUsageNote() {
        for message in ISO20022Catalogue.messages {
            for field in flattened(message.fields) {
                XCTAssertFalse(field.element.isEmpty, "\(field.id) has no element name.")
                XCTAssertFalse(field.definition.isEmpty, "\(field.id) has no definition.")
                XCTAssertFalse(field.usageNote.isEmpty, "\(field.id) has no usage note.")
            }
        }
    }

    func testRequirementLabelsAreOnlyTheDefinedCases() {
        // ISO20022Requirement is not CaseIterable, so the defined
        // cases are checked directly and every field's requirement
        // must be one of them.
        XCTAssertEqual(ISO20022Requirement.mandatory.rawValue, "mandatory")
        XCTAssertEqual(ISO20022Requirement.optional.rawValue, "optional")
        XCTAssertEqual(ISO20022Requirement.mandatory.shortLabel, "Mandatory")
        XCTAssertEqual(ISO20022Requirement.optional.shortLabel, "Optional")
        XCTAssertEqual(ISO20022Requirement.mandatory.label, "Mandatory in base schema")
        XCTAssertEqual(ISO20022Requirement.optional.label, "Optional in base schema")
        let defined: [ISO20022Requirement] = [.mandatory, .optional]
        var sawMandatory = false
        var sawOptional = false
        for message in ISO20022Catalogue.messages {
            for field in flattened(message.fields) {
                XCTAssertTrue(defined.contains(field.requirement), "\(field.id) has an undefined requirement.")
                if field.requirement == .mandatory { sawMandatory = true }
                if field.requirement == .optional { sawOptional = true }
            }
        }
        XCTAssertTrue(sawMandatory, "No field in the catalogue is mandatory.")
        XCTAssertTrue(sawOptional, "No field in the catalogue is optional.")
    }

    func testTopLevelBlocksExistAndEveryMessageHasAGroupHeader() {
        for message in ISO20022Catalogue.messages {
            XCTAssertTrue(
                message.fields.contains { $0.element == "GrpHdr" },
                "\(message.id) has no GrpHdr top-level block."
            )
        }
    }

    // MARK: - Relationships

    func testEveryRelationshipTargetResolvesToACatalogueMessage() {
        let ids = catalogueIDs()
        for message in ISO20022Catalogue.messages {
            XCTAssertFalse(message.relationships.isEmpty, "\(message.id) has no relationships.")
            let targets = message.relationships.map(\.relatedMessageID)
            XCTAssertEqual(Set(targets).count, targets.count, "\(message.id) repeats a relationship target.")
            for relationship in message.relationships {
                XCTAssertTrue(
                    ids.contains(relationship.relatedMessageID),
                    "\(message.id) links to \(relationship.relatedMessageID), which is not a catalogue message."
                )
                XCTAssertNotNil(ISO20022Catalogue.message(id: relationship.relatedMessageID))
                XCTAssertNotEqual(relationship.relatedMessageID, message.id, "\(message.id) links to itself.")
                XCTAssertFalse(relationship.kind.isEmpty)
                XCTAssertFalse(relationship.note.isEmpty)
                XCTAssertEqual(relationship.id, relationship.relatedMessageID)
            }
        }
    }

    func testCommonValidationProblemsAreSharedAndNonEmpty() {
        XCTAssertEqual(ISO20022ValidationProblem.commonProblems.count, 5)
        let titles = ISO20022ValidationProblem.commonProblems.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        for problem in ISO20022ValidationProblem.commonProblems {
            XCTAssertFalse(problem.title.isEmpty)
            XCTAssertFalse(problem.explanation.isEmpty)
            XCTAssertEqual(problem.id, problem.title)
        }
    }

    // MARK: - Follow the payment journey

    func testJourneyStepsReferenceOnlyCatalogueMessagesInOrder() {
        XCTAssertEqual(ISO20022Journey.steps.map(\.messageID), ["pain.001", "pacs.008", "pacs.002"])
        for step in ISO20022Journey.steps {
            XCTAssertEqual(step.id, step.messageID)
            XCTAssertNotNil(ISO20022Catalogue.message(id: step.messageID), "Journey step \(step.messageID) is not a catalogue message.")
            XCTAssertFalse(step.stepTitle.isEmpty)
            XCTAssertFalse(step.narrative.isEmpty)
            XCTAssertFalse(step.sampleXML.isEmpty)
            XCTAssertTrue(step.sampleXML.contains("<Document>"))
        }
    }

    func testJourneyStepsUseTheirMessagesRootElements() {
        for step in ISO20022Journey.steps {
            guard let message = ISO20022Catalogue.message(id: step.messageID) else {
                XCTFail("Journey step \(step.messageID) is not a catalogue message.")
                continue
            }
            XCTAssertTrue(
                step.sampleXML.contains("<\(message.rootElement)>"),
                "Journey step \(step.messageID) sample does not contain root element \(message.rootElement)."
            )
        }
    }

    func testJourneySharedValuesAreNonEmptyWithUniqueLabels() {
        XCTAssertFalse(ISO20022Journey.sharedValues.isEmpty)
        let labels = ISO20022Journey.sharedValues.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count)
        for shared in ISO20022Journey.sharedValues {
            XCTAssertFalse(shared.label.isEmpty)
            XCTAssertFalse(shared.value.isEmpty)
            XCTAssertEqual(shared.id, shared.label)
        }
    }

    func testSharedReferencesTravelThroughEveryJourneySample() {
        // The end-to-end and instruction references must appear in
        // all three journey samples; the UETR appears only once the
        // payment moves between banks.
        for step in ISO20022Journey.steps {
            XCTAssertTrue(step.sampleXML.contains("EXAMPLE-E2E-001"), "\(step.messageID) journey sample lacks the shared end-to-end reference.")
            XCTAssertTrue(step.sampleXML.contains("EXAMPLE-INSTR-001"), "\(step.messageID) journey sample lacks the shared instruction reference.")
        }
        let pacs008 = ISO20022Journey.steps[1]
        let pacs002 = ISO20022Journey.steps[2]
        XCTAssertTrue(pacs008.sampleXML.contains("123e4567-e89b-42d3-a456-426614174000"))
        XCTAssertTrue(pacs002.sampleXML.contains("123e4567-e89b-42d3-a456-426614174000"))
        XCTAssertFalse(ISO20022Journey.steps[0].sampleXML.contains("123e4567-e89b-42d3-a456-426614174000"), "The pain.001 journey sample must not carry a UETR.")
    }

    // MARK: - Mapping workbench

    func testMappingRowsHaveUniqueConceptsAndNotes() {
        XCTAssertEqual(ISO20022MappingWorkbench.rows.count, 6)
        let concepts = ISO20022MappingWorkbench.rows.map(\.concept)
        XCTAssertEqual(Set(concepts).count, concepts.count)
        for row in ISO20022MappingWorkbench.rows {
            XCTAssertFalse(row.concept.isEmpty)
            XCTAssertFalse(row.pain001.isEmpty)
            XCTAssertFalse(row.pacs008.isEmpty)
            XCTAssertFalse(row.pacs002.isEmpty)
            XCTAssertFalse(row.note.isEmpty)
            XCTAssertEqual(row.id, row.concept)
        }
    }

    func testMappingWorkbenchPathsReferenceOnlyCatalogueFields() {
        // A cell is either an element path (segments joined by
        // " / "), in which case every segment must be an element
        // in that message's field tree, or an explanatory sentence
        // with no path separator. No path may name an element the
        // catalogue does not teach for that message.
        let messages = Dictionary(uniqueKeysWithValues: ISO20022Catalogue.messages.map { ($0.id, $0) })
        let elementSets = messages.mapValues { Set(flattened($0.fields).map(\.element)) }
        let columns: [(String, KeyPath<ISO20022MappingRow, String>)] = [
            ("pain.001", \.pain001),
            ("pacs.008", \.pacs008),
            ("pacs.002", \.pacs002)
        ]
        for row in ISO20022MappingWorkbench.rows {
            for (messageID, keyPath) in columns {
                let cell = row[keyPath: keyPath]
                guard cell.contains(" / ") else { continue }
                guard let elements = elementSets[messageID] else {
                    XCTFail("Mapping column \(messageID) is not a catalogue message.")
                    continue
                }
                let segments = cell.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
                XCTAssertFalse(segments.isEmpty, "\(row.concept) has an empty path for \(messageID).")
                for segment in segments {
                    XCTAssertTrue(
                        elements.contains(segment),
                        "\(row.concept): path segment \(segment) is not a field of \(messageID)."
                    )
                }
            }
        }
    }

    func testMappingWorkbenchCoversTheExpectedConcepts() {
        let concepts = ISO20022MappingWorkbench.rows.map(\.concept)
        XCTAssertTrue(concepts.contains("End-to-end reference"))
        XCTAssertTrue(concepts.contains("Instruction reference"))
        XCTAssertTrue(concepts.contains("Payment amount"))
        XCTAssertTrue(concepts.contains("Creditor name"))
        XCTAssertTrue(concepts.contains("Tracking reference (UETR)"))
        XCTAssertTrue(concepts.contains("Dates"))
    }
}
