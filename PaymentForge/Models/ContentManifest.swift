// ContentManifest.swift
// Payments Training Hub iOS - Single source of truth for catalogue counts.

import Foundation

/// Verified live numbers: 100 chapters, 881 narrated lessons, 564
/// situations, 320 FAQ, 10 simulators, exactly 500 interview
/// questions, 45 guides, 15 tests, 10 labs, 15 domains.
///
/// This file is the single source of truth for counts. No Swift file
/// should hardcode these numbers: refer to ContentManifest instead,
/// so a catalogue change updates every screen from one place. Counts
/// that come from live loaded data (the search index, the bundled
/// interview bank) still come from that data; ContentManifest is
/// used for display copy and for fallbacks while live data loads.
enum ContentManifest {
    static let chapterCount = 100
    static let lessonCount = 881
    static let situationCount = 564
    static let interviewQuestionCount = 500
    static let faqCount = 320
    static let simulatorCount = 10
    static let guideCount = 45
    static let testCount = 15
    static let labCount = 10
    static let domainCount = 15
}
