// SearchView.swift
// PaymentForge iOS - Search across the whole catalogue.
// Native SwiftUI only, no WebView.
//
// Layout follows the mockup (DESIGN_REFERENCE.md, Screen 5): filter
// chips above the search field (All / Lifecycle / Scheme / Difficulty),
// result rows with an icon tile on the left, a bold title (2 lines
// max), tags below (scheme, category, level) and a bookmark icon on
// the right. The bookmark icon shows the saved state from
// PFBookmarkStore; bookmarking itself happens in the lesson and
// situation detail views, the same pattern SituationsView uses, so a
// row never nests a button inside its navigation link.
//
// Smarter search: the query is expanded through a payments-domain
// acronym, synonym and failure-symptom map in SearchService, so
// typing "RRN", "UTR" or "beneficiary not credited" also finds entries
// that only use the expanded terms. Every result says why it matched.
// Typing waits ~0.3s (debounce) before the search runs; suggestions
// appear as you type and recent searches persist on device. Filters
// (Lifecycle, Scheme, Difficulty, Type, Progress, Access) are
// derived from the entry title and text only, never invented. Duration
// is deliberately NOT offered as a filter: narration length lives only
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
    /// The query the results actually ran for. Updated ~0.3s after
    /// the user stops typing, so typing never re-filters on every
    /// keystroke. See the .task(id: query) debounce in body.
    @State private var debouncedQuery = ""
    /// The last query recorded in recents, so the debounce records
    /// each distinct search once.
    @State private var lastRecordedQuery = ""
    @State private var recentSearches: [String] = SearchService.recentSearches()
    @State private var sheetEntry: SearchEntry? = nil
    @State private var selectedBrowseType: SearchEntryType? = nil

    // MARK: - Filter state (mockup chips + extra filters)

    @State private var selectedLevel: SituationLevel? = nil
    @State private var selectedRail: String? = nil
    @State private var selectedLifecycle: String? = nil
    @State private var selectedType: SearchEntryType? = nil
    @State private var completedFilter: SearchCompletedFilter = .all
    @State private var accessFilter: SearchAccessFilter = .all

    /// Results shown at first: 20 per page, Load more adds 20.
    /// Only the shown results are grouped and rendered, so a
    /// filter matching 1,500 entries never builds 1,500 rows.
    private static let resultsPageSize = 20
    @State private var visibleResultCount = 20

    private enum SearchCompletedFilter: String, CaseIterable {
        case all = "All"
        case completed = "Completed"
        case notCompleted = "Not completed"
    }

    private enum SearchAccessFilter: String, CaseIterable {
        case all = "All"
        case free = "Free"
        case premium = "Premium"
    }

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

    /// Scheme filter options, in match order. Derived from the entry
    /// title and text only, never invented. The single source of
    /// truth lives in SearchService, which also owns detection.
    private var railOptions: [String] { SearchService.railOptions }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasActiveFilters: Bool {
        selectedLevel != nil || selectedRail != nil || selectedLifecycle != nil
            || selectedType != nil || completedFilter != .all || accessFilter != .all
    }

    private var mockupFiltersActive: Bool {
        selectedLevel != nil || selectedRail != nil || selectedLifecycle != nil
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
    /// Situation titles and the synonym map.
    private var liveSuggestions: [SearchSuggestion] {
        SearchService.suggestions(query: query, entries: contentService.searchIndex?.entries ?? [])
    }

    // MARK: - Results

    /// Ranked results for the debounced query, from SearchService:
    /// title outranks body, exact phrase outranks partial, synonym
    /// and symptom expansions resolve to the right cases, and a 1-2
    /// edit typo still finds the right lesson or Situation. Free
    /// samples and lessons in the learner's current chapter (the
    /// chapter of the last lesson they opened) rank higher. Completed
    /// items are marked in the row, never hidden. Capped at 60.
    private var scoredResults: [SearchHit] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let chapterPrefix = progressStore.lastLessonID.flatMap { SearchService.chapterPrefix(forLessonID: $0) }
        return SearchService.search(
            entries: contentService.searchIndex?.entries ?? [],
            query: q,
            freeSampleIDs: Set(ContentService.freeSampleIDs),
            currentChapterPrefix: chapterPrefix
        )
    }

    /// Every catalogue entry, with no match reason. Used when filters
    /// are set with no search text, so the mockup chips work on their own.
    private var allEntries: [SearchHit] {
        (contentService.searchIndex?.entries ?? []).map {
            SearchHit(entry: $0, score: 0, reason: "", matchedTerm: nil)
        }
    }

    private var baseResults: [SearchHit] {
        debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? allEntries : scoredResults
    }

    private var filteredResults: [SearchHit] {
        baseResults.filter { scored in
            let entry = scored.entry
            if let wantedLevel = selectedLevel, level(for: entry) != wantedLevel { return false }
            if let wantedRail = selectedRail, rail(for: entry) != wantedRail { return false }
            if let lifecycle = selectedLifecycle, topic(for: entry) != lifecycle { return false }
            if let type = selectedType, entry.type != type { return false }
            switch completedFilter {
            case .all:
                break
            case .completed:
                guard progressStore.isLessonComplete(entry.id) else { return false }
            case .notCompleted:
                guard !progressStore.isLessonComplete(entry.id) else { return false }
            }
            switch accessFilter {
            case .all:
                break
            case .free:
                guard isFree(entry) else { return false }
            case .premium:
                guard isLocked(entry) else { return false }
            }
            return true
        }
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

    /// Chapters whose title, or whose course name, matches the
    /// debounced query, so a search for "ISO 20022" shows the
    /// ISO 20022 chapters as well as their lessons. Title matches
    /// first, then course-name matches, capped at 10 so one broad
    /// query never floods the results. Empty when there is no
    /// query: courses appear only for a search, never for filters.
    private var matchedChapters: [Int] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var titleMatches: [Int] = []
        var bundleMatches: [Int] = []
        for number in PFChapterHelper.chapterNumbers(in: contentService) {
            let lessons = PFChapterHelper.lessons(forChapter: number, in: contentService)
            let title = PFChapterHelper.chapterTitle(for: lessons, number: number)
            if title.lowercased().contains(q) {
                titleMatches.append(number)
            } else if let bundle = PaymentConfig.productContaining("ch\(number)"),
                      bundle.name.lowercased().contains(q) {
                bundleMatches.append(number)
            }
        }
        return Array((titleMatches + bundleMatches).prefix(10))
    }

    /// One string for the current query and filters, so a change
    /// to any of them resets the pagination to page 1.
    private var filterSignature: String {
        [
            debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            selectedLevel?.rawValue ?? "",
            selectedRail ?? "",
            selectedLifecycle ?? "",
            selectedType?.rawValue ?? "",
            completedFilter.rawValue,
            accessFilter.rawValue
        ].joined(separator: "|")
    }

    /// Lifecycle options from the real catalogue: the chapter title
    /// for lessons and the module for situations. Sorted, capped so
    /// the menu stays usable.
    private var lifecycleOptions: [String] {
        guard let index = contentService.searchIndex else { return [] }
        var topics = Set<String>()
        for entry in index.entries {
            if let topic = topic(for: entry) {
                topics.insert(topic)
            }
        }
        return Array(Array(topics).sorted().prefix(24))
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

    // MARK: - Derived entry facts (title and text only, never invented)

    /// The rail named by an entry title or text, or nil when it names
    /// none. Detection lives in SearchService (title and text only,
    /// never invented).
    private func rail(for entry: SearchEntry) -> String? {
        SearchService.rail(for: entry)
    }

    /// The level of an entry, or nil when it cannot be derived.
    /// Situations use the full data file level first, then a text
    /// hint, defaulting to Core the same way situation(from:) does.
    /// Other types only get a level when their text names one.
    private func level(for entry: SearchEntry) -> SituationLevel? {
        if entry.type == .situation {
            if let full = contentService.fullSituations?.first(where: { $0.id == entry.id }) {
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

    /// The lifecycle category of an entry: the module for situations,
    /// the chapter title (second line of the entry text) for lessons.
    /// Nil for everything else, so no category is ever invented.
    private func topic(for entry: SearchEntry) -> String? {
        if entry.type == .situation {
            return contentService.fullSituations?.first(where: { $0.id == entry.id })?.module
        }
        if entry.type == .lesson {
            let parts = entry.text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 { return parts[1] }
        }
        return nil
    }

    /// Free means open content. A situation is free when it is one
    /// of the 10 free samples. A lesson is free when its chapter is
    /// unlocked. Guides, labs, tests and FAQs are open.
    private func isFree(_ entry: SearchEntry) -> Bool {
        if entry.type == .situation {
            return ContentService.freeSampleIDs.contains(entry.id)
        }
        if entry.type == .lesson {
            return isLessonUnlocked(entry)
        }
        return true
    }

    /// Locked means a situation that is not a free sample and the
    /// user has not unlocked Payment Situations, or a lesson whose
    /// chapter is not unlocked.
    private func isLocked(_ entry: SearchEntry) -> Bool {
        if entry.type == .situation {
            return !ContentService.freeSampleIDs.contains(entry.id)
                && !storeManager.isSituationsUnlocked
        }
        if entry.type == .lesson {
            return !isLessonUnlocked(entry)
        }
        return false
    }

    /// A lesson is unlocked when its chapter is: the bundle
    /// containing it, or the Integrated Course, is owned. An entry
    /// with no chapter number is never locked.
    private func isLessonUnlocked(_ entry: SearchEntry) -> Bool {
        guard let number = PFChapterHelper.chapterNumber(from: entry.id) else { return true }
        return storeManager.isChapterUnlocked("ch\(number)")
    }

    private func clearMockupFilters() {
        selectedLevel = nil
        selectedRail = nil
        selectedLifecycle = nil
    }

    private func clearAllFilters() {
        clearMockupFilters()
        selectedType = nil
        completedFilter = .all
        accessFilter = .all
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterChipsRow
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
            }
            .sheet(item: $sheetEntry) { entry in
                SearchEntrySheet(entry: entry)
            }
            .navigationDestination(item: $selectedBrowseType) { type in
                SearchTypeListView(type: type)
            }
            // Debounced search: waits 0.3s after the user stops typing
            // before running the search, so typing never re-filters on
            // every keystroke. The task restarts (and the previous one
            // is cancelled) on each keystroke. The finished query is
            // recorded in recents once.
            .task(id: query) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                debouncedQuery = trimmedQuery
                recordCurrentSearch()
            }
            // Any query or filter change: back to the first page of
            // results, so Load more never shows a stale slice.
            .onChange(of: filterSignature) { _, _ in
                visibleResultCount = Self.resultsPageSize
            }
        }
    }

    // MARK: - Filter chips above the search field (mockup Screen 5)

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PFSpacing.sm) {
                PFChip(text: "All", isSelected: !mockupFiltersActive) {
                    clearMockupFilters()
                }
                SearchFilterMenu(label: selectedLifecycle ?? "Lifecycle", isSelected: selectedLifecycle != nil) {
                    menuOption(title: "All lifecycles", isSelected: selectedLifecycle == nil) {
                        selectedLifecycle = nil
                    }
                    ForEach(lifecycleOptions, id: \.self) { option in
                        menuOption(title: option, isSelected: selectedLifecycle == option) {
                            selectedLifecycle = option
                        }
                    }
                }
                SearchFilterMenu(label: selectedRail ?? "Scheme", isSelected: selectedRail != nil) {
                    menuOption(title: "All schemes", isSelected: selectedRail == nil) {
                        selectedRail = nil
                    }
                    ForEach(railOptions, id: \.self) { option in
                        menuOption(title: option, isSelected: selectedRail == option) {
                            selectedRail = option
                        }
                    }
                }
                SearchFilterMenu(label: selectedLevel?.displayName ?? "Difficulty", isSelected: selectedLevel != nil) {
                    menuOption(title: "All difficulties", isSelected: selectedLevel == nil) {
                        selectedLevel = nil
                    }
                    ForEach([SituationLevel.foundation, .core, .advanced], id: \.self) { option in
                        menuOption(title: option.displayName, isSelected: selectedLevel == option) {
                            selectedLevel = option
                        }
                    }
                }
            }
            .padding(.horizontal, PFSpacing.lg)
        }
        .padding(.top, PFSpacing.md)
    }

    /// One option row inside a filter menu, with a checkmark on the
    /// current choice.
    private func menuOption(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    /// Always-visible search field below the filter chips. The
    /// navigation-bar search from .searchable can hide until the user
    /// scrolls, so the field lives here instead, where it is always
    /// tappable.
    private var searchField: some View {
        HStack(spacing: PFSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.pfSecondaryText)
            TextField("Search lessons, guides, situations", text: $query)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                    debouncedQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.pfSecondaryText)
                }
                .buttonStyle(.plain)
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
                                SearchService.clearRecentSearches()
                                recentSearches = []
                            }
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                            .buttonStyle(.plain)
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
                    VStack(spacing: PFSpacing.sm) {
                        ForEach(browseTypes, id: \.type) { item in
                            Button {
                                selectedBrowseType = item.type
                            } label: {
                                HStack {
                                    PFPill(text: item.type.displayName)
                                    Text(typeBrowseLabel(for: item.type))
                                        .font(.pfBody)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    if let count = item.count {
                                        Text("\(count)")
                                            .font(.pfCaptionBold)
                                            .foregroundColor(.pfSecondaryText)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.pfCaption.weight(.semibold))
                                        .foregroundColor(.pfSecondaryText)
                                }
                                .padding(PFSpacing.lg)
                                .background(Color.pfCard)
                                .cornerRadius(PFSpacing.cardRadius)
                                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        // Extra scrollable space at the bottom so the last row clears
        // the tab bar on every iPhone size.
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
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
                                Text(suggestion.title)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.pfCaption.weight(.semibold))
                                    .foregroundColor(.pfSecondaryText)
                            }
                            .padding(.horizontal, PFSpacing.lg)
                            .padding(.vertical, PFSpacing.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, PFSpacing.sm)
            }
        }
    }

    private var resultsContent: some View {
        VStack(spacing: 0) {
            extraFilterRow
            suggestionsSection
            if !trimmedQuery.isEmpty && debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: PFSpacing.md) {
                    ProgressView()
                    Text("Searching...")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
                .padding(PFSpacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredResults.isEmpty {
                VStack(spacing: PFSpacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(.pfScreenTitle.weight(.regular))
                        .foregroundColor(.pfSecondaryText)
                    if debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("No results match these filters")
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
                    Text("Try a different word, for example MT103, SEPA or chargeback, or clear your filters.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .multilineTextAlignment(.center)
                    if hasActiveFilters {
                        PFSecondaryButton(title: "Clear filters") {
                            clearAllFilters()
                        }
                        .padding(.horizontal, PFSpacing.xl)
                    }
                }
                .padding(PFSpacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsHeader
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
                        Section(header: Text("\(group.type.displayName)s (\(group.entries.count))")) {
                            ForEach(group.entries) { scored in
                                resultRow(for: scored)
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
                            .listRowBackground(Color.pfCard)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                // Keep rows on the card colour in both light and dark mode:
                // a default dark-mode row would make the navy row text
                // invisible. The bottom inset keeps the last row clear of
                // the tab bar.
                .scrollContentBackground(.hidden)
                .background(Color.pfBackground)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: PFSpacing.lg)
                }
            }
        }
        .background(Color.pfBackground)
    }

    /// Type, progress and access filters, shown while results are
    /// on screen. The mockup chips above the search field cover
    /// Lifecycle, Scheme and Difficulty; these three cover the rest.
    private var extraFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PFSpacing.sm) {
                SearchFilterMenu(label: selectedType?.displayName ?? "Type", isSelected: selectedType != nil) {
                    menuOption(title: "All types", isSelected: selectedType == nil) {
                        selectedType = nil
                    }
                    ForEach(typeOrder, id: \.self) { option in
                        menuOption(title: option.displayName, isSelected: selectedType == option) {
                            selectedType = option
                        }
                    }
                }
                SearchFilterMenu(label: completedFilter == .all ? "Progress" : completedFilter.rawValue, isSelected: completedFilter != .all) {
                    ForEach(SearchCompletedFilter.allCases, id: \.self) { option in
                        menuOption(title: option.rawValue, isSelected: completedFilter == option) {
                            completedFilter = option
                        }
                    }
                }
                SearchFilterMenu(label: accessFilter == .all ? "Access" : accessFilter.rawValue, isSelected: accessFilter != .all) {
                    ForEach(SearchAccessFilter.allCases, id: \.self) { option in
                        menuOption(title: option.rawValue, isSelected: accessFilter == option) {
                            accessFilter = option
                        }
                    }
                }
            }
            .padding(.horizontal, PFSpacing.lg)
        }
        .padding(.top, PFSpacing.md)
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
                    Button("Clear filters") {
                        clearAllFilters()
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
        return HStack(alignment: .top, spacing: PFSpacing.md) {
            Text("\(chapterNumber)")
                .font(.pfCardTitle.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.pfRoyal)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                Text("Chapter \(chapterNumber)")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfRoyal)
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
        }
        .textSelection(.disabled)
        .padding(.vertical, PFSpacing.xs)
    }

    /// A Situation for a search entry. The full data file wins when it
    /// has loaded (full explain, visual and stage); the search index
    /// entry is the fallback so the detail never goes empty.
    private func situationFor(entry: SearchEntry) -> Situation {
        if let full = contentService.fullSituations?.first(where: { $0.id == entry.id }) {
            return situation(fromFull: full)
        }
        return situation(from: entry)
    }

    @ViewBuilder
    private func resultRow(for scored: SearchHit) -> some View {
        let entry = scored.entry
        switch entry.type {
        case .lesson:
            NavigationLink(destination: LessonView(entry: entry)) {
                SearchResultRow(entry: entry, reason: scored.reason, matchedTerm: scored.matchedTerm, query: debouncedQuery)
            }
            .listRowBackground(Color.pfCard)
        case .situation:
            NavigationLink(destination: SituationDetailView(situation: situationFor(entry: entry))) {
                SearchResultRow(entry: entry, reason: scored.reason, matchedTerm: scored.matchedTerm, query: debouncedQuery)
            }
            .listRowBackground(Color.pfCard)
        case .guide, .lab, .test, .faq:
            Button {
                sheetEntry = entry
            } label: {
                SearchResultRow(entry: entry, reason: scored.reason, matchedTerm: scored.matchedTerm, query: debouncedQuery)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.pfCard)
        }
    }
}

// MARK: - Shared row (mockup Screen 5 layout)

/// Icon tile left, bold title (2 lines max), tags below (scheme,
/// category, level, plus a status tag when one applies), the match
/// reason underneath, and a bookmark icon on the right. The bookmark
/// icon is display only: it reflects PFBookmarkStore, and toggling
/// happens in the lesson and situation detail views.
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
        HStack(alignment: .top, spacing: PFSpacing.md) {
            PFIconTile(systemImage: systemImage, size: 40)
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                Text(SearchService.highlightedTitle(entry.title, matchedTerm: matchedTerm, query: query))
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                tagRow
                if !reason.isEmpty {
                    HStack(spacing: PFSpacing.xs) {
                        Image(systemName: "magnifyingglass")
                            .font(.pfCaption.weight(.semibold))
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
    }

    /// Tags derived from the entry title and text only, with the
    /// full situations file winning for a situation's level and
    /// module. A tag is omitted when it cannot be derived, never
    /// invented.
    @ViewBuilder
    private var tagRow: some View {
        // The tags are computed inline here because this row owns its
        // own derivation, independent of the parent view's filters.
        let rail = SearchRowFacts.rail(for: entry)
        let topic = topicTag
        let level = levelTag
        HStack(spacing: PFSpacing.xs) {
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
                && !storeManager.isSituationsUnlocked {
                PFPill(text: "Premium", background: Color.pfGoldSoft, foreground: .pfGold)
            }
            if entry.type == .lesson && isLessonLocked {
                PFPill(text: "Premium", background: Color.pfGoldSoft, foreground: .pfGold)
            }
        }
    }

    /// True when this lesson's chapter is not unlocked: neither the
    /// bundle containing it nor the Integrated Course is owned. An
    /// entry with no chapter number is never locked.
    private var isLessonLocked: Bool {
        guard entry.type == .lesson,
              let number = PFChapterHelper.chapterNumber(from: entry.id) else { return false }
        return !storeManager.isChapterUnlocked("ch\(number)")
    }

    /// The lifecycle category tag: the module for situations (full
    /// data file), the chapter title for lessons (second line of the
    /// entry text). Nil otherwise.
    private var topicTag: String? {
        if entry.type == .situation {
            return contentService.fullSituations?.first(where: { $0.id == entry.id })?.module
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
            if let full = contentService.fullSituations?.first(where: { $0.id == entry.id }) {
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

    @ViewBuilder
    private var bookmarkIcon: some View {
        if entry.type == .lesson || entry.type == .situation {
            let marked = entry.type == .lesson
                ? bookmarkStore.isLessonBookmarked(entry.id)
                : bookmarkStore.isSituationBookmarked(entry.id)
            Image(systemName: marked ? "bookmark.fill" : "bookmark")
                .font(.pfBody.weight(.semibold))
                .foregroundColor(marked ? .pfGold : .pfSecondaryText)
                .accessibilityLabel(marked ? "Bookmarked" : "Not bookmarked")
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
// Lifecycle, Scheme, Difficulty, Type, Progress and Access filters.

private struct SearchFilterMenu<Content: View>: View {
    let label: String
    let isSelected: Bool
    var content: () -> Content

    init(label: String, isSelected: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.isSelected = isSelected
        self.content = content
    }

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: PFSpacing.xs) {
                Text(label)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.pfCaption.weight(.semibold))
            }
            .font(.pfCaptionBold)
            .foregroundColor(isSelected ? .white : .pfNavy)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.pfRoyal : Color.pfCard)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.pfRoyal : Color.pfBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Browse by type list

private struct SearchTypeListView: View {
    @EnvironmentObject private var contentService: ContentService
    let type: SearchEntryType

    @State private var sheetEntry: SearchEntry? = nil

    /// Entries shown at first: 20 per page, Load more adds 20.
    /// A type like Lessons has 746 entries, so the full list is
    /// never built at once. The view is created fresh per type,
    /// so the count starts at page 1 on every navigation.
    private static let typeListPageSize = 20
    @State private var visibleCount = 20

    private var entries: [SearchEntry] {
        guard let index = contentService.searchIndex else { return [] }
        return index.entries.filter { $0.type == type }
    }

    /// The entries actually rendered: the first page(s).
    private var visibleEntries: [SearchEntry] {
        Array(entries.prefix(visibleCount))
    }

    /// A Situation for a search entry. The full data file wins when it
    /// has loaded (full explain, visual and stage); the search index
    /// entry is the fallback so the detail never goes empty.
    private func situationFor(entry: SearchEntry) -> Situation {
        if let full = contentService.fullSituations?.first(where: { $0.id == entry.id }) {
            return situation(fromFull: full)
        }
        return situation(from: entry)
    }

    var body: some View {
        Group {
            if contentService.isLoadingIndex && contentService.searchIndex == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                VStack(spacing: PFSpacing.md) {
                    Text("Nothing here yet")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text("The catalogue is still loading. Please try again in a moment.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(PFSpacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleEntries) { entry in
                        row(for: entry)
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
                            }
                            .listRowBackground(Color.pfCard)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                // Same dark-mode row treatment as the results list above:
                // rows stay on the card colour so navy text stays visible.
                .scrollContentBackground(.hidden)
                .background(Color.pfBackground)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: PFSpacing.lg)
                }
            }
        }
        .navigationTitle(type.displayName + "s")
        .sheet(item: $sheetEntry) { entry in
            SearchEntrySheet(entry: entry)
        }
    }

    @ViewBuilder
    private func row(for entry: SearchEntry) -> some View {
        switch entry.type {
        case .lesson:
            NavigationLink(destination: LessonView(entry: entry)) {
                SearchResultRow(entry: entry)
            }
            .listRowBackground(Color.pfCard)
        case .situation:
            NavigationLink(destination: SituationDetailView(situation: situationFor(entry: entry))) {
                SearchResultRow(entry: entry)
            }
            .listRowBackground(Color.pfCard)
        case .guide, .lab, .test, .faq:
            Button {
                sheetEntry = entry
            } label: {
                SearchResultRow(entry: entry)
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
    let entry: SearchEntry

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    PFPill(text: entry.type.displayName)
                    Text(entry.title)
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                    Text(entry.text)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
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
                }
            }
            .padding(.vertical, 2)
        }
    }
}
