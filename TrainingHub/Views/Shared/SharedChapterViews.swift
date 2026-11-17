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
    /// Reads the service's memoized per-chapter map: the same
    /// membership and order as filtering allLessons, without the
    /// full scan on every call.
    static func lessons(forChapter number: Int, in service: ContentService) -> [SearchEntry] {
        service.lessons(forChapterNumber: number)
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

    /// The agenda for a chapter, from the agendas document's
    /// chapters map, keyed by chapter id ("ch1"). Nil when the
    /// agendas have not loaded, when the chapter has no row, or
    /// when its agenda is blank: the chapter view then shows no
    /// agenda block, never a placeholder and never another
    /// lesson's agenda standing in for the chapter.
    static func chapterAgenda(forChapter number: Int, in service: ContentService) -> String? {
        let agenda = service.agendas?.chapters["ch\(number)"]?.agenda?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let agenda, !agenda.isEmpty else { return nil }
        return agenda
    }

    /// The thumbnail path for a chapter, from the agendas
    /// document's chapters map, keyed by chapter id ("ch1").
    /// Nil when the agendas have not loaded, when the chapter
    /// has no row, or when its thumbnail is blank: the chapter
    /// row keeps its number badge.
    static func chapterThumbnailPath(forChapter number: Int, in service: ContentService) -> String? {
        let path = service.agendas?.chapters["ch\(number)"]?.thumbnail?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else { return nil }
        return path
    }

    /// The agenda for a course, from the agendas document's
    /// courses map, keyed by catalogue bundle id ("integrated",
    /// "part-1" to "part-10"). Nil when the agendas have not
    /// loaded or the product has no row (standalone products
    /// have none): the caller falls back to the product's own
    /// description, never to a placeholder.
    static func courseAgenda(for product: CourseProduct, in service: ContentService) -> String? {
        let agenda = service.agendas?.courses[product.id]?.agenda?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let agenda, !agenda.isEmpty else { return nil }
        return agenda
    }

    /// The thumbnail path for a course, from the agendas
    /// document's courses map, keyed by catalogue bundle id.
    /// Nil when the agendas have not loaded or the product has
    /// no row: the course row keeps its number badge.
    static func courseThumbnailPath(for product: CourseProduct, in service: ContentService) -> String? {
        let path = service.agendas?.courses[product.id]?.thumbnail?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else { return nil }
        return path
    }

    /// A course product's chapter numbers in reading order, from
    /// the reading-order map: the catalogue lists course chapters
    /// in topic order, and course and catalogue listings must
    /// read in course order.
    static func readingOrderChapterNumbers(for product: CourseProduct) -> [Int] {
        product.chapterIDs
            .compactMap { chapterNumber(from: $0) }
            .sorted {
                PFBookModeReadingOrder.readingOrderIndex(forInternalNumber: $0)
                    < PFBookModeReadingOrder.readingOrderIndex(forInternalNumber: $1)
            }
    }

    /// All chapter numbers present in the loaded index, numeric order.
    /// Reads the service's memoized map keys: the same set and
    /// order as scanning allLessons, without the full scan.
    static func chapterNumbers(in service: ContentService) -> [Int] {
        service.chapterNumbers
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

    /// Short listen label for one lesson: "About 6 min listen".
    /// Nil when unknown. The word "listen" is part of the label:
    /// these seconds are narration length, never read time, and
    /// stamping them as a bare time misled learners into reading
    /// them as read time. Read time is computed separately, from
    /// the full lesson text, in LessonView.
    static func listenLabel(for lessonID: String) -> String? {
        guard let sec = secondsByID[lessonID], sec > 0 else { return nil }
        return "About " + durationText(sec) + " listen"
    }

    /// Total label for a chapter, session or course: "About 45 min
    /// of listening" or "About 1 hr 20 min of listening". Nil when
    /// nothing is known. Narration totals only: no read-time total
    /// is claimed, because full lesson texts are not loaded in
    /// list context.
    static func totalLabel(for lessons: [SearchEntry]) -> String? {
        totalLabel(seconds: totalSeconds(for: lessons))
    }

    /// Total label for a raw second count. Nil when zero.
    static func totalLabel(seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        return "About " + durationText(seconds) + " of listening"
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
/// Callers must pass the FULL text of the item: the search index
/// entry text is a truncated excerpt (86 to 193 words), and timing
/// it stamps "About 1 min read" on every item. List rows for
/// excerpt-only items show no read time at all.
enum ReadTime {
    /// Whole read minutes for the full text, or nil when empty.
    static func minutes(for text: String) -> Int? {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        guard words > 0 else { return nil }
        return max(1, (words + 199) / 200)
    }

    static func label(for text: String) -> String? {
        guard let mins = minutes(for: text) else { return nil }
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
                // The thumbnail sits beside the title when the
                // website exposes one; the type icon tile otherwise.
                if entry.thumbnail != nil {
                    PFThumbnailView(thumbnailPath: entry.thumbnail, size: 44, cornerRadius: 12)
                } else {
                    PFIconTile(systemImage: systemImage, size: 44)
                }
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

    /// Approximate time for this entry: the narration length for
    /// a lesson when the manifest knows it, labelled as listen
    /// time. Guides, labs, tests and FAQs show no time here: the
    /// only text in list context is the truncated index excerpt,
    /// and timing an excerpt stamps a fake read time on the item.
    /// Nil shows nothing.
    private var timeLabel: String? {
        guard entry.type == .lesson else { return nil }
        return LessonDurations.listenLabel(for: entry.id)
    }
}

// MARK: - Entry detail

/// Shows one guide, lab or test entry: title, type pill, text.
/// No time label: the entry text is the truncated index excerpt,
/// not the full item, so no truthful read time can be computed
/// here, and a stamped label would mislead.
struct EntryDetailView: View {
    let entry: SearchEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                PFPill(text: entry.type.displayName)
                Text(entry.title)
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
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

