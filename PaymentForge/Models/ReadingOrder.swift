// ReadingOrder.swift
// PaymentForge iOS - THE reading order for book mode: the single map
// from internal chapter IDs to the learner-facing book numbers and
// parts. Every display number in the app (chapter rows, chapter
// headers, citations, search results, prev/next, progress) comes
// from this file through PFBookModeReadingOrder, and from nowhere
// else. Certificates show no chapter numbers and need no lookup.
//
// The map is the website's reading-order.json (assets/
// reading-order.json, version v1.1-numbering-1115): the same file
// ships bundled with the app, and ContentService refreshes it from
// the website on launch, caching the refreshed copy for the next
// launch. Offline, or when the fetch fails or the fetched copy
// does not validate, the bundled copy is used. When even the
// bundled copy cannot be read, a hardcoded copy of the same order
// (verified identical to the bundled file) is the last resort, so
// display numbers never go missing. The in-memory map never
// changes mid-run: a refreshed copy takes effect on the next
// launch, so numbers stay stable within a session.
//
// A refined order later is a one-file change on the website plus a
// re-bundle here: edit the JSON, and every display number in the
// app follows. Internal chapter IDs (ch38 and friends), lesson
// IDs, URLs, audio filenames and data keys never change and are
// never shown to learners: this map only decides what number a
// learner sees. Lessons the bundled map does not list yet (new
// lessons from a later content round) resolve through the
// fallbacks in the callers: sequential position in the chapter,
// then the lesson s-number. No em dashes in any user-facing text.

import Foundation

/// The book-mode reading order: internal chapter IDs to book
/// chapter numbers and parts. Book numbers run 1 to 99 in reading
/// order; the held-out chapter has no book number and is shown
/// without one, never with its internal number.
enum PFBookModeReadingOrder {

    /// One part of the book: its number, title, and the book
    /// chapters it holds, as a contiguous range.
    struct BookPart: Hashable {
        let number: Int
        let title: String
        let bookNumbers: ClosedRange<Int>
    }

    // MARK: - Map document (reading-order.json schema)

    /// One lesson in the map: its internal id and its display
    /// number inside its chapter (1, 2, 3, ...).
    struct MapLesson: Decodable {
        let id: String
        let displayNumber: Int

        enum CodingKeys: String, CodingKey {
            case id
            case displayNumber = "display_number"
        }
    }

    /// One chapter in the map: its internal id, its book number,
    /// and its lessons in display order.
    struct MapChapter: Decodable {
        let id: String
        let bookNumber: Int
        let lessons: [MapLesson]

        enum CodingKeys: String, CodingKey {
            case id
            case bookNumber = "book_number"
            case lessons
        }
    }

    /// One part in the map: its number, title, and chapters.
    struct MapPart: Decodable {
        let part: Int
        let title: String
        let chapters: [MapChapter]
    }

    /// One chapter held outside the main reading path: no book
    /// number, kept reachable outside the sequence.
    struct MapHeldOut: Decodable {
        let id: String
        let bookNumber: Int?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case id
            case bookNumber = "book_number"
            case reason
        }
    }

    /// The whole map document. Unknown keys (source, numbering
    /// rule) are ignored by the decoder.
    struct MapDocument: Decodable {
        let version: String
        let status: String
        let parts: [MapPart]
        let heldOut: [MapHeldOut]

        enum CodingKeys: String, CodingKey {
            case version
            case status
            case parts
            case heldOut = "held_out"
        }

        /// A fetched or cached copy is usable only when it carries
        /// a version, exactly 99 book chapters numbered 1 to 99
        /// with no duplicate chapter id, and at least one held-out
        /// chapter. Lesson counts are deliberately not pinned: a
        /// later content round extends the lesson lists without
        /// changing the chapter order.
        var isValid: Bool {
            guard !version.isEmpty, !heldOut.isEmpty else { return false }
            let chapters = parts.flatMap(\.chapters)
            guard chapters.count == 99 else { return false }
            let ids = chapters.map(\.id)
            guard Set(ids).count == ids.count else { return false }
            return Set(chapters.map(\.bookNumber)) == Set(1...99)
        }
    }

    // MARK: - Loading

    /// The website copy of the map, refreshed on launch.
    static let websiteURL = URL(string: "https://www.paymentstraininghub.com/assets/reading-order.json")!

    /// The cached refreshed copy, in the Caches directory next to
    /// the search index cache. Purging it is harmless: the bundled
    /// copy is the fallback.
    static let cacheFileName = "pf-reading-order.json"

    /// The map in use this run: the cached refreshed copy when it
    /// validates, else the bundled copy, else the hardcoded
    /// fallback. Loaded once, lazily, and never swapped mid-run.
    private static let loaded: MapDocument = load()

    private static func load() -> MapDocument {
        if let cached = cachedData(),
           let decoded = try? JSONDecoder().decode(MapDocument.self, from: cached),
           decoded.isValid {
            return decoded
        }
        if let url = Bundle.main.url(forResource: "reading-order", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(MapDocument.self, from: data),
           decoded.isValid {
            return decoded
        }
        return fallbackDocument
    }

    private static func cachedData() -> Data? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(cacheFileName))
    }

    /// Fetch the website copy, validate it, and cache it for the
    /// next launch. Silent on every failure: offline, a non-200
    /// response, undecodable bytes, or a copy that does not
    /// validate all leave the current map untouched. Called once
    /// at launch from ContentService; safe to call again, it only
    /// ever rewrites the cache.
    static func refreshFromWebsite() async {
        var request = URLRequest(url: websiteURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(MapDocument.self, from: data),
              decoded.isValid else { return }
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        try? data.write(to: dir.appendingPathComponent(cacheFileName), options: [.atomic])
    }

    // MARK: - Hardcoded fallback (identical to the bundled map)

    /// The ten parts of the book, in reading order. Used only to
    /// build the fallback document when no JSON copy can be read;
    /// verified identical to the bundled reading-order.json.
    private static let fallbackParts: [BookPart] = [
        BookPart(number: 1, title: "Foundations of Money and Payments", bookNumbers: 1...7),
        BookPart(number: 2, title: "How Payments Move: Rails, Schemes and Systems", bookNumbers: 8...21),
        BookPart(number: 3, title: "Messages: SWIFT MT, ISO 20022 and Standards", bookNumbers: 22...35),
        BookPart(number: 4, title: "Cross-Border Payments and Correspondent Banking", bookNumbers: 36...43),
        BookPart(number: 5, title: "Clearing, Settlement, Liquidity and Reconciliation", bookNumbers: 44...56),
        BookPart(number: 6, title: "Exceptions, Investigations, Returns and Claims", bookNumbers: 57...67),
        BookPart(number: 7, title: "Cards and Customer Payments", bookNumbers: 68...72),
        BookPart(number: 8, title: "Architecture, APIs, Hubs and Engineering", bookNumbers: 73...86),
        BookPart(number: 9, title: "The Business Analyst at Work", bookNumbers: 87...96),
        BookPart(number: 10, title: "Emerging Payments and the Future", bookNumbers: 97...99),
    ]

    /// Internal chapter numbers in reading order. Index 0 is Book
    /// Chapter 1. Exactly 99 entries: every internal chapter
    /// except the held-out one, each appearing once. Used only to
    /// build the fallback document; verified identical to the
    /// bundled reading-order.json.
    private static let fallbackOrder: [Int] = [
        1, 2, 3, 4, 64, 69, 70, 9, 10, 11, 12, 33, 56, 57, 59, 61, 62, 74, 91, 92, 93, 5, 6, 7, 8,
        38, 54, 39, 50, 51, 52, 53, 58, 60, 67, 13, 14, 15, 16, 94, 49, 66, 75, 17, 18, 21, 71, 90,
        19, 20, 40, 44, 76, 77, 88, 89, 72, 23, 24, 41, 86, 87, 95, 73, 78, 81, 99, 22, 31, 32, 34,
        63, 25, 26, 30, 35, 36, 42, 43, 46, 47, 48, 65, 80, 68, 79, 28, 45, 82, 83, 84, 29, 96, 97,
        98, 100, 55, 27, 85
    ]

    /// The fallback document: the same chapter order and parts,
    /// with no lesson lists (callers fall back to chapter position
    /// and s-number for lesson numbers) and a "fallback" version
    /// so diagnostics can tell it apart from a loaded map.
    private static var fallbackDocument: MapDocument {
        let parts: [MapPart] = fallbackParts.map { part in
            let chapters: [MapChapter] = part.bookNumbers.map { book in
                MapChapter(
                    id: "ch\(fallbackOrder[book - 1])",
                    bookNumber: book,
                    lessons: []
                )
            }
            return MapPart(part: part.number, title: part.title, chapters: chapters)
        }
        return MapDocument(
            version: "fallback",
            status: "fallback",
            parts: parts,
            heldOut: [MapHeldOut(id: "ch37", bookNumber: nil, reason: nil)]
        )
    }

    // MARK: - Derived lookups (built once from the loaded map)

    /// The version string of the map in use (for example
    /// "v1.1-numbering-1115"). The same version string ships on
    /// the website and in the bundled copy; parity across
    /// platforms is checked against this value.
    static var mapVersion: String { loaded.version }

    /// The status string of the map in use, as shipped in the
    /// JSON ("draft" while the structure awaits sign-off).
    static var mapStatus: String { loaded.status }

    /// The ten parts of the book, in reading order.
    static let parts: [BookPart] = {
        loaded.parts.map { part in
            let books = part.chapters.map(\.bookNumber)
            let range = (books.min() ?? 1)...(books.max() ?? 1)
            return BookPart(number: part.part, title: part.title, bookNumbers: range)
        }
    }()

    /// Chapter ids in reading order. Index 0 is Book Chapter 1.
    static let orderedChapters: [String] = {
        loaded.parts.flatMap(\.chapters).sorted { $0.bookNumber < $1.bookNumber }.map(\.id)
    }()

    /// Lesson ids in reading order, as listed in the map. Lessons
    /// added after the bundled map was cut are absent here; live
    /// navigation uses the loaded catalogue instead (see
    /// ContentService.readingOrderLessons).
    static let orderedLessons: [String] = {
        loaded.parts
            .flatMap(\.chapters)
            .sorted { $0.bookNumber < $1.bookNumber }
            .flatMap(\.lessons)
            .map(\.id)
    }()

    /// Internal chapter numbers in reading order, derived from the
    /// map. Index 0 is Book Chapter 1.
    static let internalNumbersInReadingOrder: [Int] = {
        orderedChapters.compactMap { chapterID in
            guard chapterID.hasPrefix("ch") else { return nil }
            return Int(chapterID.dropFirst(2))
        }
    }()

    /// Internal chapter numbers held outside the main reading
    /// path, with no book number.
    static let heldOutInternalNumbers: Set<Int> = {
        Set(loaded.heldOut.compactMap { held in
            guard held.id.hasPrefix("ch") else { return nil }
            return Int(held.id.dropFirst(2))
        })
    }()

    /// Book number by chapter id, built once from the map.
    /// First-wins on duplicates, so a malformed copy can never
    /// crash the lookup build (validated copies have none).
    private static let bookByChapterID: [String: Int] = {
        Dictionary(
            loaded.parts.flatMap(\.chapters).map { ($0.id, $0.bookNumber) },
            uniquingKeysWith: { first, _ in first }
        )
    }()

    /// Display lesson number by lesson id, built once from the map.
    /// First-wins on duplicates, as above.
    private static let displayByLessonID: [String: Int] = {
        Dictionary(
            loaded.parts.flatMap(\.chapters).flatMap(\.lessons).map { ($0.id, $0.displayNumber) },
            uniquingKeysWith: { first, _ in first }
        )
    }()

    /// Part by chapter id, built once from the map.
    private static let partByChapterID: [String: BookPart] = {
        var result: [String: BookPart] = [:]
        for part in parts {
            for book in part.bookNumbers {
                if let id = chapterID(forBookNumber: book) {
                    result[id] = part
                }
            }
        }
        return result
    }()

    private static func chapterID(forBookNumber bookNumber: Int) -> String? {
        guard (1...orderedChapters.count).contains(bookNumber) else { return nil }
        return orderedChapters[bookNumber - 1]
    }

    // MARK: - Resolution (the one display-number resolver)

    /// The book chapter number for a chapter id ("ch38" to 26),
    /// or nil when the chapter is held out or unknown. Nil means
    /// "show no number", never "show the internal number".
    static func bookNumber(forChapterID chapterID: String) -> Int? {
        bookByChapterID[chapterID]
    }

    /// The book chapter number for an internal chapter number, or
    /// nil when the chapter is held out or unknown.
    static func bookNumber(forInternalNumber number: Int) -> Int? {
        bookByChapterID["ch\(number)"]
    }

    /// The display lesson number for a lesson id, from the map, or
    /// nil when the lesson is supplemental, held out, or not
    /// listed in the map yet. Callers fall back to the sequential
    /// position in the chapter, then to the s-number.
    static func displayNumber(forLessonID lessonID: String) -> Int? {
        displayByLessonID[lessonID]
    }

    /// The internal chapter number for a book chapter number, or
    /// nil when the book number is out of range.
    static func internalNumber(forBookNumber bookNumber: Int) -> Int? {
        guard let id = chapterID(forBookNumber: bookNumber), id.hasPrefix("ch") else { return nil }
        return Int(id.dropFirst(2))
    }

    /// The part holding a chapter id, or nil when the chapter is
    /// held out or unknown.
    static func part(forChapterID chapterID: String) -> BookPart? {
        partByChapterID[chapterID]
    }

    /// The part holding an internal chapter, or nil when the
    /// chapter is held out or unknown.
    static func part(forInternalNumber number: Int) -> BookPart? {
        partByChapterID["ch\(number)"]
    }

    /// The part holding a book chapter number, or nil when the
    /// book number is out of range.
    static func part(forBookNumber bookNumber: Int) -> BookPart? {
        parts.first { $0.bookNumbers.contains(bookNumber) }
    }

    /// True when the internal chapter is held outside the main
    /// reading path and must be shown without a book number.
    static func isHeldOut(internalNumber number: Int) -> Bool {
        heldOutInternalNumbers.contains(number)
    }

    /// Sort key for reading order: 0-based book position for
    /// chapters in the book, after every book chapter for held-out
    /// and unknown chapters (in internal-number order there), so
    /// sorting by this key never drops or duplicates a chapter.
    static func readingOrderIndex(forInternalNumber number: Int) -> Int {
        if let book = bookByChapterID["ch\(number)"] { return book - 1 }
        return 1000 + min(max(number, 0), 9999)
    }

    /// The learner-facing chapter label ("Chapter 26") for an
    /// internal chapter number, or nil when the chapter has no
    /// book number. Callers with no label show the chapter title
    /// with no number.
    static func chapterLabel(forInternalNumber number: Int) -> String? {
        guard let book = bookByChapterID["ch\(number)"] else { return nil }
        return "Chapter \(book)"
    }

    /// The neighbouring chapters in reading order, as internal
    /// chapter numbers, for prev/next chapter footers. The first
    /// book chapter has no previous, the last has no next, and a
    /// held-out or unknown chapter has neither.
    static func adjacentChapters(forInternalNumber number: Int) -> (previous: Int?, next: Int?) {
        guard let index = internalNumbersInReadingOrder.firstIndex(of: number) else {
            return (nil, nil)
        }
        let previous = index > 0 ? internalNumbersInReadingOrder[index - 1] : nil
        let next = index + 1 < internalNumbersInReadingOrder.count ? internalNumbersInReadingOrder[index + 1] : nil
        return (previous, next)
    }

    /// The next lesson id in map reading order, or nil at the end
    /// of the map or for an id the map does not list.
    static func nextLesson(after lessonID: String) -> String? {
        guard let index = orderedLessons.firstIndex(of: lessonID),
              index + 1 < orderedLessons.count else { return nil }
        return orderedLessons[index + 1]
    }

    /// The previous lesson id in map reading order, or nil at the
    /// start of the map or for an id the map does not list.
    static func previousLesson(before lessonID: String) -> String? {
        guard let index = orderedLessons.firstIndex(of: lessonID), index > 0 else { return nil }
        return orderedLessons[index - 1]
    }

    /// Lessons in reading order: chapters in book order (held-out
    /// chapters last), catalogue lessons before supplemental
    /// lessons within a chapter, then the map display number (or
    /// the lesson s-number when the map does not list the lesson).
    /// New lessons take the next sequential s-number in their
    /// chapter, so s-number order is reading order inside a
    /// chapter without any map change.
    static func sortedForReading(_ lessons: [SearchEntry]) -> [SearchEntry] {
        lessons.sorted { a, b in
            let aOrder = readingOrderIndex(forInternalNumber: a.chapterNumber ?? 0)
            let bOrder = readingOrderIndex(forInternalNumber: b.chapterNumber ?? 0)
            if aOrder != bOrder { return aOrder < bOrder }
            if a.isSupplemental != b.isSupplemental { return !a.isSupplemental }
            let aLesson = displayByLessonID[a.id] ?? a.lessonNumber ?? Int.max
            let bLesson = displayByLessonID[b.id] ?? b.lessonNumber ?? Int.max
            if aLesson != bLesson { return aLesson < bLesson }
            return a.id < b.id
        }
    }
}
