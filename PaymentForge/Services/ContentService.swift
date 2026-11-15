// ContentService.swift
// Payments Training Hub iOS - Loads content from the live website so it stays current.
// No backend of its own. If a live fetch fails, the caller shows a clear
// error with Retry, never a silent failure.

import Foundation
import Combine

/// Where a loaded lesson detail came from. `live` means the lesson
/// page was fetched from the website (or, for supplemental lessons,
/// built locally with no network, which is never stale). `cached`
/// means the live fetch failed and a page saved on this device from
/// a previous open was used instead. Views show an honest banner
/// for cached detail, never presenting it as live.
enum LessonDetailSource: Equatable {
    case live
    case cached
}

/// Fetches the catalogue and lesson content from paymentstraininghub.com.
final class ContentService: ObservableObject {
    static let shared = ContentService()

    // MARK: - Endpoints

    static let siteBase = URL(string: "https://www.paymentstraininghub.com")!
    static let searchIndexURL = URL(string: "https://www.paymentstraininghub.com/assets/search-index.json")!
    static let situationsDataURL = URL(string: "https://www.paymentstraininghub.com/assets/situations-data.js")!
    static let weeklyCasesDataURL = URL(string: "https://www.paymentstraininghub.com/assets/weekly-cases-data.js")!
    static let primaryAudioBase = "https://paymentforge-audio.pages.dev/audio/"
    static let fallbackAudioBase = "https://paymentforge-audio-backup.pages.dev/audio/"

    /// The 2 free Payment Situations samples, ungated for everyone.
    /// Kept in step with ProductCatalogue.freeSampleSituationIDs,
    /// which is the authoritative list. Only these two situations
    /// are free; every other situation needs Practice Experiences
    /// (or the Integrated Course).
    static let freeSampleIDs: [String] = ProductCatalogue.freeSampleSituationIDs

    /// The 8-session guided path. Session titles and descriptions are the
    /// site's own guided path, chapters are resolved from the search index.
    /// Within each session, chapters run from scratch to depth: a hook
    /// chapter first, fundamentals before the deep dives that assume them,
    /// and the payoff chapter last. Session 7 keeps its original order; it
    /// already climbed cleanly. Every chapter that teaches those topics is
    /// in a session; chapters outside the core flow (bank profiles, hub
    /// architecture, AI product chapters) stay in the app under Learn,
    /// reachable but not in the main path. Nothing is deleted: leaving a
    /// chapter out of the path never removes its lessons from the app.
    static let guidedSessions: [GuidedSession] = [
        GuidedSession(id: 1, title: "What a payment is", description: "Foundations, parties, accounts and the payment lifecycle.", chapterIDs: ["ch69", "ch1", "ch2", "ch64", "ch3", "ch70", "ch4", "ch71", "ch90"]),
        GuidedSession(id: 2, title: "How money moves", description: "Rails, clearing and settlement, correspondent banking.", chapterIDs: ["ch13", "ch17", "ch18", "ch72", "ch19", "ch20", "ch46", "ch74", "ch94", "ch77", "ch88", "ch89", "ch27"]),
        GuidedSession(id: 3, title: "SWIFT and messages", description: "MT and MX messages, field-level reading, UETR tracking.", chapterIDs: ["ch54", "ch5", "ch14", "ch6", "ch53", "ch50", "ch52", "ch75"]),
        GuidedSession(id: 4, title: "ISO 20022 in depth", description: "pain, pacs and camt messages, migration and mapping.", chapterIDs: ["ch8", "ch7", "ch60", "ch76", "ch39", "ch67", "ch73", "ch55"]),
        GuidedSession(id: 5, title: "Schemes and rails", description: "SEPA, Faster Payments, CHAPS, BACS, Fedwire and CHIPS.", chapterIDs: ["ch9", "ch33", "ch10", "ch92", "ch11", "ch93", "ch61", "ch62", "ch56", "ch57", "ch59", "ch12", "ch91", "ch30", "ch34", "ch83"]),
        GuidedSession(id: 6, title: "Exceptions, risk and compliance", description: "Returns, recalls, investigations, risk and AML.", chapterIDs: ["ch41", "ch16", "ch58", "ch40", "ch23", "ch95", "ch24", "ch81", "ch86", "ch65", "ch87"]),
        GuidedSession(id: 7, title: "Cards", description: "Card payments, authorisation, clearing and chargebacks.", chapterIDs: ["ch21", "ch22", "ch31", "ch63", "ch78"]),
        GuidedSession(id: 8, title: "Practice and interview", description: "Scenarios and interview questions to practise what you have learned.", chapterIDs: ["ch15", "ch28", "ch38", "ch42", "ch44", "ch84", "ch29"])
    ]

    // MARK: - Published state

    @Published private(set) var searchIndex: SearchIndex? = nil
    @Published private(set) var isLoadingIndex = false
    @Published private(set) var indexError: String? = nil

    /// True when the catalogue or situations on screen came from the
    /// local cache because the live fetch failed. Views show the
    /// PFOfflineBanner when this is true, so cached content is never
    /// presented as if it were live. False after a successful fetch.
    @Published private(set) var isShowingCachedContent = false

    /// Disk-cache file names in the caches directory. Content only:
    /// no downloads, no audio, no user data.
    static let searchIndexCacheFile = "pf-search-index.json"
    static let situationsCacheFile = "pf-situations-data.js"
    static let weeklyCasesCacheFile = "pf-weekly-cases-data.js"

    /// Authenticated situations delivery, OFF by default. While
    /// false, loadFullSituations behaves exactly as before: the
    /// public situations file plus the public cache file, for every
    /// caller. Keep this false until the owner approves enforcement
    /// and the situations-content endpoint is deployed and verified.
    /// Flipping it on without a deployed endpoint degrades
    /// gracefully per the matrix on loadFullSituations: signed-in
    /// users fall back to the endpoint cache or to search-index
    /// entries, and guests keep the public-file path. Never flip
    /// this on as part of any other change.
    static let authenticatedSituationsDeliveryEnabled = false

    /// Disk-cache file for responses from the authenticated
    /// situations-content endpoint. Separate from situationsCacheFile
    /// on purpose: the two caches hold different payloads (the
    /// endpoint JSON envelope versus the public JS assignment file)
    /// and must never be read in place of each other. Only the
    /// flag-on, signed-in path reads or writes this file.
    ///
    /// Cache note: the pre-existing public cache file may hold full
    /// content fetched while the flag was off. The flag-on path
    /// deliberately never reads that file for signed-in users, but
    /// the bytes already on a device stay there until the cache is
    /// purged or the app is removed. True enforcement is a future
    /// stage and requires the public file itself to stop serving
    /// full content; this client change alone does not enforce it.
    static let authenticatedSituationsCacheFile = "pf-situations-data-auth.js"

    /// The situations-content Edge Function URL, nil when Supabase
    /// is not configured. The function name is part of the shared
    /// contract with the server build; do not rename it here alone.
    private static var situationsContentURL: URL? {
        guard let base = SupabaseConfig.functionsBaseURL else { return nil }
        return base.appendingPathComponent("situations-content")
    }

    /// The caches-directory URL for one cache file.
    static func cacheFileURL(fileName: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(fileName)
    }

    /// Save raw fetched bytes to the disk cache. Best effort: a
    /// failed write never fails the load that just succeeded.
    static func saveCache(_ data: Data, fileName: String) {
        try? data.write(to: cacheFileURL(fileName: fileName), options: [.atomic])
    }

    /// The cached bytes for one file, nil when nothing was cached.
    static func loadCache(fileName: String) -> Data? {
        try? Data(contentsOf: cacheFileURL(fileName: fileName))
    }

    /// The full situations data (ContentManifest.situationCount items), when it has loaded.
    /// Nil until the fetch succeeds; the list falls back to the
    /// search index entries so it never goes empty.
    @Published private(set) var fullSituations: [FullSituationItem]? = nil
    @Published private(set) var isLoadingSituations = false

    /// The dedicated weekly-case list (52 items, in week order),
    /// when it has loaded. Nil until the fetch succeeds; the
    /// weekly view falls back to the catalogue pick while it is
    /// nil, so the feature never breaks before the asset is
    /// deployed. The items share the FullSituationItem shape; the
    /// extra `week` field in the file is ignored by the decoder.
    @Published private(set) var weeklyCases: [FullSituationItem]? = nil
    @Published private(set) var isLoadingWeeklyCases = false

    private init() {}

    // MARK: - Search index

    /// Load the search index (1,625 entries). Call once at launch.
    /// Bounded retry (3 attempts, exponential backoff). When every
    /// attempt fails, the last cached catalogue is used instead, so
    /// the app shows saved content with an offline note rather than
    /// a blank screen; only when there is no cache at all does the
    /// caller see indexError with a Retry action. Fetch once, parse
    /// once: the guard below means a loaded index is never fetched
    /// or decoded again. Decoding, the supplemental merge and the
    /// cache read and write all run off the main thread: this
    /// function is MainActor, and decoding 1,625 entries inline
    /// used to freeze the interface at launch and on every Retry.
    /// Only the published-state assignments happen on the main
    /// actor, after each background step suspends back here.
    @MainActor
    func loadSearchIndex() async {
        if searchIndex != nil || isLoadingIndex { return }
        isLoadingIndex = true
        indexError = nil
        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(from: Self.searchIndexURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw ContentError.badResponse
                }
                let decoded = try await Self.decodeSearchIndexOffMainThread(data)
                searchIndex = decoded
                await Self.saveCacheOffMainThread(data, fileName: Self.searchIndexCacheFile)
                isShowingCachedContent = false
                isLoadingIndex = false
                return
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
                }
            }
        }
        if let cached = await Self.loadCacheOffMainThread(fileName: Self.searchIndexCacheFile),
           let decoded = try? await Self.decodeSearchIndexOffMainThread(cached) {
            searchIndex = decoded
            isShowingCachedContent = true
            indexError = nil
        } else {
            indexError = "Could not load the course catalogue. Check your connection and try again."
            isShowingCachedContent = false
        }
        isLoadingIndex = false
    }

    /// Decode fetched index bytes and merge the supplemental
    /// lessons, off the main thread. Pure: no published state is
    /// touched here, so the detached task never races the UI.
    private static func decodeSearchIndexOffMainThread(_ data: Data) async throws -> SearchIndex {
        try await Task.detached(priority: .userInitiated) {
            try decodeSearchIndex(from: data)
        }.value
    }

    /// Decode one index document and merge the supplemental
    /// lessons in. Nonisolated and synchronous, so it can run on
    /// a detached task; the only caller is the helper above.
    private static func decodeSearchIndex(from data: Data) throws -> SearchIndex {
        let decoded = try JSONDecoder().decode(SearchIndex.self, from: data)
        return indexWithSupplemental(decoded)
    }

    /// Save raw fetched bytes to the disk cache, off the main
    /// thread. The write itself is the existing saveCache; only
    /// the thread it runs on changes.
    private static func saveCacheOffMainThread(_ data: Data, fileName: String) async {
        await Task.detached(priority: .utility) {
            saveCache(data, fileName: fileName)
        }.value
    }

    /// Read cached bytes, off the main thread. The read itself is
    /// the existing loadCache; only the thread it runs on changes.
    private static func loadCacheOffMainThread(fileName: String) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            loadCache(fileName: fileName)
        }.value
    }

    // MARK: - Supplemental lessons (v34)

    /// Supplemental lessons written for v34 to cover CIPSP and
    /// Payment Guru syllabus topics the website catalogue does not
    /// teach in depth. Bundled with the app as
    /// supplemental-lessons.json, so they work offline too. Nil when
    /// the file is missing; the app never fails to load without them.
    /// Read from the bundle once and cached: the old version read
    /// and decoded the file on every merge. The static cache
    /// initialises lazily and thread-safely on first access, which
    /// happens on the detached decode task, never on the main thread.
    static func supplementalEntries() -> [SearchEntry] {
        cachedSupplementalEntries
    }

    private static let cachedSupplementalEntries: [SearchEntry] = {
        guard let url = Bundle.main.url(forResource: "supplemental-lessons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([SearchEntry].self, from: data) else {
            return []
        }
        return entries
    }()

    // MARK: - Supplemental flow descriptors (v82)

    /// One entry of supplemental-lessons.json as read for its flow
    /// descriptor. Every field is optional: a missing or malformed
    /// flow degrades to the old empty-beats detail, never a crash.
    /// The `text`, `title`, `type` and `url` keys are deliberately
    /// not decoded here; SearchEntry already carries them.
    private struct SupplementalFlowDocument: Decodable {
        let id: String?
        let flow: SupplementalFlow?
    }

    /// The flow/diagram descriptor for one supplemental lesson,
    /// authored from the lesson's own text. `kind` is "flow" for
    /// lessons whose text describes an ordered sequence (shown
    /// with arrows) and "diagram" for lessons structured as parts,
    /// aspects, or comparisons (shown with a plain rail). Any
    /// other value behaves like "diagram": no arrows, no crash.
    private struct SupplementalFlow: Decodable {
        let kind: String?
        let steps: [SupplementalFlowStep]?
    }

    private struct SupplementalFlowStep: Decodable {
        let title: String?
        let note: String?
    }

    /// The flow descriptor for each supplemental lesson id, read
    /// from the bundle once and cached, like the entries above.
    /// Empty when the file is missing or undecodable; the lesson
    /// detail then falls back to no beats, exactly as before.
    private static let supplementalFlowsByID: [String: SupplementalFlow] = {
        guard let url = Bundle.main.url(forResource: "supplemental-lessons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let documents = try? JSONDecoder().decode([SupplementalFlowDocument].self, from: data) else {
            return [:]
        }
        var flows: [String: SupplementalFlow] = [:]
        for document in documents {
            guard let id = document.id, let flow = document.flow else { continue }
            flows[id] = flow
        }
        return flows
    }()

    /// The untimed beats for a supplemental lesson, from its flow
    /// descriptor steps, in order. Beat times are all zero: no
    /// per-beat timings exist for supplemental lessons, and none
    /// are invented. LessonView treats supplemental beats as
    /// untimed and never highlights or seeks from them. Steps
    /// with an empty title are skipped; a missing descriptor
    /// yields no beats.
    private static func supplementalBeats(for entry: SearchEntry) -> [LessonBeat] {
        guard let flow = supplementalFlowsByID[entry.id],
              let steps = flow.steps else { return [] }
        var beats: [LessonBeat] = []
        for (index, step) in steps.enumerated() {
            let title = (step.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            beats.append(LessonBeat(
                id: "\(entry.id)-beat-\(index)",
                startTime: 0,
                endTime: 0,
                title: title,
                note: (step.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return beats
    }

    /// The flow diagram SVG for a supplemental flow lesson, built
    /// from its flow steps. Only "flow" lessons get one: the
    /// diagram's presence is what makes LessonView draw arrows
    /// between the flow points, matching website flow lessons.
    /// "diagram" lessons return nil and render with a plain rail,
    /// matching website lessons without a flow diagram. Colours
    /// are the design tokens (pfNavy, pfRoyal) as hex values.
    /// Titles are XML-escaped and wrapped, so no lesson text can
    /// break the markup. The SVG itself is only shown by the
    /// dormant full-screen visual; the inline lesson view renders
    /// the native flow from the beats.
    private static func supplementalFlowSVG(for entry: SearchEntry) -> String? {
        guard let flow = supplementalFlowsByID[entry.id],
              flow.kind == "flow",
              let steps = flow.steps else { return nil }
        let titles = steps
            .map { ($0.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !titles.isEmpty else { return nil }
        let width = 360.0
        let boxX = 16.0
        let boxWidth = width - 2 * boxX
        let centreX = width / 2
        let gap = 26.0
        var parts: [String] = []
        var totalHeight = 0.0
        var boxes: [(top: Double, height: Double, lines: [String], index: Int)] = []
        for (index, title) in titles.enumerated() {
            let lines = wrappedLines(title, maxLength: 34)
            let height = 24.0 + Double(lines.count) * 20.0
            let top = totalHeight
            boxes.append((top: top, height: height, lines: lines, index: index))
            totalHeight += height
            if index < titles.count - 1 { totalHeight += gap }
        }
        for box in boxes {
            var textLines = ""
            for (lineIndex, line) in box.lines.enumerated() {
                let baseline = box.top + 28.0 + Double(lineIndex) * 20.0
                textLines += "<text x=\"\(centreX)\" y=\"\(baseline)\" text-anchor=\"middle\" font-family=\"-apple-system, Helvetica, Arial, sans-serif\" font-size=\"15\" font-weight=\"600\" fill=\"#0D1C38\">\(escapeXML(line))</text>"
            }
            parts.append("<g data-beat=\"\(box.index)\"><rect x=\"\(boxX)\" y=\"\(box.top)\" width=\"\(boxWidth)\" height=\"\(box.height)\" rx=\"10\" fill=\"#FFFFFF\" stroke=\"#17408C\" stroke-width=\"1.5\"/>\(textLines)</g>")
            if box.index < boxes.count - 1 {
                let gapTop = box.top + box.height
                let gapBottom = gapTop + gap
                parts.append("<line x1=\"\(centreX)\" y1=\"\(gapTop + 2)\" x2=\"\(centreX)\" y2=\"\(gapBottom - 8)\" stroke=\"#17408C\" stroke-width=\"2\"/>")
                parts.append("<polygon points=\"\(centreX),\(gapBottom - 2) \(centreX - 7),\(gapBottom - 11) \(centreX + 7),\(gapBottom - 11)\" fill=\"#17408C\"/>")
            }
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(Int(width)) \(Int(totalHeight))\" width=\"100%\" role=\"img\"><title>Lesson flow diagram</title>\(parts.joined())</svg>"
    }

    /// Wrap text into lines of at most `maxLength` characters,
    /// breaking only at spaces. A single over-long word stays on
    /// its own line rather than being split mid-word.
    private static func wrappedLines(_ text: String, maxLength: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= maxLength {
                current += " " + word
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [text] : lines
    }

    /// Escape text for inclusion in generated SVG markup.
    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The search index with the supplemental lessons merged in, so
    /// they appear in lessons, chapters, sessions and search
    /// exactly like catalogue lessons. Counts are updated, so
    /// the About numbers stay honest.
    private static func indexWithSupplemental(_ index: SearchIndex) -> SearchIndex {
        let extra = supplementalEntries()
        guard !extra.isEmpty else { return index }
        let lessons = extra.filter { $0.type == .lesson }.count
        let guides = extra.filter { $0.type == .guide }.count
        let situations = extra.filter { $0.type == .situation }.count
        let labs = extra.filter { $0.type == .lab }.count
        let tests = extra.filter { $0.type == .test }.count
        let faqs = extra.filter { $0.type == .faq }.count
        let counts = SearchCounts(
            lesson: index.counts.lesson + lessons,
            guide: index.counts.guide + guides,
            situation: index.counts.situation + situations,
            lab: index.counts.lab + labs,
            test: index.counts.test + tests,
            faq: index.counts.faq + faqs,
            total: index.counts.total + extra.count
        )
        return SearchIndex(counts: counts, entries: index.entries + extra)
    }

    /// All lessons, in catalogue order.
    var allLessons: [SearchEntry] {
        searchIndex?.entries.filter { $0.type == .lesson } ?? []
    }

    /// All lessons in book reading order: chapters in the order
    /// learners read them, catalogue lessons before supplemental
    /// lessons within a chapter. The order for prev/next lesson
    /// navigation and for "continue reading". Catalogue order
    /// (allLessons) is unchanged: it feeds position and gating
    /// logic that must not move.
    var readingOrderLessons: [SearchEntry] {
        PFBookModeReadingOrder.sortedForReading(allLessons)
    }

    /// True once the reading-order refresh has been attempted
    /// this launch, so the website copy is fetched at most once.
    private var didAttemptReadingOrderRefresh = false

    /// Refresh the reading-order map from the website copy, once
    /// per launch. Silent on every failure: the bundled copy (or
    /// the cached copy) stays in use. The refreshed copy takes
    /// effect on the next launch; see PFBookModeReadingOrder.
    @MainActor
    func refreshReadingOrderIfNeeded() async {
        guard !didAttemptReadingOrderRefresh else { return }
        didAttemptReadingOrderRefresh = true
        await PFBookModeReadingOrder.refreshFromWebsite()
    }

    /// The book position of a lesson: its 1-based index among the
    /// in-book lessons in reading order, and the in-book total.
    /// Nil for held-out lessons and for lessons not in the loaded
    /// catalogue. Supplemental lessons count: they sit inside
    /// their chapter in reading order.
    func bookPosition(for entry: SearchEntry) -> (position: Int, total: Int)? {
        guard let number = entry.chapterNumber,
              !PFBookModeReadingOrder.isHeldOut(internalNumber: number) else { return nil }
        let sequence = readingOrderLessons.filter {
            guard let chapter = $0.chapterNumber else { return false }
            return !PFBookModeReadingOrder.isHeldOut(internalNumber: chapter)
        }
        guard let index = sequence.firstIndex(where: { $0.id == entry.id }) else { return nil }
        return (index + 1, sequence.count)
    }

    /// The sequential position (1-based) of a regular lesson
    /// within its chapter, in catalogue order, counting catalogue
    /// lessons only. Supplemental lessons return nil: they sit
    /// after the chapter's catalogue lessons and have no lesson
    /// number. Returns nil when the entry is not a lesson, when
    /// the chapter cannot be parsed, or when the entry is not in
    /// the loaded index.
    func lessonPositionInChapter(for entry: SearchEntry) -> Int? {
        guard entry.type == .lesson, !entry.isSupplemental,
              let number = entry.chapterNumber else { return nil }
        let chapterLessons = allLessons.filter {
            $0.chapterNumber == number && !$0.isSupplemental
        }
        guard let index = chapterLessons.firstIndex(where: { $0.id == entry.id }) else { return nil }
        return index + 1
    }

    /// The citation for an entry, numbering regular lessons by
    /// sequential position within the chapter in catalogue order
    /// instead of the raw number parsed from the id, with the
    /// chapter shown as its book number from
    /// PFBookModeReadingOrder. Supplemental lessons show the
    /// chapter only, with no misleading number. Falls back to the
    /// entry's own citation when the position cannot be computed,
    /// so a citation is always produced.
    func citation(for entry: SearchEntry) -> String {
        if entry.type == .lesson, !entry.isSupplemental,
           let chapter = entry.chapterNumber,
           let book = PFBookModeReadingOrder.bookNumber(forInternalNumber: chapter),
           let position = lessonPositionInChapter(for: entry) {
            return "Chapter \(book), Lesson \(position): \(entry.title)"
        }
        return entry.citation
    }

    /// All guides, in catalogue order.
    var allGuides: [SearchEntry] {
        searchIndex?.entries.filter { $0.type == .guide } ?? []
    }

    /// All situations, in catalogue order.
    var allSituations: [SearchEntry] {
        searchIndex?.entries.filter { $0.type == .situation } ?? []
    }

    /// All labs, in catalogue order. The order decides the free
    /// lab samples (see EntryAccessRules).
    var allLabs: [SearchEntry] {
        searchIndex?.entries.filter { $0.type == .lab } ?? []
    }

    /// All FAQ entries, in catalogue order. The order decides the
    /// free FAQ samples (see EntryAccessRules).
    var allFAQs: [SearchEntry] {
        searchIndex?.entries.filter { $0.type == .faq } ?? []
    }

    // MARK: - Full situations data

    /// Load the full situations data, either from the public file or
    /// from the authenticated endpoint, depending on the flag and on
    /// whether a signed-in JWT is available. The flag-on path never
    /// changes entitlement logic: the server decides which items to
    /// return, the SituationsView hard-gate still decides what is
    /// shown, and StoreManager semantics are untouched.
    ///
    /// Fallback matrix:
    /// Flag off, guest or signed-in: public file, 3 attempts, then
    /// the public cache file, else fullSituations stays nil and
    /// callers fall back to search-index entries. Exactly as before.
    /// Flag on, guest (no JWT): the same public-file path, unchanged.
    /// Flag on, signed-in, endpoint succeeds: the returned items are
    /// stored as-is (all items when entitled is true, only the free
    /// samples when entitled is false) and the response is cached in
    /// the separate endpoint cache file.
    /// Flag on, signed-in, endpoint down or undecodable: the endpoint
    /// cache is used when present, else fullSituations stays nil and
    /// callers fall back to search-index entries. The public file and
    /// the public cache file are never read on this path.
    /// Weekly cases are untouched by every row: they always load
    /// from their own public asset in loadWeeklyCases.
    @MainActor
    func loadFullSituations() async {
        if fullSituations != nil || isLoadingSituations { return }
        if Self.authenticatedSituationsDeliveryEnabled,
           let accessToken = await AuthService.shared.validAccessToken() {
            await loadFullSituationsViaAuthenticatedEndpoint(accessToken: accessToken)
            return
        }
        await loadFullSituationsFromPublicFile()
    }

    /// The original public-file path for loadFullSituations, moved
    /// here unchanged in behavior so the dispatcher above can choose
    /// between it and the endpoint path. Load the full situations
    /// data file (ContentManifest.situationCount items with the full
    /// explain text and visual). The file is a JS assignment
    /// (window.PA_SITUATIONS = [...];) so the prefix and trailing
    /// semicolon are stripped before JSON decoding. Bounded retry
    /// (3 attempts, exponential backoff); on failure the cached
    /// file is used when one exists, and fullSituations stays nil
    /// otherwise so callers fall back to the search index entries
    /// and the list never goes empty.
    @MainActor
    private func loadFullSituationsFromPublicFile() async {
        isLoadingSituations = true
        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(from: Self.situationsDataURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      var text = String(data: data, encoding: .utf8) else {
                    throw ContentError.badResponse
                }
                let prefix = "window.PA_SITUATIONS = "
                guard text.hasPrefix(prefix) else { throw ContentError.badResponse }
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasSuffix(";") { text = String(text.dropLast()) }
                guard let jsonData = text.data(using: .utf8) else { throw ContentError.badResponse }
                let decoded = try JSONDecoder().decode([FullSituationItem].self, from: jsonData)
                fullSituations = decoded
                Self.saveCache(data, fileName: Self.situationsCacheFile)
                // Do not clear isShowingCachedContent here: the flag
                // belongs to the catalogue load, which may have fallen
                // back to cache even when this file loads live.
                isLoadingSituations = false
                return
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
                }
            }
        }
        if let cached = Self.loadCache(fileName: Self.situationsCacheFile),
           var text = String(data: cached, encoding: .utf8) {
            let prefix = "window.PA_SITUATIONS = "
            if text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasSuffix(";") { text = String(text.dropLast()) }
                if let jsonData = text.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([FullSituationItem].self, from: jsonData) {
                    fullSituations = decoded
                    isShowingCachedContent = true
                }
            }
        }
        isLoadingSituations = false
    }

    /// One response from the situations-content endpoint. The server
    /// returns every item for an entitled caller and only the free
    /// samples otherwise; the client stores `items` as returned and
    /// never re-filters it. `entitled` is decoded so a malformed
    /// envelope fails the decode instead of being silently trusted.
    private struct AuthenticatedSituationsResponse: Decodable {
        let entitled: Bool
        let items: [FullSituationItem]
    }

    /// Load the full situations data from the authenticated
    /// situations-content endpoint for a signed-in user. The request
    /// is GET with Authorization Bearer <user JWT>, sent through
    /// SupabaseClient.request, which also sends the apikey header
    /// the Supabase gateway expects and retries transient failures
    /// internally, so no extra retry loop is added here. The JWT
    /// comes from AuthService.validAccessToken, which refreshes an
    /// expiring token first; no new auth mechanism is added.
    /// On success the returned items are stored as-is and the raw
    /// response is cached in the separate endpoint cache file. On
    /// any failure (no endpoint URL, network or server error, or an
    /// undecodable reply) the endpoint cache is used when present,
    /// else fullSituations stays nil so existing callers fall back
    /// to search-index entries. This path never reads the public
    /// file or the public cache file, and never falls back to them.
    /// See the cache note on authenticatedSituationsCacheFile for
    /// why the pre-existing public cache file is out of scope here.
    @MainActor
    private func loadFullSituationsViaAuthenticatedEndpoint(accessToken: String) async {
        isLoadingSituations = true
        defer { isLoadingSituations = false }
        if let url = Self.situationsContentURL {
            do {
                let data = try await SupabaseClient.shared.request(url: url, method: "GET", accessToken: accessToken)
                let decoded = try JSONDecoder().decode(AuthenticatedSituationsResponse.self, from: data)
                fullSituations = decoded.items
                Self.saveCache(data, fileName: Self.authenticatedSituationsCacheFile)
                // Do not clear isShowingCachedContent here: the flag
                // belongs to the catalogue load, which may have fallen
                // back to cache even when this fetch loads live.
                return
            } catch {
                // Fall through to the endpoint cache below.
            }
        }
        if let cached = Self.loadCache(fileName: Self.authenticatedSituationsCacheFile),
           let decoded = try? JSONDecoder().decode(AuthenticatedSituationsResponse.self, from: cached) {
            fullSituations = decoded.items
            isShowingCachedContent = true
        }
        // Otherwise fullSituations stays nil and callers fall back
        // to the search-index entries, as in the public-file path.
    }

    /// Load the dedicated weekly-case list (52 items in week
    /// order, with the full explain text and visual). Mirrors
    /// loadFullSituations: the file is a JS assignment
    /// (window.PA_WEEKLY_CASES = [...];) so the prefix and
    /// trailing semicolon are stripped before JSON decoding, with
    /// the same bounded retry (3 attempts, exponential backoff)
    /// and the same cache fallback. The asset is free public
    /// content, no purchase and no sign-in. On failure weeklyCases
    /// stays nil and callers keep the catalogue pick, so the
    /// weekly case never goes empty.
    @MainActor
    func loadWeeklyCases() async {
        if weeklyCases != nil || isLoadingWeeklyCases { return }
        isLoadingWeeklyCases = true
        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(from: Self.weeklyCasesDataURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      var text = String(data: data, encoding: .utf8) else {
                    throw ContentError.badResponse
                }
                let prefix = "window.PA_WEEKLY_CASES = "
                guard text.hasPrefix(prefix) else { throw ContentError.badResponse }
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasSuffix(";") { text = String(text.dropLast()) }
                guard let jsonData = text.data(using: .utf8) else { throw ContentError.badResponse }
                let decoded = try JSONDecoder().decode([FullSituationItem].self, from: jsonData)
                weeklyCases = decoded
                Self.saveCache(data, fileName: Self.weeklyCasesCacheFile)
                // Do not clear isShowingCachedContent here: the flag
                // belongs to the catalogue load, which may have fallen
                // back to cache even when this file loads live.
                isLoadingWeeklyCases = false
                return
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
                }
            }
        }
        if let cached = Self.loadCache(fileName: Self.weeklyCasesCacheFile),
           var text = String(data: cached, encoding: .utf8) {
            let prefix = "window.PA_WEEKLY_CASES = "
            if text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasSuffix(";") { text = String(text.dropLast()) }
                if let jsonData = text.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([FullSituationItem].self, from: jsonData) {
                    weeklyCases = decoded
                    isShowingCachedContent = true
                }
            }
        }
        isLoadingWeeklyCases = false
    }

    /// Stage names, the same six learning stages as the website.
    static let situationStageNames: [Int: String] = [
        1: "Payment mechanics",
        2: "Processing decisions",
        3: "Operational exceptions",
        4: "Cross-system consequences",
        5: "Complex banking scenarios",
        6: "Senior SME judgement"
    ]

    /// Where a situation's stage came from. `authoritative` means
    /// the live data file's own `stage` field; `stageMap` means the
    /// website per-item stage map; `levelFallback` means the level
    /// fallback (foundation to 1, advanced to 6, anything else to 3).
    /// Only `authoritative` is presented as the item's stage; the
    /// other two are derived and are labelled as such.
    enum SituationStageSource: Equatable {
        case authoritative
        case stageMap
        case levelFallback
    }

    /// The stage source for one full situation item.
    static func stageSource(forFullItem item: FullSituationItem) -> SituationStageSource {
        if let stage = item.stage, (1...6).contains(stage) {
            return .authoritative
        }
        if situationStageMap[item.id] != nil {
            return .stageMap
        }
        return .levelFallback
    }

    /// The stage for one full situation item. Priority: the data
    /// file's own `stage` field when it is present and in range
    /// (authoritative, verified for all ContentManifest.situationCount items on 11 Nov 2026),
    /// then the website per-item stage map, then the level fallback.
    /// No stage numbers are invented beyond that map and fallback.
    static func stage(forFullItem item: FullSituationItem) -> Int {
        if let stage = item.stage, (1...6).contains(stage) {
            return stage
        }
        if let mapped = situationStageMap[item.id], (1...6).contains(mapped) {
            return mapped
        }
        switch item.level.lowercased() {
        case "foundation": return 1
        case "advanced": return 6
        default: return 3
        }
    }

    /// The stage name for one full situation item: the data file's
    /// own `stage_name` when it is present and matches the resolved
    /// stage (verified for all ContentManifest.situationCount items on 11 Nov 2026), otherwise
    /// the standard name for the resolved stage.
    static func stageName(forFullItem item: FullSituationItem) -> String {
        let stage = stage(forFullItem: item)
        if stageSource(forFullItem: item) == .authoritative,
           let name = item.stageName, !name.isEmpty {
            return name
        }
        return stageName(for: stage)
    }

    /// The stage name for a stage number.
    static func stageName(for stage: Int) -> String {
        situationStageNames[stage] ?? "Stage \(stage)"
    }

    /// The per-item stage map from the website
    /// (content/premium-500/situation-stage-map.json). The 35 items
    /// added after the map was written are not in it and fall back
    /// by level. Generated from the map file; do not hand-edit.
    private static let situationStageMap: [String: Int] = [
        "ABH-01": 1, "ABH-02": 1, "ABH-03": 3, "ABH-04": 1,
        "ABH-05": 1, "ABH-06": 1, "ABH-07": 1, "ABH-08": 1,
        "ABH-09": 1, "ABH-10": 2, "ABH-11": 1, "ABH-12": 2,
        "ABH-13": 1, "ABH-14": 2, "ABH-15": 2, "ABH-16": 2,
        "ABH-17": 2, "ABH-18": 6, "ABH-19": 1, "ABH-20": 1,
        "ABH-21": 1, "ABH-22": 1, "ABH-23": 1, "ABH-24": 2,
        "ABH-25": 6, "ABH-26": 6, "ABH-27": 1, "ABH-28": 1,
        "ABH-29": 1, "ABH-30": 1, "ABH-31": 6, "ABH-32": 6,
        "ABH-33": 6, "ABH-34": 6, "ABH-35": 6, "ABH-36": 6,
        "ABH-37": 6, "ABH-38": 6, "ABH-39": 6, "ABH-40": 6,
        "ABH-41": 6, "ABH-42": 6, "ABH-43": 6, "ABH-44": 6,
        "ABH-45": 6, "ABH-46": 6, "ABH-47": 6, "ABH-48": 6,
        "ABH-49": 6, "ABH-50": 6, "INS-001": 1, "INS-002": 1,
        "INS-003": 2, "INS-004": 4, "INS-005": 3, "INS-006": 4,
        "INS-007": 6, "INS-008": 6, "INS-009": 6, "INS-010": 6,
        "INS-011": 6, "INS-012": 1, "INS-013": 6, "INS-014": 6,
        "INS-015": 6, "INS-016": 6, "INS-017": 6, "INS-018": 6,
        "INS-019": 6, "INS-020": 6, "INS-021": 6, "INS-022": 6,
        "INS-023": 6, "INS-024": 2, "INS-025": 6, "INS-026": 6,
        "INS-027": 1, "INS-028": 1, "INS-029": 1, "INS-030": 6,
        "INS-031": 1, "INS-032": 4, "INS-033": 4, "INS-034": 4,
        "INS-035": 4, "INS-036": 4, "INS-037": 6, "INS-038": 6,
        "INS-039": 6, "INS-040": 6, "INS-041": 6, "INS-042": 6,
        "INS-043": 6, "INS-044": 6, "INS-045": 6, "INS-046": 6,
        "INS-047": 6, "INS-048": 6, "INS-049": 6, "INS-050": 3,
        "INS-051": 6, "INS-052": 6, "INS-053": 6, "INS-054": 6,
        "INS-055": 6, "INS-056": 6, "INS-057": 4, "INS-058": 6,
        "INS-059": 6, "INS-060": 6, "INS-061": 6, "INS-062": 4,
        "INS-063": 6, "INS-064": 4, "INS-065": 6, "INS-066": 5,
        "INS-067": 6, "INS-068": 6, "INS-069": 1, "INS-070": 1,
        "INS-071": 4, "INS-072": 6, "INS-073": 6, "INS-074": 6,
        "INS-075": 6, "INS-076": 6, "INS-077": 6, "INS-078": 6,
        "INS-079": 6, "INS-080": 6, "INS-081": 6, "INS-082": 6,
        "INS-083": 6, "INS-084": 6, "INS-085": 6, "INS-086": 3,
        "INS-087": 3, "INS-088": 1, "INS-089": 6, "INS-090": 1,
        "INS-091": 6, "INS-092": 6, "INS-093": 6, "INS-094": 6,
        "INS-095": 6, "INS-096": 6, "INS-097": 6, "INS-098": 6,
        "INS-099": 6, "INS-100": 6, "INS-101": 1, "INS-102": 1,
        "INS-103": 4, "INS-104": 1, "INS-105": 1, "INS-106": 2,
        "INS-107": 2, "INS-108": 3, "INS-109": 3, "INS-110": 2,
        "INS-111": 2, "INS-112": 3, "INS-113": 2, "INS-114": 6,
        "INS-115": 6, "INS-116": 3, "INS-117": 2, "INS-118": 3,
        "INS-119": 6, "INS-120": 6, "INS-121": 1, "INS-122": 1,
        "INS-123": 1, "INS-124": 1, "INS-125": 1, "INS-126": 1,
        "INS-127": 5, "INS-128": 1, "INS-129": 3, "INS-130": 3,
        "INS-131": 3, "INS-132": 3, "INS-133": 3, "INS-134": 3,
        "INS-135": 5, "INS-136": 4, "INS-137": 5, "INS-138": 2,
        "INS-139": 1, "INS-140": 2, "INS-141": 5, "INS-142": 5,
        "INS-143": 5, "INS-144": 5, "INS-145": 2, "INS-146": 2,
        "INS-147": 4, "INS-148": 6, "INS-149": 2, "INS-150": 5,
        "INS-151": 4, "INS-152": 1, "INS-153": 5, "INS-154": 1,
        "INS-155": 1, "INS-156": 1, "INS-157": 1, "INS-158": 3,
        "INS-159": 3, "INS-160": 3, "INS-161": 3, "INS-162": 3,
        "INS-163": 1, "INS-164": 5, "INS-165": 1, "INS-166": 5,
        "INS-167": 5, "INS-168": 1, "INS-169": 2, "INS-170": 4,
        "JEB-A01": 6, "JEB-A02": 3, "JEB-A03": 3, "JEB-A04": 4,
        "JEB-A05": 3, "JEB-A06": 2, "JEB-A07": 2, "JEB-A08": 1,
        "JEB-A09": 2, "JEB-A10": 4, "JEB-A11": 1, "JEB-A12": 3,
        "JEB-A13": 1, "JEB-A14": 3, "JEB-A15": 4, "JEB-B01": 1,
        "JEB-B02": 2, "JEB-B03": 6, "JEB-B04": 1, "JEB-B05": 5,
        "JEB-B06": 6, "JEB-B07": 4, "JEB-B08": 2, "JEB-B09": 2,
        "JEB-B10": 6, "JEB-B11": 1, "JEB-B12": 2, "JEB-B13": 3,
        "JEB-B14": 1, "JEB-C01": 2, "JEB-C02": 4, "JEB-C03": 2,
        "JEB-C04": 1, "JEB-C05": 2, "JEB-C06": 2, "JEB-C07": 6,
        "JEB-C08": 1, "JEB-C09": 6, "JEB-C10": 6, "JEB-C11": 1,
        "JEB-C12": 3, "JEB-C13": 1, "JEB-C14": 6, "JEB-C15": 1,
        "JEB-D01": 1, "JEB-D02": 2, "JEB-D03": 1, "JEB-D04": 3,
        "JEB-D05": 3, "JEB-D06": 2, "JEB-D07": 5, "JEB-D08": 1,
        "JEB-D09": 5, "JEB-D10": 1, "JEB-D11": 1, "JEB-D12": 1,
        "JEB-D13": 5, "JEB-D14": 1, "JEB-D15": 5, "JEB-E01": 6,
        "JEB-E02": 3, "JEB-E03": 6, "JEB-E04": 3, "JEB-E05": 5,
        "JEB-E06": 4, "JEB-E07": 6, "JEB-E08": 2, "JEB-E09": 2,
        "JEB-E10": 1, "JEB-E11": 1, "JEB-E12": 1, "JEB-E13": 1,
        "JEB-E14": 1, "JEB-E15": 2, "JEB-F01": 6, "JEB-F02": 2,
        "JEB-F03": 6, "JEB-F04": 5, "JEB-F05": 6, "JEB-F06": 6,
        "JEB-F07": 2, "JEB-F08": 6, "JEB-F09": 6, "JEB-F10": 1,
        "JEB-F11": 2, "JEB-F12": 1, "JEB-F13": 5, "JEB-F14": 3,
        "PAI-C001": 1, "PAI-C002": 1, "PAI-C003": 2, "PAI-C004": 1,
        "PAI-C005": 1, "PAI-C006": 1, "PAI-C007": 1, "PAI-C008": 1,
        "PAI-C009": 3, "PAI-C010": 3, "PAI-C011": 3, "PAI-C012": 3,
        "PAI-C013": 3, "PAI-C014": 3, "PAI-C015": 3, "PAI-C016": 3,
        "PAI-C017": 3, "PAI-C018": 4, "PAI-C019": 4, "PAI-C020": 2,
        "PAI-C021": 3, "PAI-C022": 1, "PAI-C023": 1, "PAI-C024": 1,
        "PAI-C025": 4, "PAI-C026": 1, "PAI-C027": 3, "PAI-C028": 3,
        "PAI-C029": 3, "PAI-C030": 3, "PAI-C031": 3, "PAI-C032": 3,
        "PAI-C033": 1, "PAI-C034": 3, "PAI-C035": 2, "PAI-C036": 4,
        "PAI-C037": 3, "PAI-C038": 5, "PAI-C039": 1, "PAI-C040": 1,
        "PAI-C041": 1, "PAI-C042": 3, "PAI-C043": 1, "PAI-C044": 5,
        "PAI-C045": 2, "PAI-C046": 3, "PAI-C047": 4, "PAI-C048": 1,
        "PAI-C049": 5, "PAI-C050": 1, "PAI-C051": 5, "PAI-C052": 1,
        "PAI-C053": 3, "PAI-C054": 2, "PAI-C055": 1, "PAI-C056": 1,
        "PAI-C057": 1, "PAI-C058": 2, "PAI-C059": 1, "PAI-C060": 3,
        "PAI-C061": 2, "PAI-C062": 4, "PAI-C063": 1, "PAI-C064": 2,
        "PAI-C065": 1, "PAI-C066": 1, "PAI-C067": 5, "PAI-C068": 1,
        "PAI-C069": 1, "PAI-C070": 1, "PAI-C071": 5, "PAI-C072": 3,
        "PAI-C073": 3, "PAI-C074": 1, "PAI-C075": 4, "PAI-C076": 4,
        "PAI-C077": 1, "PAI-C078": 1, "PAI-C079": 1, "PAI-C080": 1,
        "PAI-C081": 1, "PAI-C082": 1, "PAI-C083": 1, "PAI-C084": 1,
        "PAI-C085": 1, "PAI-C086": 1, "PAI-C087": 1, "PAI-C088": 1,
        "PAI-C089": 4, "PAI-C090": 3, "PAI-C091": 1, "PAI-C092": 1,
        "PAI-C093": 1, "PAI-C094": 2, "PAI-C095": 1, "PAI-C096": 1,
        "PAI-C097": 1, "PAI-C098": 1, "PAI-C099": 4, "PAI-C100": 1,
        "PAI-C101": 1, "PAI-C102": 1, "RUN3-001": 3, "RUN3-002": 4,
        "RUN3-003": 1, "RUN3-004": 3, "RUN3-005": 3, "RUN3-006": 3,
        "RUN3-007": 1, "RUN3-008": 1, "RUN3-009": 1, "RUN3-010": 1,
        "RUN3-011": 1, "RUN3-012": 1, "RUN3-013": 1, "RUN4-001": 1,
        "RUN4-002": 5, "RUN4-003": 5, "RUN4-004": 1, "RUN4-005": 1,
        "RUN4-006": 1, "RUN4-007": 1, "RUN4-008": 5, "RUN4-009": 1,
        "RUN4-010": 4, "RUN4-011": 4, "RUN4-012": 2, "RUN4-013": 5,
        "RUN4-014": 5, "RUN4-015": 5, "RUN4-016": 5, "RUN4-017": 5,
        "RUN4-018": 1, "RUN4-019": 5, "RUN4-020": 1, "RUN5-001": 1,
        "RUN5-002": 1, "RUN5-003": 1, "RUN5-004": 1, "RUN5-005": 1,
        "RUN5-006": 1, "RUN5-007": 1, "RUN5-008": 1, "RUN6-001": 1,
        "RUN6-002": 1, "RUN6-003": 1, "RUN6-004": 1, "RUN6-005": 6,
        "RUN6-006": 1, "RUN6-007": 1, "RUN6-008": 1, "RUN6-009": 1,
        "RUN6-010": 1, "RUN6-011": 1, "RUN6-012": 2, "RUN6-013": 2,
        "RUN6-014": 5, "RUN6-015": 1, "RUN6-016": 1, "RUN6-017": 1,
        "RUN6-018": 1, "RUN6-019": 1, "RUN6-020": 1, "RUN6-021": 1,
        "RUN6-022": 1, "RUN6-023": 1, "RUN6-024": 1, "RUN6-025": 1,
        "RUN6-026": 1, "RUN6-027": 2, "RUN6-028": 1, "RUN6-029": 1,
        "RUN6-030": 1, "RUN6-031": 1, "RUN6-032": 1, "RUN7-001": 1,
        "RUN7-002": 1, "RUN7-003": 1, "RUN7-004": 1, "RUN7-005": 1,
        "RUN7-006": 3, "RUN7-007": 1, "RUN7-008": 1, "RUN7-009": 1,
        "RUN7-010": 6, "SCN-01": 4, "SCN-02": 4, "SCN-03": 5,
        "SCN-04": 3, "SCN-05": 3, "SCN-06": 3, "SCN-07": 4,
        "SCN-08": 3, "SCN-09": 2, "SCN-10": 4, "SCN-11": 3,
        "SCN-12": 2, "SCN-13": 3, "SCN-14": 3, "SCN-15": 1,
        "SCN-16": 3, "SCN-17": 1, "SCN-18": 2, "SCN-19": 3,
        "SCN-20": 1, "SCN-21": 4, "SCN-22": 3, "SCN-23": 2,
        "SCN-24": 2, "SCN-25": 2, "SCN-26": 6, "SCN-27": 4,
        "SCN-28": 6, "SCN-29": 4, "SCN-30": 3, "SCN-31": 2,
        "SCN-32": 3, "SCN-33": 6, "SCN-34": 4, "SCN-35": 4,
        "SCN-36": 4,
    ]

    /// Lessons for one chapter id prefix, for example "ch1".
    func lessons(forChapterPrefix prefix: String) -> [SearchEntry] {
        allLessons.filter { $0.id.hasPrefix(prefix) }
    }

    // MARK: - Lesson detail cache (offline)

    /// Maximum lesson detail pages kept on disk, and maximum total
    /// size. The oldest pages are evicted first when either bound is
    /// passed. Lesson pages are HTML text, so 50 pages stay well
    /// under 50MB in practice; both bounds are enforced.
    static let lessonDetailCacheMaxFiles = 50
    static let lessonDetailCacheMaxBytes: Int64 = 50 * 1024 * 1024

    /// The cache file name for a lesson id. Only letters, numbers,
    /// hyphen and underscore survive; every other character becomes
    /// a hyphen, so an id can never escape the cache directory.
    /// An id with no characters at all maps to "lesson.html".
    static func sanitisedLessonDetailCacheFileName(for lessonID: String) -> String {
        let safe = lessonID.map { char in
            (char.isLetter || char.isNumber || char == "-" || char == "_") ? char : "-"
        }
        let stem = String(safe)
        let base = stem.isEmpty ? "lesson" : stem
        return base + ".html"
    }

    /// The Application Support directory holding cached lesson pages.
    /// Application Support is persistent; the purgeable Caches
    /// directory is not used, so a previously opened lesson stays
    /// readable offline until the bound evicts it.
    /// Sandbox rule: cached lesson pages stay inside this app's
    /// private sandbox, like the audio downloads. They are never
    /// shown in the Files app, never shared or exported, and they
    /// are gone when the app is deleted. Keep this cache in
    /// Application Support: never move it to Documents, a shared
    /// container, or a share sheet.
    static func lessonDetailCacheDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LessonDetailCache", isDirectory: true)
    }

    /// The cache file URL for one lesson id.
    static func lessonDetailCacheFileURL(for lessonID: String) -> URL {
        lessonDetailCacheDirectoryURL()
            .appendingPathComponent(sanitisedLessonDetailCacheFileName(for: lessonID))
    }

    /// The cached page HTML for a lesson, nil when nothing was cached
    /// or the cached file is empty.
    static func cachedLessonHTML(for lessonID: String) -> String? {
        guard let data = try? Data(contentsOf: lessonDetailCacheFileURL(for: lessonID)),
              let html = String(data: data, encoding: .utf8),
              !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return html
    }

    /// Save a fetched lesson page to the cache and enforce the bounds.
    /// Best effort: a failed write never fails the load that succeeded.
    static func saveLessonDetailCache(html: String, lessonID: String) {
        let directory = lessonDetailCacheDirectoryURL()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = html.data(using: .utf8) else { return }
        try? data.write(to: lessonDetailCacheFileURL(for: lessonID), options: [.atomic])
        enforceLessonDetailCacheBounds()
    }

    /// One cached file, for eviction selection. The modification date
    /// decides age; a missing date is treated as the oldest possible.
    struct LessonDetailCacheFileInfo: Equatable {
        let fileName: String
        let modificationDate: Date
        let sizeBytes: Int64
    }

    /// The file names to evict so the remaining files fit both bounds.
    /// Oldest first; ties break by file name so the result is stable.
    /// Pure logic with no disk access, so it is covered by unit tests.
    static func cacheFilesToEvict(_ files: [LessonDetailCacheFileInfo], maxFiles: Int, maxBytes: Int64) -> [String] {
        let ordered = files.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate < $1.modificationDate
            }
            return $0.fileName < $1.fileName
        }
        var remainingCount = ordered.count
        var remainingBytes = ordered.reduce(Int64(0)) { $0 + $1.sizeBytes }
        var evicted: [String] = []
        for file in ordered {
            if remainingCount <= maxFiles && remainingBytes <= maxBytes { break }
            evicted.append(file.fileName)
            remainingCount -= 1
            remainingBytes -= file.sizeBytes
        }
        return evicted
    }

    /// Enforce the cache bounds on disk, evicting the oldest files
    /// first. Best effort: failures are ignored.
    static func enforceLessonDetailCacheBounds() {
        let directory = lessonDetailCacheDirectoryURL()
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        var infos: [LessonDetailCacheFileInfo] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            infos.append(LessonDetailCacheFileInfo(
                fileName: url.lastPathComponent,
                modificationDate: values?.contentModificationDate ?? Date.distantPast,
                sizeBytes: Int64(values?.fileSize ?? 0)
            ))
        }
        let toEvict = cacheFilesToEvict(infos, maxFiles: lessonDetailCacheMaxFiles, maxBytes: lessonDetailCacheMaxBytes)
        for fileName in toEvict {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
        }
    }

    // MARK: - Lesson detail

    /// Fetch a lesson page and extract its content.
    /// Falls back to the search index entry if the page cannot be parsed.
    /// Bounded retry (3 attempts, exponential backoff) so a single
    /// transient network failure does not surface as a lesson error.
    /// When the live fetch fails and a cached copy of the page exists
    /// from a previous open, the cached copy is returned instead, so
    /// a previously opened lesson stays readable offline. Throws only
    /// when neither the live fetch nor the cache produces a lesson.
    func loadLessonDetail(entry: SearchEntry) async throws -> LessonDetail {
        do {
            return try await fetchLiveLessonDetail(entry: entry)
        } catch {
            if let cached = cachedLessonDetail(entry: entry) {
                return cached
            }
            throw error
        }
    }

    /// Load a lesson detail and report where it came from. Tries the
    /// live page first; on failure, parses the cached page HTML when
    /// one exists and reports .cached. Returns nil only when both
    /// fail. Supplemental lessons are built locally with no network
    /// and report .live, because the local build is never stale.
    func loadLessonDetailWithSource(entry: SearchEntry) async -> (detail: LessonDetail, source: LessonDetailSource)? {
        do {
            let detail = try await fetchLiveLessonDetail(entry: entry)
            return (detail, .live)
        } catch {
            if let cached = cachedLessonDetail(entry: entry) {
                return (cached, .cached)
            }
            return nil
        }
    }

    /// Fetch the live lesson page (3 attempts, exponential backoff)
    /// and cache the page HTML on success, so the next offline open
    /// can use it. Supplemental lessons have no page: their detail
    /// is built locally and nothing is cached.
    private func fetchLiveLessonDetail(entry: SearchEntry) async throws -> LessonDetail {
        // Supplemental lessons have no page on the website: their
        // detail is built locally from the bundled entry text, with
        // no network fetch and no retry delay. Narration is recorded
        // for all of them; there is still no quiz. Beats come from
        // the bundled flow descriptor and are untimed (see
        // supplementalBeats): the flow shows every step, with no
        // invented timings. Flow lessons also carry a generated
        // flow diagram, which makes the flow render with arrows,
        // like website flow lessons. The full text is the lesson.
        if entry.isSupplemental {
            return LessonDetail(
                id: entry.id,
                title: entry.title,
                chapterTitle: chapterTitle(for: entry),
                audioFileName: entry.audioFileName ?? (entry.id + ".mp3"),
                transcript: entry.text,
                takeaways: defaultTakeaways(for: entry),
                doThisAtWork: [],
                sources: [],
                quiz: [],
                nextLessonID: nil,
                beats: Self.supplementalBeats(for: entry),
                diagramSVG: Self.supplementalFlowSVG(for: entry),
                durationSec: 0,
                nextLessonTitle: nil,
                quizIntro: ""
            )
        }
        let pageURL = Self.siteBase.appendingPathComponent(entry.url)
        var lastError: Error = ContentError.badResponse
        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(from: pageURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let html = String(data: data, encoding: .utf8) else {
                    throw ContentError.badResponse
                }
                Self.saveLessonDetailCache(html: html, lessonID: entry.id)
                return parseLessonHTML(html, entry: entry)
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
                }
            }
        }
        throw lastError
    }

    /// The lesson detail parsed from the cached page HTML, nil when
    /// no cached copy exists. Parsing never throws: a cached page
    /// that no longer parses yields the entry fallback detail, the
    /// same fallback the live path uses. Supplemental lessons never
    /// reach the cache; they are built locally.
    private func cachedLessonDetail(entry: SearchEntry) -> LessonDetail? {
        guard !entry.isSupplemental,
              let html = Self.cachedLessonHTML(for: entry.id) else { return nil }
        return parseLessonHTML(html, entry: entry)
    }

    /// Extract the lesson from its page. The page embeds the full lesson
    /// as a JSON blob (window.__PA_STUDIO_QUEUE), which is the primary
    /// source for transcript, takeaways, beats, quiz, next lesson,
    /// chapter title and duration. The diagram SVG comes from the
    /// studio-canvas div, and the quiz intro from the quiz score note.
    /// Every <svg> and <script> block is stripped before any HTML text
    /// extraction, so markup can never leak into lesson text. When the
    /// JSON blob is missing, the static HTML sections are used and the
    /// search index entry text is the fallback.
    private func parseLessonHTML(_ html: String, entry: SearchEntry) -> LessonDetail {
        let diagramSVG = extractDiagramSVG(html)
        let quizIntro = extractQuizIntro(html)
        let cleaned = stripSVGAndScriptBlocks(html)

        if let studio = extractStudioJSON(html) {
            let sampleID = studio.sampleID ?? entry.id
            var transcripts: [String] = []
            var takeaways: [String] = []
            var beats: [LessonBeat] = []
            var totalDuration: Double = 0
            var sceneOffset: Double = 0
            for (sceneIndex, scene) in (studio.scenes ?? []).enumerated() {
                var transcript = (scene.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if transcript.isEmpty {
                    let paragraphs = (scene.paragraphs ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    transcript = paragraphs.joined(separator: "\n\n")
                }
                if !transcript.isEmpty { transcripts.append(transcript) }
                takeaways.append(contentsOf: scene.points ?? [])
                for (beatIndex, beat) in (scene.beats ?? []).enumerated() {
                    let title = (beat.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { continue }
                    beats.append(LessonBeat(
                        id: "\(sampleID)-beat-\(sceneIndex)-\(beatIndex)",
                        startTime: sceneOffset + (beat.t0 ?? 0),
                        endTime: sceneOffset + (beat.t1 ?? 0),
                        title: title,
                        note: (beat.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
                let duration = scene.durationSec ?? 0
                totalDuration += duration
                sceneOffset += duration
            }
            if takeaways.isEmpty {
                takeaways = extractListItems(cleaned, sectionMarker: "Key takeaways")
            }
            let transcript = transcripts.joined(separator: "\n\n")
            return LessonDetail(
                id: entry.id,
                title: studio.title ?? entry.title,
                chapterTitle: studio.chapterTitle ?? chapterTitle(for: entry),
                audioFileName: entry.audioFileName ?? (entry.id + ".mp3"),
                transcript: transcript.isEmpty ? entry.text : transcript,
                takeaways: takeaways.isEmpty ? defaultTakeaways(for: entry) : takeaways,
                doThisAtWork: extractListItems(cleaned, sectionMarker: "Do this at work"),
                sources: extractListItems(cleaned, sectionMarker: "Sources"),
                quiz: quizQuestions(from: studio.quiz, lessonID: sampleID),
                nextLessonID: studio.nextID ?? extractNextLessonID(html, currentID: entry.id),
                beats: beats,
                diagramSVG: diagramSVG,
                durationSec: totalDuration,
                nextLessonTitle: studio.nextTitle,
                quizIntro: quizIntro
            )
        }

        // No studio JSON on the page: read the static HTML sections.
        let transcript = extractTranscriptFromHTML(cleaned) ?? entry.text
        let takeaways = extractListItems(cleaned, sectionMarker: "Key takeaways")
        return LessonDetail(
            id: entry.id,
            title: entry.title,
            chapterTitle: chapterTitle(for: entry),
            audioFileName: entry.audioFileName ?? (entry.id + ".mp3"),
            transcript: transcript.isEmpty ? entry.text : transcript,
            takeaways: takeaways.isEmpty ? defaultTakeaways(for: entry) : takeaways,
            doThisAtWork: extractListItems(cleaned, sectionMarker: "Do this at work"),
            sources: extractListItems(cleaned, sectionMarker: "Sources"),
            quiz: [],
            nextLessonID: extractNextLessonID(html, currentID: entry.id),
            beats: [],
            diagramSVG: diagramSVG,
            durationSec: 0,
            nextLessonTitle: nil,
            quizIntro: quizIntro
        )
    }

    private func chapterTitle(for entry: SearchEntry) -> String {
        // The chapter name parsed from the single-line catalogue
        // text (`<lesson title> <chapter name> Part N: <domain> <body>`).
        // Falls back to the book chapter label, never to the app
        // name and never to an internal chapter number.
        if let name = entry.chapterName { return name }
        if let number = entry.chapterNumber,
           let label = PFBookModeReadingOrder.chapterLabel(forInternalNumber: number) { return label }
        return "Chapter"
    }

    private func defaultTakeaways(for entry: SearchEntry) -> [String] {
        [entry.title, "Listen to the full narration for the worked example.", "Try the quiz below to check your understanding."]
    }

    // MARK: - Studio JSON payload

    /// The lesson JSON blob embedded in each lesson page as
    /// window.__PA_STUDIO_QUEUE.push(["studio-<id>", {...}]).
    private struct StudioPayload: Decodable {
        let sampleID: String?
        let chapterID: String?
        let title: String?
        let chapterTitle: String?
        let nextID: String?
        let nextTitle: String?
        let scenes: [StudioScene]?
        let quiz: [StudioQuizItem]?

        enum CodingKeys: String, CodingKey {
            case sampleID = "sample_id"
            case chapterID = "chapter_id"
            case title
            case chapterTitle = "chapter_title"
            case nextID = "next_id"
            case nextTitle = "next_title"
            case scenes
            case quiz
        }
    }

    private struct StudioScene: Decodable {
        let id: String?
        let title: String?
        let durationSec: Double?
        let transcript: String?
        let paragraphs: [String]?
        let points: [String]?
        let beats: [StudioBeat]?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case durationSec = "duration_sec"
            case transcript
            case paragraphs
            case points
            case beats
        }
    }

    private struct StudioBeat: Decodable {
        let t0: Double?
        let t1: Double?
        let title: String?
        let note: String?
    }

    /// One quiz item from the studio JSON. The correct answer is an
    /// option index: answer_index wins, then answer when it is a number,
    /// then the option whose text matches answer or correct_answer.
    private struct StudioQuizItem: Decodable {
        let question: String?
        let options: [String]?
        let answerIndex: Int?
        let answerText: String?
        let explanation: String?

        enum CodingKeys: String, CodingKey {
            case question
            case options
            case answer
            case answerIndex = "answer_index"
            case correctAnswer = "correct_answer"
            case explanation
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            question = try container.decodeIfPresent(String.self, forKey: .question)
            options = try container.decodeIfPresent([String].self, forKey: .options)
            explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
            var resolvedIndex: Int? = nil
            if let raw = try? container.decodeIfPresent(Int.self, forKey: .answerIndex) {
                resolvedIndex = raw
            } else if let raw = try? container.decodeIfPresent(Int.self, forKey: .answer) {
                resolvedIndex = raw
            }
            answerIndex = resolvedIndex
            var resolvedText: String? = nil
            if let raw = try? container.decodeIfPresent(String.self, forKey: .answer) {
                resolvedText = raw
            }
            if resolvedText == nil {
                resolvedText = try container.decodeIfPresent(String.self, forKey: .correctAnswer)
            }
            answerText = resolvedText
        }
    }

    /// Find the studio JSON object inside
    /// window.__PA_STUDIO_QUEUE.push([...]) and decode it. The scan
    /// respects JSON strings and escapes, so braces inside quoted text
    /// cannot end the object early.
    private func extractStudioJSON(_ html: String) -> StudioPayload? {
        guard let marker = html.range(of: "window.__PA_STUDIO_QUEUE.push([\"studio-") else { return nil }
        guard let braceIndex = html[marker.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = braceIndex
        while index < html.endIndex {
            let ch = html[index]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else if ch == "\"" {
                inString = true
            } else if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let jsonText = String(html[braceIndex...index])
                    guard let data = jsonText.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode(StudioPayload.self, from: data)
                }
            }
            index = html.index(after: index)
        }
        return nil
    }

    /// The lesson diagram SVG from the studio-canvas div. The mobile flow
    /// fits phone widths better, so it is preferred; the desktop flow is
    /// the fallback. Returns the whole <svg>...</svg> string.
    private func extractDiagramSVG(_ html: String) -> String? {
        guard let canvasStart = html.range(of: "<div class=\"studio-canvas\"") else { return nil }
        for flowClass in ["flow-mobile", "flow-desktop"] {
            let marker = "<svg class=\"\(flowClass)\""
            guard let svgStart = html.range(of: marker, range: canvasStart.lowerBound..<html.endIndex),
                  let svgEnd = html.range(of: "</svg>", range: svgStart.upperBound..<html.endIndex) else { continue }
            return String(html[svgStart.lowerBound..<svgEnd.upperBound])
        }
        return nil
    }

    /// The quiz intro line from the page, for example "Answer all 3
    /// questions to see your score. ...". Empty when the page has none.
    private func extractQuizIntro(_ html: String) -> String {
        guard let pStart = html.range(of: "<p class=\"studio-note\" id=\"pf-quiz-score-"),
              let tagEnd = html.range(of: ">", range: pStart.upperBound..<html.endIndex),
              let pEnd = html.range(of: "</p>", range: tagEnd.upperBound..<html.endIndex) else { return "" }
        return stripTags(String(html[tagEnd.upperBound..<pEnd.lowerBound]))
    }

    /// Build real quiz questions from the studio JSON quiz items. Items
    /// with no question, no options, or no resolvable correct option are
    /// skipped instead of inventing True/False options.
    private func quizQuestions(from items: [StudioQuizItem]?, lessonID: String) -> [QuizQuestion] {
        guard let items = items else { return [] }
        var questions: [QuizQuestion] = []
        for (index, item) in items.enumerated() {
            guard let question = item.question?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !question.isEmpty,
                  let options = item.options, !options.isEmpty else { continue }
            var correct = item.answerIndex
            if correct == nil, let answerText = item.answerText,
               let found = options.firstIndex(of: answerText) {
                correct = found
            }
            guard let correctIndex = correct, correctIndex >= 0, correctIndex < options.count else { continue }
            let explanation = (item.explanation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            questions.append(QuizQuestion(
                id: "\(lessonID)-q\(index + 1)",
                question: question,
                options: options,
                correctOptionIndex: correctIndex,
                explanation: explanation.isEmpty ? "See the lesson transcript for the full explanation." : explanation
            ))
        }
        return questions
    }

    // MARK: - HTML helpers

    /// Remove every <script>...</script> and <svg>...</svg> block. This
    /// runs BEFORE any HTML text extraction, so SVG attribute text and
    /// script source can never leak into lesson text, lists or the
    /// transcript.
    private func stripSVGAndScriptBlocks(_ html: String) -> String {
        var result = html
        for pattern in ["<script\\b[^>]*>.*?</script>", "<svg\\b[^>]*>.*?</svg>"] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        return result
    }

    private func stripTags(_ html: String) -> String {
        var result = ""
        var inTag = false
        for ch in html {
            if ch == "<" { inTag = true; continue }
            if ch == ">" { inTag = false; continue }
            if !inTag { result.append(ch) }
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The static "Full lesson text" transcript div, used only when the
    /// studio JSON blob is missing. Paragraphs are kept apart with blank
    /// lines so the text reads as paragraphs, not one run-on block.
    private func extractTranscriptFromHTML(_ html: String) -> String? {
        guard let divStart = html.range(of: "<div id=\"studio-transcript-full-"),
              let tagEnd = html.range(of: ">", range: divStart.upperBound..<html.endIndex),
              let divEnd = html.range(of: "</div>", range: tagEnd.upperBound..<html.endIndex) else { return nil }
        let inner = String(html[tagEnd.upperBound..<divEnd.lowerBound])
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "</h4>", with: "\n\n")
        let cleaned = stripTags(inner)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func extractListItems(_ html: String, sectionMarker: String) -> [String] {
        // Anchor on the real <h2> heading. The page <style> block holds a
        // CSS comment that mentions "Do this at work", so bare text would
        // match the stylesheet instead of the section.
        let heading = "<h2>" + sectionMarker + "</h2>"
        guard let headingRange = html.range(of: heading) else { return [] }
        let afterHeading = html[headingRange.upperBound...]
        var sectionEnd = afterHeading.endIndex
        if let end = afterHeading.range(of: "</section>") {
            sectionEnd = end.lowerBound
        }
        if let endDiv = afterHeading.range(of: "</div>"), endDiv.lowerBound < sectionEnd {
            sectionEnd = endDiv.lowerBound
        }
        let section = String(afterHeading[..<sectionEnd])
        // Match only real list items: "<li>" or "<li " with attributes.
        // Never "<line", "<link" or "<linearGradient".
        guard let liRegex = try? NSRegularExpression(pattern: "<li(?:\\s[^>]*)?>", options: [.caseInsensitive]) else { return [] }
        let nsSection = section as NSString
        let matches = liRegex.matches(in: section, options: [], range: NSRange(location: 0, length: nsSection.length))
        var items: [String] = []
        for (index, match) in matches.enumerated() {
            let itemStart = match.range.upperBound
            // Stop at the next <li> as well as at </li>: with nested or
            // unclosed items, running to the next </li> swallows the
            // following item's text, which then repeats as its own item.
            let nextItemStart = (index + 1 < matches.count) ? matches[index + 1].range.lowerBound : nsSection.length
            let closeRange = nsSection.range(of: "</li>", options: [.caseInsensitive], range: NSRange(location: itemStart, length: nsSection.length - itemStart))
            let itemEnd: Int
            if closeRange.location != NSNotFound, closeRange.location < nextItemStart {
                itemEnd = closeRange.location
            } else if nextItemStart < nsSection.length {
                itemEnd = nextItemStart
            } else {
                continue
            }
            guard itemEnd > itemStart else { continue }
            let raw = nsSection.substring(with: NSRange(location: itemStart, length: itemEnd - itemStart))
            let cleaned = stripTags(raw)
            if !cleaned.isEmpty { items.append(cleaned) }
        }
        return items
    }

    private func extractNextLessonID(_ html: String, currentID: String) -> String? {
        // Next lesson links use the lessons/<id> path.
        let pattern = "lessons/(ch\\d+s\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        for match in matches {
            if let idRange = Range(match.range(at: 1), in: html) {
                let id = String(html[idRange])
                if id != currentID { return id }
            }
        }
        return nil
    }

    // MARK: - Audio URLs

    /// The primary audio URL for a lesson file.
    static func primaryAudioURL(fileName: String) -> URL {
        URL(string: primaryAudioBase + fileName)!
    }

    /// The fallback audio URL for a lesson file.
    static func fallbackAudioURL(fileName: String) -> URL {
        URL(string: fallbackAudioBase + fileName)!
    }
}

// MARK: - Errors

enum ContentError: Error, LocalizedError {
    case badResponse
    case notFound

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "The website did not respond. Check your connection and try again."
        case .notFound:
            return "That content could not be found."
        }
    }
}
