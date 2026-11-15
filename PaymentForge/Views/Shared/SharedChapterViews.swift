// SharedChapterViews.swift
// Payments Training Hub iOS - shared chapter helpers and entry views.
// Moved verbatim from HomeView (PFChapterHelper) and CoursesView
// (EntryRow, EntryDetailView) so every tab uses one definition.
// Native SwiftUI only, no WebView. Uses the shared DesignSystem.
// No em dashes in any user-facing text.

import SwiftUI
import Foundation

// MARK: - Shared chapter helpers

/// Helpers for deriving chapters from lesson entries.
/// Lesson IDs look like ch1s1 or ch27s9. The chapter number is the digits
/// between "ch" and "s". Filtering is done on the exact chapter number:
/// a plain prefix match on "ch1" would also catch ch10 to ch19.
enum PFChapterHelper {
    static func chapterNumber(from lessonID: String) -> Int? {
        guard lessonID.hasPrefix("ch") else { return nil }
        let digits = lessonID.dropFirst(2).prefix(while: { $0.isNumber })
        return Int(digits)
    }

    /// Lessons belonging to exactly one chapter number, in catalogue order.
    static func lessons(forChapter number: Int, in service: ContentService) -> [SearchEntry] {
        service.allLessons.filter { chapterNumber(from: $0.id) == number }
    }

    /// The citation for an entry, via the service: regular lessons
    /// are numbered by sequential position within the chapter in
    /// catalogue order, supplemental lessons show the chapter only
    /// with no misleading number.
    static func citation(for entry: SearchEntry, in service: ContentService) -> String {
        service.citation(for: entry)
    }

    /// True when this entry is the first lesson of its chapter: the
    /// free sample lesson. One per chapter, full content, no purchase
    /// needed. The remaining lessons in the chapter stay locked
    /// behind the part or the Integrated Course, except the
    /// sequential samples (see isFreeLesson).
    static func isSampleLesson(_ entry: SearchEntry, in service: ContentService) -> Bool {
        guard let number = chapterNumber(from: entry.id) else { return false }
        return lessons(forChapter: number, in: service).first?.id == entry.id
    }

    /// True when this lesson is one of its part's sequential free
    /// samples: the first 2 lessons of the part in reading-order
    /// order, in addition to the D77 first-lesson-of-chapter rule.
    /// Empty when the reading-order map has no lesson lists loaded.
    static func isSequentialSampleLesson(_ entry: SearchEntry) -> Bool {
        FreeSampleRules.isSequentialSampleLesson(entry.id)
    }

    /// True when this lesson is free without any purchase: the
    /// first lesson of its chapter (D77), or one of its part's
    /// sequential free samples. Lesson gating uses this; deep-link
    /// sharing, onboarding, and the dashboard keep using
    /// isSampleLesson (D77 only) on purpose.
    static func isFreeLesson(_ entry: SearchEntry, in service: ContentService) -> Bool {
        isSampleLesson(entry, in: service) || isSequentialSampleLesson(entry)
    }

    /// Lessons for a guided session, in session chapter order, deduped by id.
    static func lessons(forSession session: GuidedSession, in service: ContentService) -> [SearchEntry] {
        var seen: Set<String> = []
        var result: [SearchEntry] = []
        for chapterID in session.chapterIDs {
            guard let number = chapterNumber(from: chapterID + "s1") else { continue }
            for lesson in lessons(forChapter: number, in: service) {
                if seen.insert(lesson.id).inserted {
                    result.append(lesson)
                }
            }
        }
        return result
    }

    /// Chapter title: the second non-empty line of the first lesson's text.
    /// With no lessons, the book chapter label, or the bare word
    /// when the chapter has no book number: an internal chapter
    /// number is never shown.
    static func chapterTitle(for lessons: [SearchEntry], number: Int) -> String {
        guard let first = lessons.first else {
            return PFBookModeReadingOrder.chapterLabel(forInternalNumber: number) ?? "Chapter"
        }
        return chapterTitle(for: first)
    }

    /// Chapter title for one lesson entry: the chapter name parsed
    /// from the single-line catalogue text
    /// (`<lesson title> <chapter name> Part N: <domain> <body>`).
    /// Falls back to the book chapter label, never to the app name
    /// and never to an internal chapter number.
    static func chapterTitle(for entry: SearchEntry) -> String {
        if let name = entry.chapterName { return name }
        if let number = entry.chapterNumber,
           let label = PFBookModeReadingOrder.chapterLabel(forInternalNumber: number) { return label }
        return "Chapter"
    }

    /// The reading position of a lesson for display: "Chapter 26,
    /// Lesson 3" for a regular lesson, "Chapter 27" for a
    /// supplemental lesson (no lesson number), the chapter name
    /// for a held-out chapter, nil when nothing can be derived.
    /// Chapter numbers are always book numbers, never internal.
    /// The lesson number comes from the reading-order map when it
    /// lists the lesson, else the sequential position in the
    /// chapter, else the lesson s-number.
    static func readingPositionLabel(for entry: SearchEntry, in service: ContentService) -> String? {
        guard let number = chapterNumber(from: entry.id) else { return nil }
        guard let book = PFBookModeReadingOrder.bookNumber(forInternalNumber: number) else {
            return entry.chapterName
        }
        if entry.isSupplemental {
            return "Chapter \(book)"
        }
        if let display = PFBookModeReadingOrder.displayNumber(forLessonID: entry.id) {
            return "Chapter \(book), Lesson \(display)"
        }
        if let position = service.lessonPositionInChapter(for: entry) {
            return "Chapter \(book), Lesson \(position)"
        }
        if let lesson = entry.lessonNumber {
            return "Chapter \(book), Lesson \(lesson)"
        }
        return "Chapter \(book)"
    }

    /// All chapter numbers present in the loaded index, numeric order.
    static func chapterNumbers(in service: ContentService) -> [Int] {
        let numbers = Set(service.allLessons.compactMap { chapterNumber(from: $0.id) })
        return numbers.sorted()
    }

    /// The next lessons to recommend: the first lessons in book
    /// reading order that the learner has not completed yet. Real
    /// catalogue entries only, never invented.
    static func recommendedLessons(in service: ContentService, progress: ProgressStore, limit: Int = 3) -> [SearchEntry] {
        Array(service.readingOrderLessons.filter { !progress.isLessonComplete($0.id) }.prefix(limit))
    }
}

// MARK: - Lesson durations

/// True narration lengths for every lesson, measured from the
/// narration audio on the audio hosts and shipped as
/// lesson-durations.json. No audio is bundled with the app.
/// Lists show these estimates without loading any lesson page.
/// A lesson missing from the manifest shows no estimate, never
/// a guessed number.
enum LessonDurations {
    /// Seconds of narration per lesson id, loaded once from the
    /// bundled manifest. Empty when the file is missing; the app
    /// never fails to load without it.
    static let secondsByID: [String: Int] = {
        guard let url = Bundle.main.url(forResource: "lesson-durations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return map
    }()

    /// Narration seconds for one lesson, if the manifest knows it.
    static func seconds(for lessonID: String) -> Int? {
        secondsByID[lessonID]
    }

    /// Total narration seconds for a list of lessons. Lessons
    /// missing from the manifest count as zero.
    static func totalSeconds(for lessons: [SearchEntry]) -> Int {
        lessons.reduce(0) { $0 + (secondsByID[$1.id] ?? 0) }
    }

    /// Short label for one lesson: "6 min". Nil when unknown.
    static func label(for lessonID: String) -> String? {
        guard let sec = secondsByID[lessonID], sec > 0 else { return nil }
        return "\(minutes(sec)) min"
    }

    /// Total label for a chapter, session or course: "About 45 min"
    /// or "About 1 hr 20 min". Nil when nothing is known.
    static func totalLabel(for lessons: [SearchEntry]) -> String? {
        totalLabel(seconds: totalSeconds(for: lessons))
    }

    /// Total label for a raw second count. Nil when zero.
    static func totalLabel(seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        return "About " + durationText(seconds)
    }

    /// "45 min", "1 hr", "1 hr 20 min", "3 hrs".
    static func durationText(_ seconds: Int) -> String {
        let mins = minutes(seconds)
        if mins < 60 { return "\(mins) min" }
        let hrs = mins / 60
        let rem = mins % 60
        if rem == 0 { return hrs == 1 ? "1 hr" : "\(hrs) hrs" }
        return hrs == 1 ? "1 hr \(rem) min" : "\(hrs) hrs \(rem) min"
    }

    /// Whole minutes, rounded to nearest, at least 1.
    private static func minutes(_ seconds: Int) -> Int {
        max(1, (seconds + 30) / 60)
    }
}

// MARK: - Read time

/// Approximate read time for text content, at 200 words per
/// minute, rounded up, at least 1 minute. Computed from the
/// actual text, never guessed: empty text has no estimate.
enum ReadTime {
    static func label(for text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        guard words > 0 else { return nil }
        let mins = max(1, (words + 199) / 200)
        return "About \(mins) min read"
    }
}

struct EntryRow: View {
    let entry: SearchEntry

    private var systemImage: String {
        switch entry.type {
        case .lesson: return "play.fill"
        case .guide: return "book.fill"
        case .situation: return "briefcase.fill"
        case .lab: return "flask.fill"
        case .test: return "checkmark.circle.fill"
        case .faq: return "questionmark.circle.fill"
        }
    }

    var body: some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: systemImage, size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(entry.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.preview)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let timeLabel = timeLabel {
                        HStack(spacing: PFSpacing.xs) {
                            Image(systemName: "clock")
                                .font(.pfCaption.weight(.semibold))
                                .accessibilityHidden(true)
                            Text(timeLabel)
                                .font(.pfCaption)
                        }
                        .foregroundColor(.pfSecondaryText)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
                    .pfDecorative()
            }
        }
    }

    /// Approximate time for this entry: the narration length
    /// for a lesson when the manifest knows it, else the read
    /// time of the entry text. Nil shows nothing.
    private var timeLabel: String? {
        if entry.type == .lesson, let label = LessonDurations.label(for: entry.id) {
            return "About " + label
        }
        return ReadTime.label(for: entry.text)
    }
}

// MARK: - Entry detail

/// Shows one guide, lab or test entry: title, type pill, full text.
struct EntryDetailView: View {
    let entry: SearchEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                PFPill(text: entry.type.displayName)
                Text(entry.title)
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                if let timeLabel = ReadTime.label(for: entry.text) {
                    Label(timeLabel, systemImage: "clock")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                }
                PFBodyText(text: entry.text)
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle(entry.type.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

