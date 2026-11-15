// SearchView.swift
// Payments Training Hub iOS - Search across the whole catalogue.
// Native SwiftUI only, no WebView.
//
// Layout follows the mockup (DESIGN_REFERENCE.md, Screen 5):
// a difficulty pill row above the search field (All / Foundation
// / Core / Advanced), result rows with an icon tile on the left,
// a bold title (2 lines max), tags below (scheme, category,
// level) and a bookmark icon on the right. The bookmark icon toggles the saved state in
// PFBookmarkStore; it is a borderless button, so tapping it does not
// follow the row's navigation link. The same toggle also lives in
// the lesson and situation detail views. Result tags wrap onto a
// second row instead of overflowing on a narrow phone.
//
// Smarter search: the query is expanded through a payments-domain
// acronym, synonym and failure-symptom map in SearchService, so
// typing "RRN", "UTR" or "beneficiary not credited" also finds entries
// that only use the expanded terms. Every result says why it matched.
// Typing waits ~0.15s (debounce) before the search runs; suggestions
// appear as you type and recent searches persist on device. The
// search, the level filter, the per-type totals and the matching
// chapters are computed once per query, off the main thread, into
// a snapshot held in state: rendering never re-runs the search.
// (The old code recomputed the full search from computed
// properties several times per render, on the main thread, which
// is what made search feel extremely slow and hung the app.)
// The one filter, Difficulty, is derived from the entry title and
// text only, never invented. Duration is deliberately NOT
// offered as a filter: narration length lives only
// in each lesson page (durationSec in the lesson detail) and is not in
// the search index, so a duration filter here would have to guess.
// Browse-by-type counts come from the live index entries, never from
// hardcoded totals: a type with no loaded entries shows no count.
// Only real catalogue entries are ever returned.

import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var storeManager: StoreManager
    @ObservedObject private var bookmarkStore = PFBookmarkStore.shared

    /// Opens the side drawer. Passed in from the tab bar so the menu
    /// button can sit in this screen's navigation bar, and only here:
    /// pushed detail views have no menu button and keep a clean back button.
    @Binding var isDrawerOpen: Bool

    @State private var query = ""
    /// The latest tour demo run accepted: keystrokes from an
    /// older run are ignored, so a demo abandoned mid-typing
    /// can never overwrite a newer one.
    @State private var tourDemoRun = 0
    /// Keyboard focus for the search field, so pressing Search and
    /// the keyboard Done button can dismiss the keyboard.
    @FocusState private var isSearchFieldFocused: Bool
    /// The query the results actually ran for. Updated ~0.15s after
    /// the user stops typing, so typing never re-filters on every
    /// keystroke. See the .task(id: query) debounce in body.
    @State private var debouncedQuery = ""
    /// The last query recorded in recents, so the debounce records
    /// each distinct search once.
    @State private var lastRecordedQuery = ""
    @State private var recentSearches: [String] = SearchService.recentSearches()
    /// Confirmation before wiping all recent searches: clearing
    /// history cannot be undone.
    @State private var showClearRecentsConfirmation = false
    @State private var sheetEntry: SearchEntry? = nil
    @State private var selectedBrowseType: SearchEntryType? = nil
    /// Results List identity: the scroll rule for Lists. A List
    /// restores its offset on Back like a ScrollView does, and a
    /// new query must start at the first result, so each return
    /// and each new query bumps this generation and recreates
    /// the List at the top. Load more never bumps it: paging
    /// down keeps the learner where they are.
    @State private var resultsListGeneration = 0

    // MARK: - Filter state (difficulty only)

    /// The one filter: difficulty levels, picked from the pill
    /// row above the search field. Multi-select: tapping a level
    /// toggles it. An empty selection means all levels, and
    /// selecting every level means all levels too, so an
    /// all-selected filter can never empty the results.
    @State private var selectedLevels: Set<SituationLevel> = []

    /// Results shown at first: 20 per page, Load more adds 20.
    /// Only the shown results are grouped and rendered, so a
    /// filter matching 1,500 entries never builds 1,500 rows.
    private static let resultsPageSize = 20
    @State private var visibleResultCount = 20

    /// One fully computed result set for one query, filter and
    /// catalogue state: the level-filtered hits, the per-type
    /// totals across all of them, and the matching chapters.
    /// Computed once, off the main thread, by the task keyed on
    /// searchWorkKey below. Rendering reads this state and never
    /// re-runs the search, the filter, the totals or the chapter
    /// match, however many times the body evaluates.
    private struct SearchResultsSnapshot {
        let hits: [SearchHit]
        let totals: [SearchEntryType: Int]
        let chapters: [Int]
        static let empty = SearchResultsSnapshot(hits: [], totals: [:], chapters: [])
    }

    /// The latest computed snapshot. Empty until the first
    /// computation finishes.
    @State private var searchSnapshot = SearchResultsSnapshot.empty
    /// The work key the snapshot above was computed for. When it
    /// differs from searchWorkKey, a newer computation is still
    /// running and the visible results belong to the older key.
    @State private var snapshotKey = ""
    /// Live suggestions for the text being typed, computed off
    /// the main thread so typing never scans the catalogue on
    /// the main thread. Empty while the field holds under 2
    /// characters, exactly as SearchService.suggestions returns.
    @State private var suggestionList: [SearchSuggestion] = []

    private let popularSearches = [
        "MT103", "pacs.008", "ISO 20022", "SEPA",
        "OUR SHA BEN", "chargeback", "nostro", "UPI",
        "beneficiary not credited", "RRN"
    ]

    /// Browse-by-type rows with counts from the live index entries.
    /// A type with no entries in the loaded index has a nil count and
    /// the row shows no number, never a made-up total.
    private var browseTypes: [(type: SearchEntryType, count: Int?)] {
        let counts = SearchService.countsByType(entries: contentService.searchIndex?.entries ?? [])
        return typeOrder.map { ($0, counts[$0]) }
    }

    private let typeOrder: [SearchEntryType] = [.lesson, .guide, .situation, .lab, .test, .faq]

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasActiveFilters: Bool {
        SearchService.isLevelFilterActive(selectedLevels)
    }

    // MARK: - Synonym, acronym and symptom map

    /// The synonym entries the current query triggers. The map itself
    /// lives in SearchService (the single source of truth); this view
    /// only asks what the current query triggers, for the expansion
    /// note and for SearchService.search.
    private var triggeredSynonyms: [SearchService.SearchSynonym] {
        SearchService.triggeredSynonyms(for: trimmedQuery)
    }

    /// Run a search immediately, skipping the debounce: used when the
    /// learner taps a suggestion or a recent search.
    private func runSearch(_ term: String) {
        query = term
        debouncedQuery = term.trimmingCharacters(in: .whitespacesAndNewlines)
        recordCurrentSearch()
    }

    /// Record the current debounced query in recents, once per
    /// distinct query.
    private func recordCurrentSearch() {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, q.lowercased() != lastRecordedQuery.lowercased() else { return }
        lastRecordedQuery = q
        SearchService.recordSearch(q)
        recentSearches = SearchService.recentSearches()
    }

    /// Live suggestions for the text being typed, from lesson and
    /// Situation titles and the synonym map. Held in state and
    /// computed off the main thread by the suggestions task, so
    /// reading them here costs nothing.
    private var liveSuggestions: [SearchSuggestion] {
        suggestionList
    }

    // MARK: - Results

    /// One string for everything the snapshot depends on: the
    /// debounced query, the difficulty filter, the loaded
    /// catalogue size, the loaded situations size (the full file
    /// wins for a situation's level), and the last lesson opened
    /// (its chapter ranks higher). The snapshot task reruns when
    /// this changes, and only then: typing alone never recomputes
    /// anything, because the raw query is not part of the key.
    private var searchWorkKey: String {
        [
            debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            selectedLevels.map(\.rawValue).sorted().joined(separator: ","),
            "\(contentService.searchIndex?.entries.count ?? 0)",
            "\(contentService.fullSituations?.count ?? -1)",
            progressStore.lastLessonID ?? ""
        ].joined(separator: "|")
    }

    /// True while a snapshot computation for the current key is
    /// still running: the visible snapshot belongs to an older key.
    private var isAwaitingSnapshot: Bool {
        snapshotKey != searchWorkKey
    }

    /// The level-filtered hits from the latest snapshot. A plain
    /// state read: rendering never re-runs the search or the
    /// filter. Ranked results for the debounced query come from
    /// SearchService (title outranks body, exact phrase outranks
    /// partial, synonym and symptom expansions resolve to the
    /// right cases, a 1-2 edit typo still finds the right lesson
    /// or Situation, free samples and the current chapter rank
    /// higher, completed items are marked, never hidden; the 60-hit
    /// cap lifts while a difficulty filter is active, so the filter
    /// never empties a query's results). With no search text, every catalogue entry is the
    /// base set and the difficulty filter alone applies.
    private var filteredResults: [SearchHit] {
        searchSnapshot.hits
    }

    /// Compute the snapshot for the current debounced query and
    /// filter. The heavy work (search, level filter, totals,
    /// chapter match) runs on a detached background task; this
    /// function only gathers the inputs on the main actor and
    /// awaits the result, so the main thread stays free. With no
    /// query and no filter the browse content shows instead, so
    /// no work is done at all. The situations level map is built
    /// here (one cheap pass, first item wins for a repeated id,
    /// exactly as first(where:) behaved) so the background task
    /// receives only plain sendable values.
    private func computeSnapshot() async -> SearchResultsSnapshot {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let levels = selectedLevels
        guard !q.isEmpty || SearchService.isLevelFilterActive(levels) else { return .empty }
        let entries = contentService.searchIndex?.entries ?? []
        guard !entries.isEmpty else { return .empty }
        var situationLevelsByID: [String: String] = [:]
        for item in contentService.fullSituations ?? [] {
            if situationLevelsByID[item.id] == nil {
                situationLevelsByID[item.id] = item.level
            }
        }
        let chapterPrefix = progressStore.lastLessonID.flatMap { SearchService.chapterPrefix(forLessonID: $0) }
        return await Task.detached(priority: .userInitiated) {
            Self.computeSnapshotSync(
                entries: entries,
                query: q,
                levels: levels,
                situationLevelsByID: situationLevelsByID,
                chapterPrefix: chapterPrefix
            )
        }.value
    }

    /// The snapshot computation itself: search (or the whole
    /// catalogue when there is no query), the difficulty filter,
    /// the per-type totals, and the matching chapters. Nonisolated
    /// and synchronous, so it runs on the detached task with no
    /// hop back to the main actor. Same index source, same
    /// matching semantics, same level rules as the old computed
    /// properties: only the thread and the frequency change.
    private nonisolated static func computeSnapshotSync(
        entries: [SearchEntry],
        query: String,
        levels: Set<SituationLevel>,
        situationLevelsByID: [String: String],
        chapterPrefix: String?
    ) -> SearchResultsSnapshot {
        // When the difficulty filter is active, the search runs
        // uncapped: the old 60-hit cap ran before the filter, so
        // a query plus a filter could return nothing even though
        // matches existed beyond the first 60 hits. With no
        // active filter the 60-hit cap stays, as before.
        let base: [SearchHit]
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = entries.map { SearchHit(entry: $0, score: 0, reason: "", matchedTerm: nil) }
        } else {
            base = SearchService.search(
                entries: entries,
                query: query,
                freeSampleIDs: Set(ContentService.freeSampleIDs),
                currentChapterPrefix: chapterPrefix,
                limit: SearchService.isLevelFilterActive(levels) ? entries.count : 60
            )
        }
        let filtered = SearchService.applyLevelFilter(
            base,
            selectedLevels: levels,
            situationLevelsByID: situationLevelsByID
        )
        var totals: [SearchEntryType: Int] = [:]
        for hit in filtered {
            totals[hit.entry.type, default: 0] += 1
        }
        return SearchResultsSnapshot(
            hits: filtered,
            totals: totals,
            chapters: matchedChaptersSync(entries: entries, query: query)
        )
    }

    /// Chapters whose title, or whose course name, matches the
    /// query, so a search for "ISO 20022" shows the ISO 20022
    /// chapters as well as their lessons. Title matches first,
    /// then course-name matches, capped at 10 so one broad query
    /// never floods the results. Empty when there is no query:
    /// courses appear only for a search, never for filters.
    /// Lessons are grouped by chapter once, instead of scanning
    /// the whole lesson list per chapter per render.
    private nonisolated static func matchedChaptersSync(entries: [SearchEntry], query: String) -> [Int] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var lessonsByChapter: [Int: [SearchEntry]] = [:]
        for entry in entries where entry.type == .lesson {
            if let number = PFChapterHelper.chapterNumber(from: entry.id) {
                lessonsByChapter[number, default: []].append(entry)
            }
        }
        var titleMatches: [Int] = []
        var bundleMatches: [Int] = []
        // Reading order, not numeric chapter order: the matched
        // chapters list follows the book.
        let orderedNumbers = lessonsByChapter.keys.sorted {
            PFBookModeReadingOrder.readingOrderIndex(forInternalNumber: $0)
                < PFBookModeReadingOrder.readingOrderIndex(forInternalNumber: $1)
        }
        for number in orderedNumbers {
            let lessons = lessonsByChapter[number] ?? []
            let title = PFChapterHelper.chapterTitle(for: lessons, number: number)
            if title.lowercased().contains(q) {
                titleMatches.append(number)
            } else if let bundle = ProductCatalogue.productContaining(chapterID: "ch\(number)"),
                      bundle.name.lowercased().contains(q) {
                bundleMatches.append(number)
            }
        }
        return Array((titleMatches + bundleMatches).prefix(10))
    }

    private var groupedResults: [(type: SearchEntryType, entries: [SearchHit])] {
        var groups: [SearchEntryType: [SearchHit]] = [:]
        for scored in visibleResults {
            groups[scored.entry.type, default: []].append(scored)
        }
        return typeOrder.compactMap { type in
            guard let entries = groups[type], !entries.isEmpty else { return nil }
            return (type: type, entries: entries)
        }
    }

    /// The results actually rendered: the first page(s) of the
    /// filtered results. Grouping above runs on this subset only.
    private var visibleResults: [SearchHit] {
        Array(filteredResults.prefix(visibleResultCount))
    }

    /// Full per-type totals across ALL filtered results, not just
    /// the visible page, so a group header reads the live filtered
    /// total for its type instead of the page count. Counts here
    /// always come from the filtered live results, never from
    /// catalogue totals. A state read from the snapshot: computed
    /// once with the results, never re-tallied per render.
    private var groupTotals: [SearchEntryType: Int] {
        searchSnapshot.totals
    }

    /// True while the text field holds a newer query than the one
    /// the results ran for: the 0.15s debounce has not caught up
    /// yet, so the visible results belong to the previous query.
    private var isAwaitingDebouncedSearch: Bool {
        trimmedQuery != debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Chapters whose title, or whose course name, matches the
    /// debounced query, from the snapshot. A state read: the
    /// chapter match runs once with the search, off the main
    /// thread, never per render.
    private var matchedChapters: [Int] {
        searchSnapshot.chapters
    }

    /// One string for the current query and filter, so a change
    /// to either resets the pagination to page 1.
    private var filterSignature: String {
        [
            debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            selectedLevels.map(\.rawValue).sorted().joined(separator: ",")
        ].joined(separator: "|")
    }

    private var expansionNote: String {
        guard !triggeredSynonyms.isEmpty else { return "" }
        let parts = triggeredSynonyms.map { synonym in
            synonym.isSymptom
                ? "'\(synonym.key)'"
                : "'\(synonym.key)' (\(synonym.expansion))"
        }
        return "Also matching: " + parts.joined(separator: ", ")
    }

    /// The no-results hint. The filter clause only appears when a
    /// filter is actually active: with no filter set, telling the
    /// learner to clear one would point at nothing.
    private var noResultsHintText: String {
        if hasActiveFilters {
            return "Try a different word, for example MT103, SEPA or chargeback, or clear the difficulty filter."
        }
        return "Try a different word, for example MT103, SEPA or chargeback."
    }

    /// True when the no-results state should offer tappable popular
    /// searches: the learner typed a query, and the live suggestions
    /// row above the results is empty, so no synonym or title
    /// suggestion is already on screen. When suggestions exist,
    /// they are the synonym next step and are not repeated here.
    private var shouldShowNoResultsFallbackChips: Bool {
        !trimmedQuery.isEmpty && liveSuggestions.isEmpty
    }

    // MARK: - Derived entry facts (title and text only, never invented)

    // The level derivation lives in SearchService.levelForEntry,
    // shared by the snapshot computation and the unit tests, with
    // the full situations file prebuilt into a lookup map.
    // Row-level derivation lives in SearchResultRow below.

    /// The full situations file as a lookup map, first item wins
    /// for a repeated id (exactly as first(where:) behaved).
    /// Each list reads it once into a local and passes it to its
    /// rows, so no row scans the whole file to find its own
    /// situation on every render.
    private var situationLookup: [String: FullSituationItem] {
        var lookup: [String: FullSituationItem] = [:]
        for item in contentService.fullSituations ?? [] {
            if lookup[item.id] == nil {
                lookup[item.id] = item
            }
        }
        return lookup
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                difficultyPillsRow
                searchField
                if contentService.isShowingCachedContent {
                    PFOfflineBanner()
                        .padding(.horizontal, PFSpacing.lg)
                        .padding(.top, PFSpacing.sm)
                }
                Group {
                    if contentService.isLoadingIndex && contentService.searchIndex == nil {
                        VStack(spacing: PFSpacing.lg) {
                            ProgressView()
                            Text("Loading the course catalogue...")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = contentService.indexError, contentService.searchIndex == nil {
                        VStack(spacing: PFSpacing.lg) {
                            PFCard {
                                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                    Text("Could not load search")
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                    Text(error)
                                        .font(.pfBody)
                                        .foregroundColor(.pfSecondaryText)
                                    PFPrimaryButton(title: "Retry") {
                                        Task { await contentService.loadSearchIndex() }
                                    }
                                }
                            }
                            .padding(.horizontal, PFSpacing.lg)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if trimmedQuery.isEmpty && !hasActiveFilters {
                        browseContent
                    } else {
                        resultsContent
                    }
                }
            }
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    DrawerMenuButton(isDrawerOpen: $isDrawerOpen)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isSearchFieldFocused = false
                    }
                }
            }
            .sheet(item: $sheetEntry) { entry in
                SearchEntrySheet(entry: entry)
            }
            .navigationDestination(item: $selectedBrowseType) { type in
                SearchTypeListView(type: type)
            }
            // Debounced search: waits 0.15s after the user stops typing
            // before running the search, so typing never re-filters on
            // every keystroke. The task restarts (and the previous one
            // is cancelled) on each keystroke. The finished query is
            // recorded in recents once.
            .task(id: query) {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                debouncedQuery = trimmedQuery
                recordCurrentSearch()
            }
            // Live suggestions, computed off the main thread so
            // typing never scans the catalogue on the main thread.
            // The task restarts on each keystroke (and when the
            // catalogue loads), cancelling the previous run; a
            // stale result is discarded, never shown. No debounce
            // delay: suggestions stay live as the learner types,
            // exactly as before, only on a background task now.
            .task(id: query + "|" + "\(contentService.searchIndex?.entries.count ?? 0)") {
                let current = query
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2 else {
                    suggestionList = []
                    return
                }
                let entries = contentService.searchIndex?.entries ?? []
                let found = await Task.detached(priority: .userInitiated) {
                    SearchService.suggestions(query: current, entries: entries)
                }.value
                guard !Task.isCancelled else { return }
                suggestionList = found
            }
            // The result snapshot: search, level filter, totals
            // and chapter match, computed once per work key, off
            // the main thread. The task restarts only when the
            // key changes (debounced query, filter, catalogue or
            // situations load, last lesson), never per keystroke.
            // A stale result is discarded, never shown.
            .task(id: searchWorkKey) {
                let key = searchWorkKey
                let snapshot = await computeSnapshot()
                guard !Task.isCancelled else { return }
                searchSnapshot = snapshot
                snapshotKey = key
            }
            // Any query or filter change: back to the first page of
            // results, so Load more never shows a stale slice.
            .onChange(of: filterSignature) { _, _ in
                visibleResultCount = Self.resultsPageSize
            }
            // The guided tour's Search demo: the tour types a
            // query character by character and taps search.
            // Demo keystrokes only land when the field is empty
            // or already holds the demo prefix, so the
            // learner's own typing is never overwritten, and
            // stale runs are ignored. The reset clears only
            // the exact demo query.
            .onReceive(NotificationCenter.default.publisher(for: .tourSearchDemoType)) { note in
                guard let run = note.userInfo?["run"] as? Int, run >= tourDemoRun,
                      let text = note.userInfo?["text"] as? String,
                      let full = note.userInfo?["full"] as? String,
                      query.isEmpty || full.hasPrefix(query) else { return }
                tourDemoRun = run
                query = text
            }
            .onReceive(NotificationCenter.default.publisher(for: .tourSearchDemoSubmit)) { note in
                guard let run = note.userInfo?["run"] as? Int, run >= tourDemoRun,
                      let term = note.userInfo?["query"] as? String,
                      query.isEmpty || term.hasPrefix(query) else { return }
                tourDemoRun = run
                runSearch(term)
            }
            .onReceive(NotificationCenter.default.publisher(for: .tourSearchDemoReset)) { note in
                guard let term = note.userInfo?["query"] as? String, query == term else { return }
                query = ""
                debouncedQuery = ""
            }
        }
    }

    // MARK: - Difficulty pills above the search field

    /// The one filter, as pills that are always visible.
    /// Multi-select difficulty pills: tapping a level toggles
    /// it, and any combination can be active. "All" is selected
    /// when no level is picked or when every level is picked,
    /// and tapping it clears the selection. No menus, no hidden
    /// choices. The pills work with no search text too,
    /// filtering the whole catalogue.
    private var difficultyPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PFSpacing.sm) {
                Text("Difficulty")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
                    .accessibilityHidden(true)
                PFChip(text: "All", isSelected: !SearchService.isLevelFilterActive(selectedLevels)) {
                    selectedLevels = []
                }
                .pfMinimumTouchTarget()
                ForEach(SearchService.allLevels, id: \.self) { option in
                    PFChip(text: option.displayName, isSelected: selectedLevels.contains(option)) {
                        if selectedLevels.contains(option) {
                            selectedLevels.remove(option)
                        } else {
                            selectedLevels.insert(option)
                        }
                    }
                    .pfMinimumTouchTarget()
                }
            }
            .padding(.horizontal, PFSpacing.lg)
        }
        .padding(.top, PFSpacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Difficulty filter")
    }

    /// Always-visible search field below the filter chips. The
    /// navigation-bar search from .searchable can hide until the user
    /// scrolls, so the field lives here instead, where it is always
    /// tappable.
    private var searchField: some View {
        HStack(spacing: PFSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.pfSecondaryText)
                .accessibilityHidden(true)
            TextField("Search lessons, guides, situations and more", text: $query)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .onSubmit(of: .search) {
                    // Pressing Search runs the query at once instead
                    // of waiting for the debounce, and dismisses the
                    // keyboard so the results are fully visible.
                    debouncedQuery = trimmedQuery
                    recordCurrentSearch()
                    isSearchFieldFocused = false
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    debouncedQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.pfSecondaryText)
                }
                .buttonStyle(.plain)
                .pfMinimumTouchTarget()
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, PFSpacing.md)
        .padding(.vertical, PFSpacing.sm)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
        .shadow(color: Color.pfNavy.opacity(0.06), radius: 8, x: 0, y: 2)
        // Reports the field frame for the tour's typing demo.
        // Attached before the outer padding, so the bounds are
        // the field box itself, not the padded strip.
        .anchorPreference(key: SearchFieldAnchorKey.self, value: .bounds) { $0 }
        .padding(.horizontal, PFSpacing.lg)
        .padding(.top, PFSpacing.md)
        .background(Color.pfBackground)
    }

    // MARK: - Empty query: recent and popular searches, browse by type

    private var browseContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                if !recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        HStack {
                            PFSectionHeader(title: "Recent searches")
                            Spacer()
                            Button("Clear") {
                                showClearRecentsConfirmation = true
                            }
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                            .buttonStyle(.plain)
                            .pfMinimumTouchTarget()
                            .accessibilityLabel("Clear recent searches")
                            .accessibilityHint("Asks before clearing all recent searches from this device.")
                        }
                        FlowChips(
                            items: recentSearches,
                            onTap: { runSearch($0) }
                        )
                    }
                }

                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFSectionHeader(title: "Popular searches")
                    FlowChips(
                        items: popularSearches,
                        onTap: { runSearch($0) }
                    )
                }

                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFSectionHeader(title: "Browse by type")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: PFSpacing.md) {
                        ForEach(browseTypes, id: \.type) { item in
                            browseTypeCard(item)
                        }
                    }
                }
            }
            .padding(PFSpacing.lg)
            .id("searchBrowseTop")
        }
        .pfScrollToTopOnAppear("searchBrowseTop")
        .background(Color.pfBackground)
        .scrollDismissesKeyboard(.interactively)
        // Extra scrollable space at the bottom so the last row clears
        // the tab bar on every iPhone size.
        .pfTabBarClearance()
        .confirmationDialog(
            "Clear recent searches?",
            isPresented: $showClearRecentsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear recent searches", role: .destructive) {
                SearchService.clearRecentSearches()
                recentSearches = []
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes all recent searches from this device. It cannot be undone.")
        }
    }

    private func typeBrowseLabel(for type: SearchEntryType) -> String {
        switch type {
        case .lesson: return "Lessons"
        case .guide: return "Guides"
        case .situation: return "Situations"
        case .lab: return "Labs"
        case .test: return "Tests"
        case .faq: return "FAQs"
        }
    }

    /// The browse card icon, the same symbol the result rows use
    /// for each type, so a type looks the same everywhere.
    private func typeBrowseSymbol(for type: SearchEntryType) -> String {
        switch type {
        case .lesson: return "play.fill"
        case .guide: return "book"
        case .situation: return "briefcase.fill"
        case .lab: return "flask"
        case .test: return "checkmark.circle"
        case .faq: return "questionmark.circle.fill"
        }
    }

    /// One browse card: the type's icon tile, its name, and the
    /// live count from the loaded index. No count shows when the
    /// index has no entries of that type, never a made-up total.
    private func browseTypeCard(_ item: (type: SearchEntryType, count: Int?)) -> some View {
        Button {
            selectedBrowseType = item.type
        } label: {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack {
                    PFIconTile(systemImage: typeBrowseSymbol(for: item.type), size: 44)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.pfCaption.weight(.semibold))
                        .foregroundColor(.pfSecondaryText)
                        .pfDecorative()
                }
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(typeBrowseLabel(for: item.type))
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    if let count = item.count {
                        Text("\(count) \(count == 1 ? "item" : "items")")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PFSpacing.lg)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cardRadius)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(typeBrowseLabel(for: item.type))\(item.count.map { ", \($0) items" } ?? "")")
    }

    // MARK: - Results

    /// Suggestions for the text being typed, above the results.
    /// Tapping one runs that search at once.
    private var suggestionsSection: some View {
        let suggestions = Array(liveSuggestions.prefix(5))
        return Group {
            if !trimmedQuery.isEmpty, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            runSearch(suggestion.query)
                        } label: {
                            HStack(spacing: PFSpacing.sm) {
                                Image(systemName: "magnifyingglass")
                                    .font(.pfCaption.weight(.semibold))
                                    .foregroundColor(.pfSecondaryText)
                                    .accessibilityHidden(true)
                                Text(suggestion.title)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.pfCaption.weight(.semibold))
                                    .foregroundColor(.pfSecondaryText)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, PFSpacing.lg)
                            .padding(.vertical, PFSpacing.sm)
                        }
                        .buttonStyle(.plain)
                        .pfMinimumTouchTarget()
                    }
                }
                .padding(.bottom, PFSpacing.sm)
            }
        }
    }

    private var resultsContent: some View {
        let situationsByID = situationLookup
        return VStack(spacing: 0) {
            suggestionsSection
            if (!trimmedQuery.isEmpty && debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                || (isAwaitingSnapshot && filteredResults.isEmpty) {
                VStack(spacing: PFSpacing.md) {
                    ProgressView()
                    Text("Searching...")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
                .padding(PFSpacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredResults.isEmpty {
                // No results is never a dead end. The next steps are:
                // clear the difficulty filter (when one is active),
                // try a suggested search, and browse by type. The
                // synonym next step lives in the suggestions row
                // above this state whenever live suggestions exist
                // (synonym-map entries first); when that row is
                // empty, tappable popular searches are offered here
                // instead, so the synonym step is never duplicated.
                // Browse by type clears the query and the filter,
                // which returns the learner to the browse content.
                VStack(spacing: PFSpacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(.pfScreenTitle.weight(.regular))
                        .foregroundColor(.pfSecondaryText)
                        .pfDecorative()
                    if debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("No results match this filter")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No results for \"\(debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(noResultsHintText)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .multilineTextAlignment(.center)
                    if hasActiveFilters {
                        PFSecondaryButton(title: "Clear filter") {
                            selectedLevels = []
                        }
                        .padding(.horizontal, PFSpacing.xl)
                    }
                    if shouldShowNoResultsFallbackChips {
                        Text("Try a popular search")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                        // The same three examples the hint names,
                        // made tappable. All three are in the
                        // popular searches list.
                        FlowChips(items: ["MT103", "SEPA", "chargeback"], onTap: { runSearch($0) })
                            .frame(maxWidth: .infinity)
                    }
                    PFSecondaryButton(title: "Browse by type") {
                        query = ""
                        debouncedQuery = ""
                        selectedLevels = []
                        isSearchFieldFocused = false
                    }
                    .padding(.horizontal, PFSpacing.xl)
                }
                .padding(PFSpacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // A second or later query: the results below still
                // belong to the previous query until the debounce
                // catches up or the new snapshot lands, so a small
                // searching indicator says so instead of leaving
                // stale results unexplained.
                // The first query uses the full-screen state above.
                if isAwaitingDebouncedSearch || isAwaitingSnapshot {
                    HStack(spacing: PFSpacing.sm) {
                        ProgressView()
                        Text("Searching...")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                    }
                    .padding(.horizontal, PFSpacing.lg)
                    .padding(.top, PFSpacing.md)
                    .accessibilityLabel("Searching")
                }
                // The scroll rule for the results List: each
                // return and each new query bumps the List
                // generation (state above) and restarts it at
                // the top. The handlers sit on the header, whose
                // identity is stable: on the List itself the
                // recreation would refire onAppear in a loop.
                resultsHeader
                    .onAppear { resultsListGeneration += 1 }
                    .onChange(of: debouncedQuery) { _, _ in resultsListGeneration += 1 }
                List {
                    if !matchedChapters.isEmpty {
                        Section(header: Text("Courses (\(matchedChapters.count))")) {
                            ForEach(matchedChapters, id: \.self) { number in
                                NavigationLink(destination: ChapterDetailView(chapterNumber: number)) {
                                    courseResultRow(chapterNumber: number)
                                }
                                .listRowBackground(Color.pfCard)
                            }
                        }
                    }
                    ForEach(groupedResults, id: \.type) { group in
                        Section(header: Text("\(group.type.displayName)s (\(groupTotals[group.type] ?? group.entries.count))")) {
                            ForEach(group.entries) { scored in
                                resultRow(for: scored, situationsByID: situationsByID)
                            }
                        }
                    }
                    if filteredResults.count > visibleResultCount {
                        Section {
                            Button("Load more results") {
                                visibleResultCount += Self.resultsPageSize
                            }
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.pfRoyal)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .pfMinimumTouchTarget()
                            .listRowBackground(Color.pfCard)
                        }
                    }
                }
                .id(resultsListGeneration)
                .listStyle(.insetGrouped)
                // Keep rows on the card colour in both light and dark mode:
                // a default dark-mode row would make the navy row text
                // invisible. The bottom inset keeps the last row clear of
                // the tab bar.
                .scrollContentBackground(.hidden)
                .background(Color.pfBackground)
                .scrollDismissesKeyboard(.interactively)
                .pfTabBarClearance()
            }
        }
        .background(Color.pfBackground)
    }

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: PFSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: PFSpacing.sm) {
                Text(resultsCountText)
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if hasActiveFilters {
                    Button("Clear filter") {
                        selectedLevels = []
                    }
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfRoyal)
                    .buttonStyle(.plain)
                }
            }
            if !expansionNote.isEmpty {
                Text(expansionNote)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, PFSpacing.lg)
        .padding(.top, PFSpacing.md)
        .padding(.bottom, PFSpacing.sm)
    }

    private var resultsCountText: String {
        let count = filteredResults.count
        let noun = count == 1 ? "result" : "results"
        let shownQuery = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = min(visibleResultCount, count)
        let range = count > visibleResultCount
            ? "Showing \(shown) of \(count) \(noun)"
            : "\(count) \(noun)"
        if shownQuery.isEmpty {
            return "\(range) matching your filters"
        }
        return "\(range) for \"\(shownQuery)\""
    }

    /// One matching chapter in the Courses section: royal number
    /// tile, chapter number, title and lesson count, in the same
    /// visual language as the chapter rows on the Learn tab.
    /// Tapping opens the chapter's lesson list.
    private func courseResultRow(chapterNumber: Int) -> some View {
        let lessons = PFChapterHelper.lessons(forChapter: chapterNumber, in: contentService)
        let title = PFChapterHelper.chapterTitle(for: lessons, number: chapterNumber)
        let completed = lessons.filter { progressStore.isLessonComplete($0.id) }.count
        let bookNumber = PFBookModeReadingOrder.bookNumber(forInternalNumber: chapterNumber)
        let thumbnailPath = PFChapterHelper.chapterThumbnailPath(forChapter: chapterNumber, in: contentService)
        return HStack(alignment: .top, spacing: PFSpacing.md) {
            // The chapter thumbnail sits beside the title when the
            // website exposes one; the number tile otherwise.
            if thumbnailPath != nil {
                PFThumbnailView(thumbnailPath: thumbnailPath, size: 40, cornerRadius: 10)
            } else {
                Text(bookNumber.map(String.init) ?? "•")
                    .font(.pfCardTitle.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.pfRoyal)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                if let bookNumber {
                    Text("Chapter \(bookNumber)")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                } else {
                    Text("Outside the main reading path")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                }
                Text(title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(lessons.count) lessons, \(completed) complete")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.pfCaption.weight(.semibold))
                .foregroundColor(.pfSecondaryText)
                .padding(.top, PFSpacing.xs)
                .pfDecorative()
        }
        .textSelection(.disabled)
        .padding(.vertical, PFSpacing.xs)
    }

    /// A Situation for a search entry. The full data file wins when it
    /// has loaded (full explain, visual and stage); the search index
    /// entry is the fallback so the detail never goes empty. The
    /// lookup map is built once by the list, so this is one
    /// dictionary lookup instead of a scan of the whole file.
    private func situationFor(entry: SearchEntry, situationsByID: [String: FullSituationItem]) -> Situation {
        if let full = situationsByID[entry.id] {
            return situation(fromFull: full)
        }
        return situation(from: entry)
    }

    @ViewBuilder
    private func resultRow(for scored: SearchHit, situationsByID: [String: FullSituationItem]) -> some View {
        let entry = scored.entry
        switch entry.type {
        case .lesson:
            NavigationLink(destination: LessonView(entry: entry)) {
                SearchResultRow(entry: entry, reason: scored.reason, matchedTerm: scored.matchedTerm, query: debouncedQuery, situationsByID: situationsByID)
            }
            .listRowBackground(Color.pfCard)
        case .situation:
            NavigationLink(destination: SituationDetailView(situation: situationFor(entry: entry, situationsByID: situationsByID))) {
                SearchResultRow(entry: entry, reason: scored.reason, matchedTerm: scored.matchedTerm, query: debouncedQuery, situationsByID: situationsByID)
            }
            .listRowBackground(Color.pfCard)
        case .guide, .lab, .test, .faq:
            Button {
                sheetEntry = entry
            } label: {
                SearchResultRow(entry: entry, reason: scored.reason, matchedTerm: scored.matchedTerm, query: debouncedQuery, situationsByID: situationsByID)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.pfCard)
        }
    }
}

// MARK: - Shared row (mockup Screen 5 layout)

/// Icon tile left, bold title (2 lines max), tags below (scheme,
/// category, level, plus a status tag when one applies), the match
/// reason underneath, and a bookmark button on the right that
/// toggles the saved state. The button is borderless, so tapping it
/// does not follow the row's navigation link. The type icons match
/// the Learn library rows (unfilled book, flask and checkmark).
private struct SearchResultRow: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var storeManager: StoreManager
    @ObservedObject private var bookmarkStore = PFBookmarkStore.shared

    let entry: SearchEntry
    var reason: String = ""
    /// The term that matched in the title, for highlighting. Nil
    /// when the match is only in the body text.
    var matchedTerm: String? = nil
    /// The query that produced these results, for highlighting.
    var query: String = ""
    /// The full situations file as a lookup map, built once by the
    /// list that owns this row. Nil falls back to a scan of the
    /// loaded file, so a caller without a map still works; every
    /// caller in this file passes one, so no row scans the file
    /// on every render.
    var situationsByID: [String: FullSituationItem]? = nil

    /// True when this row is a locked situation: not a free sample
    /// and Practice Experiences not unlocked. The row itself shows
    /// teaser fields only (title, tags, read time, match reason),
    /// never excerpt text; the identifier lets the D101 UI test
    /// open a locked result from search and assert the detail gate.
    private var isLockedSituation: Bool {
        entry.type == .situation
            && !ContentService.freeSampleIDs.contains(entry.id)
            && !storeManager.isPracticeUnlocked
    }

    private var systemImage: String {
        switch entry.type {
        case .lesson: return "play.fill"
        case .guide: return "book"
        case .situation: return "briefcase.fill"
        case .lab: return "flask"
        case .test: return "checkmark.circle"
        case .faq: return "questionmark.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: PFSpacing.md) {
            // The thumbnail sits beside the title when the
            // website exposes one; the type icon tile otherwise.
            if entry.thumbnail != nil {
                PFThumbnailView(thumbnailPath: entry.thumbnail, size: 40, cornerRadius: 10)
            } else {
                PFIconTile(systemImage: systemImage, size: 40)
            }
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                Text(SearchService.highlightedTitle(entry.title, matchedTerm: matchedTerm, query: query))
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    // The highlighted title is styled fragments;
                    // VoiceOver reads the plain title once instead.
                    .accessibilityLabel(entry.title)
                if entry.type == .lesson, let position = PFChapterHelper.readingPositionLabel(for: entry, in: contentService) {
                    Text(position)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                }
                tagRow
                if let timeLabel {
                    HStack(spacing: PFSpacing.xs) {
                        Image(systemName: "clock")
                            .font(.pfCaption.weight(.semibold))
                            .accessibilityHidden(true)
                        Text(timeLabel)
                    }
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                }
                if !reason.isEmpty {
                    HStack(spacing: PFSpacing.xs) {
                        Image(systemName: "magnifyingglass")
                            .font(.pfCaption.weight(.semibold))
                            .accessibilityHidden(true)
                        Text(reason)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                }
            }
            Spacer(minLength: PFSpacing.sm)
            bookmarkIcon
        }
        // Search result titles cannot be selected or copied. The
        // search field itself is outside this row, so it stays
        // editable.
        .textSelection(.disabled)
        .padding(.vertical, PFSpacing.xs)
        .accessibilityIdentifier(isLockedSituation ? "lockedSituationSearchRow" : "searchResultRow")
    }

    /// Tags derived from the entry title and text only, with the
    /// full situations file winning for a situation's level and
    /// module. A tag is omitted when it cannot be derived, never
    /// invented. Tags wrap onto a second row (SearchTagFlow) so a
    /// result with five or six pills never overflows or clips on a
    /// narrow phone or at large text sizes.
    @ViewBuilder
    private var tagRow: some View {
        // The tags are computed inline here because this row owns its
        // own derivation, independent of the parent view's filters.
        let rail = SearchRowFacts.rail(for: entry)
        let topic = topicTag
        let level = levelTag
        SearchTagFlow(spacing: PFSpacing.xs) {
            PFPill(text: entry.type.displayName)
            if let rail {
                PFPill(text: rail)
            }
            if let topic {
                PFPill(text: topic, background: Color.pfNavySoft, foreground: .pfNavy)
            }
            if let level {
                PFLevelPill(text: level.displayName)
            }
            if entry.type == .lesson && progressStore.isLessonComplete(entry.id) {
                PFPill(
                    text: "Completed",
                    background: Color.pfSuccess.opacity(0.12),
                    foreground: .pfSuccess
                )
            }
            if entry.type == .situation && ContentService.freeSampleIDs.contains(entry.id) {
                PFPill(text: "Free", background: Color.pfGoldSoft, foreground: .pfGold)
            }
            if entry.type == .situation
                && !ContentService.freeSampleIDs.contains(entry.id)
                && !storeManager.isPracticeUnlocked {
                PFPill(text: "Premium", background: Color.pfGoldSoft, foreground: .pfGold)
            }
            if entry.type == .lesson && isLessonLocked {
                PFPill(text: "Premium", background: Color.pfGoldSoft, foreground: .pfGold)
            }
        }
    }

    /// True when this lesson's chapter is not unlocked: neither the
    /// part containing it nor the Integrated Course is owned. An
    /// entry with no chapter number is never locked.
    private var isLessonLocked: Bool {
        guard entry.type == .lesson,
              let number = PFChapterHelper.chapterNumber(from: entry.id) else { return false }
        return !storeManager.isChapterUnlocked("ch\(number)")
    }

    /// Approximate time for this result: the narration length
    /// for a lesson when the manifest knows it, labelled as listen
    /// time. Other types show no time: the indexed text is a
    /// truncated excerpt, and timing it stamps a fake read time.
    /// Nil shows nothing.
    private var timeLabel: String? {
        guard entry.type == .lesson else { return nil }
        return LessonDurations.listenLabel(for: entry.id)
    }

    /// The full situation for this row's entry, from the lookup
    /// map when the list supplied one, else a scan of the loaded
    /// file. Same item either way: the map is first-wins, exactly
    /// as first(where:) is.
    private func fullSituation() -> FullSituationItem? {
        if let lookup = situationsByID {
            return lookup[entry.id]
        }
        return contentService.fullSituations?.first(where: { $0.id == entry.id })
    }

    /// The lifecycle category tag: the module for situations (full
    /// data file), the chapter title for lessons (second line of the
    /// entry text). Nil otherwise.
    private var topicTag: String? {
        if entry.type == .situation {
            return fullSituation()?.module
        }
        if entry.type == .lesson {
            let parts = entry.text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 { return parts[1] }
        }
        return nil
    }

    /// The level tag: the full data file level for situations, a text
    /// hint otherwise, Core as the situation default (the same rule
    /// situation(from:) uses). Nil for other types with no hint.
    private var levelTag: SituationLevel? {
        if entry.type == .situation {
            if let full = fullSituation() {
                switch full.level.lowercased() {
                case "foundation": return .foundation
                case "advanced": return .advanced
                default: return .core
                }
            }
            let lower = entry.text.lowercased()
            if lower.contains("foundation") { return .foundation }
            if lower.contains("advanced") { return .advanced }
            return .core
        }
        let lower = entry.text.lowercased()
        if lower.contains("foundation") { return .foundation }
        if lower.contains("advanced") { return .advanced }
        return nil
    }

    /// A bookmark button for lessons and situations: tapping it
    /// toggles the saved state in PFBookmarkStore without opening
    /// the item. Borderless, so the tap does not also follow the
    /// row's navigation link. The labels match the detail views.
    @ViewBuilder
    private var bookmarkIcon: some View {
        if entry.type == .lesson || entry.type == .situation {
            let marked = entry.type == .lesson
                ? bookmarkStore.isLessonBookmarked(entry.id)
                : bookmarkStore.isSituationBookmarked(entry.id)
            Button {
                if entry.type == .lesson {
                    bookmarkStore.toggleLesson(entry.id)
                } else {
                    bookmarkStore.toggleSituation(entry.id)
                }
            } label: {
                Image(systemName: marked ? "bookmark.fill" : "bookmark")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(marked ? .pfGold : .pfSecondaryText)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .pfMinimumTouchTarget()
            .accessibilityLabel(
                marked ? "Remove bookmark"
                    : entry.type == .lesson ? "Bookmark this lesson" : "Bookmark this situation"
            )
        }
    }
}

// MARK: - Row-level derivation (shared by the row only)
//
// SearchResultRow derives its rail tag itself so the browse-by-type
// list shows the same tags without depending on the parent view's
// state. Level and topic come from the row's own contentService-backed
// helpers above, so they use the full situations file. The rule is the
// same everywhere: title and text only, never invented.

private enum SearchRowFacts {
    static func rail(for entry: SearchEntry) -> String? {
        SearchService.rail(for: entry)
    }
}

// MARK: - Filter menu chip (mockup pill style)
//
// A Menu styled as a pill: royal blue with white text when a choice
// is active, white with a hairline border otherwise. Used for the
// MARK: - Browse by type list

private struct SearchTypeListView: View {
    @EnvironmentObject private var contentService: ContentService
    let type: SearchEntryType

    @State private var sheetEntry: SearchEntry? = nil

    /// Entries shown at first: 20 per page, Load more adds 20.
    /// A type can hold many entries, so the full list is
    /// never built at once. The view is created fresh per type,
    /// so the count starts at page 1 on every navigation.
    private static let typeListPageSize = 20
    @State private var visibleCount = 20
    /// List identity: the scroll rule for Lists. Back from a
    /// pushed lesson recreates the List at the top instead of
    /// restoring the old offset. Load more never bumps it.
    @State private var typeListGeneration = 0

    private var entries: [SearchEntry] {
        guard let index = contentService.searchIndex else { return [] }
        return index.entries.filter { $0.type == type }
    }

    /// The entries actually rendered: the first page(s).
    private var visibleEntries: [SearchEntry] {
        Array(entries.prefix(visibleCount))
    }

    /// The full situations file as a lookup map, first item wins
    /// for a repeated id (exactly as first(where:) behaved).
    /// Read once per body evaluation and passed to the rows, so
    /// no row scans the whole file on every render.
    private var situationLookup: [String: FullSituationItem] {
        var lookup: [String: FullSituationItem] = [:]
        for item in contentService.fullSituations ?? [] {
            if lookup[item.id] == nil {
                lookup[item.id] = item
            }
        }
        return lookup
    }

    /// A Situation for a search entry. The full data file wins when it
    /// has loaded (full explain, visual and stage); the search index
    /// entry is the fallback so the detail never goes empty. The
    /// lookup map is built once by the list, so this is one
    /// dictionary lookup instead of a scan of the whole file.
    private func situationFor(entry: SearchEntry, situationsByID: [String: FullSituationItem]) -> Situation {
        if let full = situationsByID[entry.id] {
            return situation(fromFull: full)
        }
        return situation(from: entry)
    }

    var body: some View {
        let situationsByID = situationLookup
        return Group {
            if contentService.isLoadingIndex && contentService.searchIndex == nil {
                VStack(spacing: PFSpacing.lg) {
                    ProgressView()
                    Text("Loading the course catalogue...")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = contentService.indexError, contentService.searchIndex == nil {
                // The catalogue failed to load: a terminal failure
                // state with Retry, not the "still loading" text.
                VStack(spacing: PFSpacing.lg) {
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            Text("Could not load the catalogue")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            Text(error)
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                            PFPrimaryButton(title: "Retry") {
                                Task { await contentService.loadSearchIndex() }
                            }
                        }
                    }
                    .padding(.horizontal, PFSpacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                // The catalogue loaded and this type genuinely has
                // no entries: say so, instead of claiming it is
                // still loading.
                VStack(spacing: PFSpacing.md) {
                    Text("Nothing here yet")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text("There are no \(type.displayName.lowercased())s in the catalogue.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(PFSpacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleEntries) { entry in
                        row(for: entry, situationsByID: situationsByID)
                    }
                    if entries.count > visibleCount {
                        Section {
                            VStack(spacing: PFSpacing.xs) {
                                Text("Showing \(visibleCount) of \(entries.count) \(type.displayName.lowercased())s")
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                                Button("Load more") {
                                    visibleCount += Self.typeListPageSize
                                }
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.pfRoyal)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .pfMinimumTouchTarget()
                            }
                            .listRowBackground(Color.pfCard)
                        }
                    }
                }
                .id(typeListGeneration)
                .listStyle(.insetGrouped)
                // Same dark-mode row treatment as the results list above:
                // rows stay on the card colour so navy text stays visible.
                .scrollContentBackground(.hidden)
                .background(Color.pfBackground)
                .pfTabBarClearance()
            }
        }
        .onAppear { typeListGeneration += 1 }
        .navigationTitle(type.displayName + "s")
        .sheet(item: $sheetEntry) { entry in
            SearchEntrySheet(entry: entry)
        }
    }

    @ViewBuilder
    private func row(for entry: SearchEntry, situationsByID: [String: FullSituationItem]) -> some View {
        switch entry.type {
        case .lesson:
            NavigationLink(destination: LessonView(entry: entry)) {
                SearchResultRow(entry: entry, situationsByID: situationsByID)
            }
            .listRowBackground(Color.pfCard)
        case .situation:
            NavigationLink(destination: SituationDetailView(situation: situationFor(entry: entry, situationsByID: situationsByID))) {
                SearchResultRow(entry: entry, situationsByID: situationsByID)
            }
            .listRowBackground(Color.pfCard)
        case .guide, .lab, .test, .faq:
            Button {
                sheetEntry = entry
            } label: {
                SearchResultRow(entry: entry, situationsByID: situationsByID)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.pfCard)
        }
    }
}

// MARK: - Full-text sheet for guides, labs, tests and FAQs

/// Shows the full text of a guide, lab, test or FAQ entry in a sheet.
/// Private to this file so it cannot collide with types other screens own.
private struct SearchEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var storeManager: StoreManager
    @EnvironmentObject private var contentService: ContentService
    let entry: SearchEntry

    @State private var showCheckout = false

    /// The entry's position among entries of its type, in catalogue
    /// order. Nil when the entry is not in the loaded list.
    private var indexInType: Int? {
        switch entry.type {
        case .faq:
            return contentService.allFAQs.firstIndex(of: entry)
        case .lab:
            return contentService.allLabs.firstIndex(of: entry)
        case .lesson, .guide, .situation, .test:
            return nil
        }
    }

    /// Whether the entry's chapter is unlocked, for tests. True for
    /// every other type, and for a test with no chapter number.
    private var isChapterUnlocked: Bool {
        guard entry.type == .test,
              let number = entry.chapterNumber else { return true }
        return storeManager.isChapterUnlocked("ch\(number)")
    }

    private var isLocked: Bool {
        EntryAccessRules.isLocked(
            entry,
            indexInType: indexInType,
            isPracticeUnlocked: storeManager.isPracticeUnlocked,
            isInterviewUnlocked: storeManager.isInterviewUnlocked,
            isChapterUnlocked: isChapterUnlocked
        )
    }

    /// The product that unlocks this entry, for the lock card.
    private var unlockingProduct: CourseProduct? {
        let chapterProductID: String?
        if entry.type == .test, let number = entry.chapterNumber {
            chapterProductID = storeManager.unlockingProduct(for: "ch\(number)")?.productID
        } else {
            chapterProductID = nil
        }
        guard let productID = EntryAccessRules.unlockingProductID(
            for: entry, chapterUnlockingProductID: chapterProductID) else { return nil }
        return ProductCatalogue.product(for: productID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    PFPill(text: entry.type.displayName)
                    Text(entry.title)
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                    if isLocked {
                        lockCard
                    } else {
                        PFBodyText(text: entry.text)
                    }
                }
                .padding(PFSpacing.lg)
            }
            // Copy protection: guide, lab, test and FAQ text cannot
            // be selected, a faint identity watermark sits over it,
            // and recording blurs it out.
            .pfProtectedContent()
            .background(Color.pfBackground)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: PFSpacing.xl)
            }
            .navigationTitle(entry.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCheckout) {
                CheckoutView()
            }
        }
    }

    /// The lock card shown in place of locked full text. The title
    /// stays visible (discovery); only the text is gated.
    private var lockCard: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Label("\(entry.type.displayName) locked", systemImage: "lock.fill")
                .font(.pfCaptionBold)
                .foregroundColor(.pfNavy)
            if let product = unlockingProduct {
                Text(lockCopy(for: product))
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFPrimaryButton(title: "View \(product.name)") {
                    showCheckout = true
                }
            }
        }
    }

    private func lockCopy(for product: CourseProduct) -> String {
        let pricePart = storeManager.isPriceAvailable(for: product.productID)
            ? " for \(storeManager.priceText(for: product.productID))"
            : ""
        let integratedNote = product.productID == ProductCatalogue.integratedProductID
            ? ""
            : " The Integrated Course includes it too."
        switch entry.type {
        case .faq:
            return "This FAQ answer is part of Interview Ready: \(ContentManifest.faqCount) FAQ answers and \(ContentManifest.interviewQuestionCount) interview questions\(pricePart), with 1 year of access.\(integratedNote)"
        case .lab:
            return "This lab is part of \(product.name)\(pricePart), with 1 year of access.\(integratedNote)"
        case .test:
            return "This test belongs to \(product.name)\(pricePart), with 1 year of access.\(integratedNote)"
        case .lesson, .guide, .situation:
            return ""
        }
    }
}

// MARK: - Wrapping tag layout
//
// Search result tags flow onto a second row instead of overflowing
// on a narrow screen. A plain SwiftUI Layout (iOS 16+), the same
// pattern as SituationsView's PillFlow, kept private to this file
// because the row owns its own tag layout.

private struct SearchTagFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

// MARK: - Wrapping chip grid
//
// Chips sit in ONE horizontally scrolling row of small compact
// pills, never a wrapped multi-line block: recent and popular
// searches read as a single line the learner can swipe through,
// with the same tap-to-search behaviour on each chip.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PFSpacing.sm) {
                ForEach(items, id: \.self) { item in
                    Button {
                        onTap(item)
                    } label: {
                        Text(item)
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.pfRoyal.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pfMinimumTouchTarget()
                }
            }
            .padding(.vertical, 2)
        }
    }
}
