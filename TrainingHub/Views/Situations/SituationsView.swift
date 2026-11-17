// SituationsView.swift
// Payments Training Hub iOS - Payment Situations: ContentManifest.situationCount real-world situations.
// Native SwiftUI only, no WebView.

import SwiftUI

// MARK: - SearchEntry to Situation mapping

/// Build a Situation from a search index entry.
///
/// The search index carries only id, title and text for situations, so
/// stage, stage name, level, explain and takeaway are derived as follows:
/// explain is the entry text, takeaway is the entry preview, and stage and
/// level use the defaults below unless the entry text contains a stage or
/// level hint. No stage numbers or levels are invented beyond those hints.
/// The result is marked derived (isStageAuthoritative is false): the
/// authoritative stage lives in the full data file, not the index.
func situation(from entry: SearchEntry) -> Situation {
    let lower = entry.text.lowercased()
    var stage = 1
    var stageName = "Stage 1"
    for candidate in 1...6 {
        if lower.contains("stage \(candidate)") {
            stage = candidate
            stageName = "Stage \(candidate)"
            break
        }
    }
    var level: SituationLevel = .core
    if lower.contains("foundation") {
        level = .foundation
    } else if lower.contains("advanced") {
        level = .advanced
    }
    return Situation(
        id: entry.id,
        title: entry.title,
        stage: stage,
        stageName: stageName,
        level: level,
        explain: entry.text,
        takeaway: entry.preview,
        isFreeSample: ContentService.freeSampleIDs.contains(entry.id),
        visual: nil,
        isStageAuthoritative: false,
        agenda: entry.agenda,
        thumbnail: entry.thumbnail
    )
}

/// Build a Situation from one full data-file item. The stage and stage
/// name come from the data file's own `stage` and `stage_name` fields
/// when present (authoritative for all ContentManifest.situationCount items, verified 11 Nov 2026);
/// ContentService falls back to the website stage map and then to the
/// level, and the result is marked derived in that case. The level
/// comes from the item itself, and the explain, takeaway and visual
/// are the full ones, not the search index excerpt.
func situation(fromFull item: FullSituationItem) -> Situation {
    let stage = ContentService.stage(forFullItem: item)
    let level: SituationLevel
    switch item.level.lowercased() {
    case "foundation": level = .foundation
    case "advanced": level = .advanced
    default: level = .core
    }
    return Situation(
        id: item.id,
        title: item.title,
        stage: stage,
        stageName: ContentService.stageName(forFullItem: item),
        level: level,
        explain: item.explain,
        takeaway: item.takeaway,
        isFreeSample: ContentService.freeSampleIDs.contains(item.id),
        visual: item.visual,
        isStageAuthoritative: ContentService.stageSource(forFullItem: item) == .authoritative,
        agenda: item.agenda,
        thumbnail: item.thumbnail
    )
}

/// Build a Situation from one compact index row. The level,
/// stage and stage name come from the row itself: the same
/// authoritative values as the full data file, so list rows,
/// filters and category counts are correct without downloading
/// the full file. Explain and takeaway stay empty until the
/// detail loads through SituationDetailLoaderView; the row
/// shows the title, pills and thumbnail only, never a read
/// time or body text. Thumbnail and agenda come from the
/// agenda-joined search index entry when one exists, so rows
/// keep their images.
func situation(fromIndex entry: SituationsIndexEntry, indexEntry: SearchEntry?) -> Situation {
    let level: SituationLevel
    switch entry.level.lowercased() {
    case "foundation": level = .foundation
    case "advanced": level = .advanced
    default: level = .core
    }
    let stage = entry.stage ?? 1
    return Situation(
        id: entry.id,
        title: entry.title,
        stage: stage,
        stageName: entry.stageName ?? "Stage \(stage)",
        level: level,
        explain: "",
        takeaway: "",
        isFreeSample: ContentService.freeSampleIDs.contains(entry.id),
        visual: nil,
        isStageAuthoritative: entry.stage != nil,
        agenda: indexEntry?.agenda,
        thumbnail: indexEntry?.thumbnail
    )
}

// MARK: - Scheme derivation (title keywords only)
//
// A scheme is shown only when the situation title itself names it.
// Titles name only a few schemes (UPI, SEPA, SWIFT, Cards, Direct
// Debit, ACH, Faster Payments, CHAPS, TARGET2, Fedwire, CHIPS, RuPay,
// Visa, Mastercard, NEFT, RTGS, IMPS, BACS, FedNow). No scheme is ever
// invented for an item whose title names none: scheme(for:) returns
// nil for those items, they appear under "All", and no scheme tag is
// shown on their row. Matching is on whole words, so "ACH" never
// matches inside another word.

/// The scheme candidates, in match order. "Cards" matches "card" or
/// "cards" in the title.
private let situationSchemeCandidates: [(label: String, pattern: String)] = [
    ("UPI", "upi"),
    ("SEPA", "sepa"),
    ("SWIFT", "swift"),
    ("Cards", "cards?"),
    ("Direct Debit", "direct debit"),
    ("ACH", "ach"),
    ("Faster Payments", "faster payments"),
    ("CHAPS", "chaps"),
    ("TARGET2", "target2"),
    ("Fedwire", "fedwire"),
    ("CHIPS", "chips"),
    ("RuPay", "rupay"),
    ("Visa", "visa"),
    ("Mastercard", "mastercard"),
    ("NEFT", "neft"),
    ("RTGS", "rtgs"),
    ("IMPS", "imps"),
    ("BACS", "bacs"),
    ("FedNow", "fednow"),
]

private func containsWord(_ text: String, pattern: String) -> Bool {
    // The regexes are compiled once and cached: the old code
    // compiled a fresh regex on every call, and scheme(for:) runs
    // for every row on every render, so one list render paid for
    // thousands of compilations. A pattern outside the cache (only
    // possible for a future caller) still compiles on the spot,
    // with the same pattern, so the match is identical.
    let regex: NSRegularExpression?
    if let cached = situationSchemeRegexes[pattern] {
        regex = cached
    } else {
        regex = try? NSRegularExpression(pattern: "\\b" + pattern + "\\b", options: [.caseInsensitive])
    }
    guard let regex else { return false }
    let range = NSRange(text.startIndex..., in: text)
    return regex.firstMatch(in: text, options: [], range: range) != nil
}

/// The compiled scheme regexes, one per candidate pattern.
private let situationSchemeRegexes: [String: NSRegularExpression] = {
    var map: [String: NSRegularExpression] = [:]
    for candidate in situationSchemeCandidates {
        if let regex = try? NSRegularExpression(pattern: "\\b" + candidate.pattern + "\\b", options: [.caseInsensitive]) {
            map[candidate.pattern] = regex
        }
    }
    return map
}()

/// The scheme named by a situation title, or nil when the title names
/// none. Never invented.
func scheme(for situation: Situation) -> String? {
    for candidate in situationSchemeCandidates {
        if containsWord(situation.title, pattern: candidate.pattern) {
            return candidate.label
        }
    }
    return nil
}

// MARK: - Explain parsing (split on the real structure only)
//
// The full explain text is one field in a fixed 13 to 17 paragraph
// format, paragraphs separated by blank lines:
//   opening paragraphs (the hook / scenario)
//   "Here is what happened:" / "Here is how it happens:" (and the
//   "Here's ..." variants) + an arrow list of what happened
//   "The requirement said:" or "The assumption was:" (the flawed
//   requirement; one item uses "The instruction was:"), followed by
//   what followed from it
//   "Why?" + the root-cause paragraphs
//   one insight sentence, the paragraph just before "BA Takeaway"
//   "BA Takeaway" + the recommended resolution, including a
//   "Keep these controls separate:" arrow list
//   "The real requirement is not ..." / "It is ..."
//   a closing question ("Have you ...?" / "Did you know ...?")
// A few items have no "Why?" paragraph: there the paragraphs between
// the flawed requirement and the insight sentence are the root cause.
// Nothing is written into a section that the text does not contain:
// when a marker is missing, that section is empty and the tab shows
// the full explain text instead, so no information is lost and none
// is fabricated.

/// The explain text split into its real parts. Any part may be empty.
struct ParsedSituationExplain {
    var opening: [String] = []
    var flowSteps: [String] = []
    var flawedRequirement: [String] = []
    var rootCause: [String] = []
    var insight: String? = nil
    var baBody: [String] = []
    var controls: [String] = []
    var realRequirement: [String] = []
    var closingQuestion: String? = nil

    /// True when the explain text carries the structured format at
    /// all (a flow header and a BA Takeaway heading). Short
    /// search-index excerpts do not, and fall back to full text.
    /// A BA section that holds only the controls list still counts
    /// as parsed: the resolution for those items is the controls.
    var isParsed: Bool { !opening.isEmpty && (!baBody.isEmpty || !controls.isEmpty) }
}

private func parseSituationExplain(_ explain: String) -> ParsedSituationExplain {
    let paragraphs = explain
        .components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    var parsed = ParsedSituationExplain()
    guard !paragraphs.isEmpty else { return parsed }

    func isFlowHeader(_ para: String) -> Bool {
        // Every variant starts with "Here" and ends with a colon and
        // contains "happen": "Here is what happened:", "Here is how
        // it happens:", "Here's how that happens:", and the curly
        // apostrophe spellings.
        para.hasPrefix("Here") && para.hasSuffix(":") && para.contains("happen")
    }
    func isFlawedHeader(_ para: String) -> Bool {
        para.hasPrefix("The requirement said:")
            || para.hasPrefix("The assumption was:")
            || para.hasPrefix("The assumption said:")
            || para.hasPrefix("The requirement says")
            || para.hasPrefix("The requirement is written")
            || para.hasPrefix("The instruction was:")
    }
    func arrowLines(_ para: String) -> [String] {
        para.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("→") }
            .map { String($0.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    let flowIndex = paragraphs.firstIndex(where: isFlowHeader)
    let flawedIndex = paragraphs.firstIndex(where: isFlawedHeader)
    let whyIndex = paragraphs.firstIndex { $0 == "Why?" }
    let baIndex = paragraphs.firstIndex { $0 == "BA Takeaway" }
    let realIndex = paragraphs.firstIndex { $0.hasPrefix("The real requirement") }

    // Closing question: the last paragraph, when it is a question to
    // the reader.
    var bodyEnd = paragraphs.count
    if let last = paragraphs.last,
       last.hasPrefix("Have you") || last.hasPrefix("Did you know") {
        parsed.closingQuestion = last
        bodyEnd -= 1
    }

    // Opening: everything before the flow header, or before the
    // flawed requirement when there is no flow header.
    let openingEnd = flowIndex ?? flawedIndex ?? bodyEnd
    parsed.opening = Array(paragraphs[..<openingEnd])

    // Flow steps: the arrow list right after the flow header.
    if let flowIndex, flowIndex + 1 < paragraphs.count {
        parsed.flowSteps = arrowLines(paragraphs[flowIndex + 1])
    }

    // Flawed requirement: the flawed paragraph plus what followed
    // from it, up to "Why?" (or up to the root-cause paragraphs when
    // there is no "Why?").
    if let flawedIndex {
        if let whyIndex {
            parsed.flawedRequirement = Array(paragraphs[flawedIndex..<whyIndex])
        } else if let baIndex, baIndex > flawedIndex + 1 {
            // No "Why?": only the flawed paragraph itself is the
            // flawed requirement; the paragraphs after it, up to the
            // insight sentence, are the root cause (handled below).
            parsed.flawedRequirement = [paragraphs[flawedIndex]]
        } else {
            parsed.flawedRequirement = Array(paragraphs[flawedIndex..<min(bodyEnd, paragraphs.count)])
        }
    }

    // Root cause: the paragraphs after "Why?", up to the insight
    // sentence (the paragraph just before "BA Takeaway"). Without a
    // "Why?", the paragraphs after the flawed requirement, up to the
    // insight sentence.
    if let baIndex, baIndex > 0 {
        // The insight is the single-sentence paragraph just before
        // "BA Takeaway". It is never an arrow list or a flow header.
        let candidate = paragraphs[baIndex - 1]
        if !candidate.contains("→") && !isFlowHeader(candidate) {
            parsed.insight = candidate
        }
        let causeStart: Int?
        if let whyIndex {
            causeStart = whyIndex + 1
        } else if let flawedIndex {
            causeStart = flawedIndex + 1
        } else {
            causeStart = nil
        }
        if let causeStart, causeStart < baIndex - 1 {
            // When there is an insight sentence it is excluded here
            // and shown on its own; without one, the last paragraph
            // before "BA Takeaway" belongs to the root cause.
            let causeEnd = parsed.insight == nil ? baIndex : baIndex - 1
            parsed.rootCause = Array(paragraphs[causeStart..<causeEnd])
        }
    }

    // Solution: everything after "BA Takeaway" up to the real
    // requirement. Arrow lists in this stretch are the controls to
    // keep separate; a paragraph ending in "separate:" is their
    // heading, not body text. Other paragraphs are the resolution.
    if let baIndex {
        let solutionEnd = realIndex ?? bodyEnd
        if baIndex + 1 < solutionEnd {
            for para in paragraphs[(baIndex + 1)..<solutionEnd] {
                let lines = arrowLines(para)
                if !lines.isEmpty {
                    parsed.controls.append(contentsOf: lines)
                } else if para.hasSuffix("separate:") || para.contains("keep them separate:") {
                    // Heading for the controls list, not body text.
                    continue
                } else {
                    parsed.baBody.append(para)
                }
            }
        }
    }

    // The real requirement: the "is not" / "It is" pair.
    if let realIndex, realIndex < bodyEnd {
        parsed.realRequirement = Array(paragraphs[realIndex..<bodyEnd])
    }

    return parsed
}

// MARK: - Situations list

/// One category in the category drawer: every case, the free
/// samples, or one learning stage. The drawer is the category
/// navigation: picking a category filters the flat list below,
/// and no category starts privileged over the others.
enum SituationCategory: Hashable {
    case all
    case freeSamples
    case stage(Int)

    var title: String {
        switch self {
        case .all: return "All cases"
        case .freeSamples: return "Free samples"
        case .stage(let stage): return "Stage \(stage) · \(ContentService.stageName(for: stage))"
        }
    }
}

struct SituationsView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var storeManager: StoreManager

    /// Opens the side drawer. Passed in from the tab bar so the menu
    /// button can sit in this screen's navigation bar, and only here:
    /// pushed detail views have no menu button and keep a clean back button.
    @Binding var isDrawerOpen: Bool

    /// Shows a Done button in the navigation bar when this view is
    /// pushed from Checkout after a build-phase Buy, so the learner
    /// has a way back: the pushed copy has no drawer, and its own
    /// NavigationStack hides the outer back button. False in the
    /// tab, where the drawer button is the way out.
    var showCloseButton: Bool = false

    /// Reselect tick from the tab bar: bumped when the learner
    /// taps the Payment Cases tab while already on it. Scrolls
    /// back to the top of the list.
    var tabReselectTick: Int = 0

    @Environment(\.dismiss) private var dismiss

    /// The difficulty filter, preserved across restarts through
    /// SceneStorage as the level's raw value (empty means no
    /// filter). The computed bridge keeps every existing read
    /// and write working.
    @SceneStorage("situations.levelFilter") private var storedLevelFilter = ""
    private var levelFilter: SituationLevel? {
        get { storedLevelFilter.isEmpty ? nil : SituationLevel(rawValue: storedLevelFilter) }
        nonmutating set { storedLevelFilter = newValue?.rawValue ?? "" }
    }
    @State private var selectedCategory: SituationCategory = .all
    @State private var isCategoryDrawerOpen = false
    @State private var showCheckout = false
    /// The list search text, preserved across restarts through
    /// SceneStorage. The computed bridge keeps every existing
    /// read and write working; the TextField binds through
    /// searchTextBinding below.
    @SceneStorage("situations.searchText") private var storedSearchText = ""
    private var searchText: String {
        get { storedSearchText }
        nonmutating set { storedSearchText = newValue }
    }
    private var searchTextBinding: Binding<String> {
        Binding(get: { searchText }, set: { searchText = $0 })
    }
    /// The scheme filter, preserved across restarts through
    /// SceneStorage (empty means no filter). The computed
    /// bridge keeps every existing read and write working.
    @SceneStorage("situations.schemeFilter") private var storedSchemeFilter = ""
    private var schemeFilter: String? {
        get { storedSchemeFilter.isEmpty ? nil : storedSchemeFilter }
        nonmutating set { storedSchemeFilter = newValue ?? "" }
    }
    @ObservedObject private var bookmarkStore = PFBookmarkStore.shared

    /// Numbered pagination for the flat case list: 20 cases per
    /// page, the current page in state. Only the shown page is
    /// rendered, so ContentManifest.situationCount cases never
    /// sit in the view hierarchy at once. Any filter or category
    /// change resets to page 1.
    @State private var currentPage = 1

    /// Scroll-back requests for page jumps: the bar sits inside
    /// the list section, which has no ScrollViewProxy, so a tap
    /// bumps this tick and the ScrollView content observes it
    /// and scrolls the list back to its top. Resets never bump
    /// it, so typing in the search field never yanks the view.
    @State private var pageScrollTick = 0

    /// Total pages over the filtered cases, and the current page
    /// clamped into them.
    private var totalCasePages: Int {
        PFPagination.totalPages(totalCount: filteredSituations.count)
    }

    private var effectiveCasePage: Int {
        PFPagination.clampedPage(currentPage, totalPages: totalCasePages)
    }

    /// The situations to show. The full data file wins when it has
    /// loaded (full explain, visual and stage); the compact
    /// situations index is next (authoritative stage and level,
    /// no body text, detail fetched per case on open); the search
    /// index entries are the fallback so the list never goes empty.
    private var allSituations: [Situation] {
        if let full = contentService.fullSituations, !full.isEmpty {
            return full.map { situation(fromFull: $0) }
        }
        if let index = contentService.situationsIndex, !index.items.isEmpty {
            let byID = Dictionary(uniqueKeysWithValues: contentService.allSituations.map { ($0.id, $0) })
            return index.items.map { situation(fromIndex: $0, indexEntry: byID[$0.id]) }
        }
        return contentService.allSituations.map { situation(from: $0) }
    }

    private var freeSamples: [Situation] {
        ContentService.freeSampleIDs.compactMap { id in
            allSituations.first { $0.id == id }
        }
    }

    /// Schemes actually named by at least one situation title, in
    /// candidate order. Only these get a chip; a scheme with no
    /// situation never appears as a filter.
    private var availableSchemes: [String] {
        situationSchemeCandidates.compactMap { candidate in
            allSituations.contains { scheme(for: $0) == candidate.label } ? candidate.label : nil
        }
    }

    private var filteredSituations: [Situation] {
        var list = categoryBase
        switch selectedCategory {
        case .all:
            break
        case .freeSamples:
            list = list.filter { $0.isFreeSample }
        case .stage(let stage):
            list = list.filter { $0.stage == stage }
        }
        return list
    }

    /// The situations filtered by everything except the category:
    /// the search text, the scheme chip, and the difficulty chip.
    /// The category drawer counts each category against this list,
    /// so its counts respect the other filters, and the flat list
    /// applies the category on top of it. The search matches the
    /// title, the explain text, and the takeaway: title-only
    /// matching hid cases whose title never names the search term.
    /// Index-mode situations carry no body text, so the search
    /// also matches the backing search index entry (its tags and
    /// excerpt), which keeps in-list search working without
    /// downloading the full file.
    private var categoryBase: [Situation] {
        var list = allSituations
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            let entriesByID = Dictionary(uniqueKeysWithValues: contentService.allSituations.map { ($0.id, $0) })
            list = list.filter {
                $0.title.lowercased().contains(query)
                    || $0.explain.lowercased().contains(query)
                    || $0.takeaway.lowercased().contains(query)
                    || (entriesByID[$0.id]?.searchText.lowercased().contains(query) ?? false)
            }
        }
        if let schemeFilter {
            list = list.filter { scheme(for: $0) == schemeFilter }
        }
        if let levelFilter {
            list = list.filter { $0.level == levelFilter }
        }
        return list
    }

    /// The count of one category against the current other
    /// filters, for the drawer rows.
    private func count(for category: SituationCategory) -> Int {
        switch category {
        case .all:
            return categoryBase.count
        case .freeSamples:
            return categoryBase.count { $0.isFreeSample }
        case .stage(let stage):
            return categoryBase.count { $0.stage == stage }
        }
    }

    /// The cases actually rendered: the current page of the
    /// filtered list.
    private var visibleSituations: [Situation] {
        PFPagination.slice(filteredSituations, page: currentPage)
    }

    /// True when any filter narrows the list: search text, a
    /// scheme, a difficulty, or a category other than All.
    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || schemeFilter != nil
            || levelFilter != nil
            || selectedCategory != .all
    }

    /// Clear every filter and return to the full list.
    private func clearAllFilters() {
        searchText = ""
        schemeFilter = nil
        levelFilter = nil
        selectedCategory = .all
        currentPage = 1
    }

    /// Pick a category from the drawer: filter the list, reset to
    /// the first page, and close the drawer.
    private func selectCategory(_ category: SituationCategory) {
        selectedCategory = category
        currentPage = 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isCategoryDrawerOpen = false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: PFSpacing.xl) {
                            heroCard(onSeeFreeSamples: {
                                selectCategory(.freeSamples)
                                withAnimation {
                                    proxy.scrollTo("allSituations", anchor: .top)
                                }
                            })
                            .id("situationsTop")

                            if contentService.isShowingCachedContent {
                                PFOfflineBanner()
                            }

                            if let error = contentService.indexError, contentService.searchIndex == nil {
                                PFErrorStateView(
                                    title: "Could not load the course catalogue",
                                    message: error,
                                    retryTitle: "Retry"
                                ) {
                                    Task { await contentService.loadSearchIndex() }
                                }
                            }

                            // The free samples teaser shows only in
                            // the unfiltered browse state. Showing
                            // it alongside the flat list would list
                            // the same cases twice on one screen.
                            if !hasActiveFilters {
                                freeSamplesSection
                            }

                            searchField

                            categoryButtonRow

                            filterSection

                            allSituationsSection

                            if !storeManager.isPracticeUnlocked {
                                footerCard
                            }
                        }
                        .padding(PFSpacing.lg)
                    }
                    .background(Color.pfBackground)
                    // Extra scrollable space at the bottom so the last card
                    // clears the tab bar on every iPhone size.
                    .pfTabBarClearance()
                    // Any filter change: back to the first page.
                    .onChange(of: searchText) { _, _ in currentPage = 1 }
                    .onChange(of: schemeFilter) { _, _ in currentPage = 1 }
                    .onChange(of: levelFilter) { _, _ in currentPage = 1 }
                    .onChange(of: selectedCategory) { _, _ in
                        currentPage = 1
                        withAnimation {
                            proxy.scrollTo("allSituations", anchor: .top)
                        }
                    }
                    // A page jump from the pagination bar: the
                    // list returns to its top.
                    .onChange(of: pageScrollTick) { _, _ in
                        withAnimation {
                            proxy.scrollTo("allSituations", anchor: .top)
                        }
                    }
                    .onAppear {
                        // The scroll rule: Back and tab switches land
                        // at the top, never at the restored offset.
                        // Dispatched async so the scroll lands after
                        // layout, the same form PFScrollToTopModifier
                        // uses.
                        DispatchQueue.main.async {
                            proxy.scrollTo("situationsTop", anchor: .top)
                        }
                    }
                    .onChange(of: tabReselectTick) { _, _ in
                        DispatchQueue.main.async {
                            proxy.scrollTo("situationsTop", anchor: .top)
                        }
                    }
                    .task {
                        await contentService.loadSituationsIndex()
                    }
                }
                .disabled(isCategoryDrawerOpen)

                if isCategoryDrawerOpen {
                    categoryDrawerOverlay
                }
            }
            .navigationTitle("Payment Cases")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    DrawerMenuButton(isDrawerOpen: $isDrawerOpen)
                }
                if showCloseButton {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showCheckout) {
                CheckoutView()
            }
            .task {
                await contentService.loadFullSituations()
            }
        }
    }

    // MARK: - Category drawer

    /// The button row above the filters: the current category,
    /// which opens the category drawer, and Clear all filters
    /// when any filter is active.
    private var categoryButtonRow: some View {
        HStack(spacing: PFSpacing.md) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isCategoryDrawerOpen = true
                }
            } label: {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.pfBody.weight(.semibold))
                    Text(selectedCategory.title)
                        .font(.pfBody.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.pfCaption.weight(.semibold))
                }
                .foregroundColor(.pfRoyal)
                .padding(.horizontal, PFSpacing.md)
                .padding(.vertical, PFSpacing.sm)
                .frame(minHeight: 44)
                .background(Color.pfRoyal.opacity(0.10))
                .cornerRadius(PFSpacing.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                        .stroke(Color.pfRoyal.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Browse by category, currently \(selectedCategory.title)")
            .accessibilityHint("Opens the category list.")
            Spacer()
            if hasActiveFilters {
                Button("Clear all filters") {
                    clearAllFilters()
                }
                .font(.pfCallout.weight(.semibold))
                .foregroundColor(.pfRoyal)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Clear all filters")
            }
        }
    }

    /// The side-drawer style category navigation: a dimmed
    /// background (tap to close) and a panel sliding in from the
    /// left with All cases, Free samples, and the six learning
    /// stages, each with its live count against the other
    /// filters. Stages with no matches under the other filters
    /// still list, with a zero count, so the drawer never hides
    /// a category the learner is looking for.
    private var categoryDrawerOverlay: some View {
        GeometryReader { geometry in
            let panelWidth = min(geometry.size.width * 0.85, 320)
            ZStack(alignment: .leading) {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isCategoryDrawerOpen = false
                        }
                    }
                    .accessibilityLabel("Close categories")
                    .accessibilityHint("Closes the category list.")
                    .accessibilityAddTraits(.isButton)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Categories")
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isCategoryDrawerOpen = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.pfSecondaryText)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close categories")
                    }
                    .padding(PFSpacing.lg)
                    ScrollView {
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            categoryDrawerRow(category: .all, systemImage: "square.grid.2x2.fill")
                            categoryDrawerRow(category: .freeSamples, systemImage: "gift.fill")
                            Text("Learning stages")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfSecondaryText)
                                .padding(.top, PFSpacing.md)
                                .padding(.horizontal, PFSpacing.md)
                            ForEach(1...6, id: \.self) { stage in
                                categoryDrawerRow(category: .stage(stage), systemImage: "briefcase.fill")
                            }
                        }
                        .padding(.horizontal, PFSpacing.sm)
                        .padding(.bottom, PFSpacing.lg)
                    }
                }
                .frame(width: panelWidth)
                .frame(maxHeight: .infinity)
                .background(Color.pfCard)
                .ignoresSafeArea(edges: .vertical)
                .transition(.move(edge: .leading))
            }
        }
    }

    /// One category drawer row: icon, title, live count, and a
    /// checkmark when selected, so selection is never shown by
    /// colour alone.
    private func categoryDrawerRow(category: SituationCategory, systemImage: String) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectCategory(category)
        } label: {
            HStack(spacing: PFSpacing.md) {
                Image(systemName: systemImage)
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(isSelected ? .pfRoyal : .pfSecondaryText)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(category.title)
                    .font(.pfBody.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text("\(count(for: category))")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.pfBody.weight(.bold))
                        .foregroundColor(.pfRoyal)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, PFSpacing.md)
            .padding(.vertical, PFSpacing.sm)
            .frame(minHeight: 44)
            .background(isSelected ? Color.pfRoyal.opacity(0.10) : Color.clear)
            .cornerRadius(PFSpacing.cornerRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.title), \(count(for: category)) cases" + (isSelected ? ", selected" : ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: - (a) Hero card

    private func heroCard(onSeeFreeSamples: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            HStack(spacing: PFSpacing.sm) {
                Text("Real-world cases")
                    .font(.pfCaption.weight(.bold))
                    .tracking(1)
                    .foregroundColor(.pfGold)
                Rectangle()
                    .fill(Color.pfGold)
                    .frame(width: 28, height: 2)
                    .cornerRadius(1)
            }
            Text("Payment Situations")
                .font(.pfHeroTitle)
                .foregroundColor(.white)
            Text("\(ContentManifest.situationCount) real-world situations across 6 learning stages. Try the \(ProductCatalogue.freeSampleSituationIDs.count) free samples, then unlock Practice Experiences for the full set\(storeManager.isPriceAvailable(for: ProductCatalogue.practiceProductID) ? " for \(storeManager.priceText(for: ProductCatalogue.practiceProductID))" : ""), with 1 year of access. The Integrated Course includes Practice Experiences too.")
                .font(.pfBody)
                .foregroundColor(.white.opacity(0.85))
            PFGoldButton(title: "See the free samples", action: onSeeFreeSamples)
        }
        .padding(24)
        .background(
            ZStack {
                Color.pfHeroGradient
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 200, height: 200)
                    .offset(x: 140, y: -100)
                Circle()
                    .fill(Color.pfGold.opacity(0.14))
                    .frame(width: 110, height: 110)
                    .offset(x: 120, y: 90)
            }
        )
        .cornerRadius(28)
        .shadow(color: Color.pfNavy.opacity(0.30), radius: 20, x: 0, y: 10)
    }

    // MARK: - (b) Free samples

    private var freeSamplesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(
                title: "Free samples",
                actionTitle: "See all free samples",
                action: { selectCategory(.freeSamples) }
            )
            Text("Try the free samples, no payment needed. Practice Experiences unlocks the full set.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
            if contentService.isLoadingIndex && contentService.searchIndex == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PFSpacing.lg)
            } else if freeSamples.isEmpty {
                Text("Free samples will appear here once the catalogue loads.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            } else {
                VStack(spacing: PFSpacing.sm) {
                    ForEach(freeSamples) { situation in
                        PFGuardedNavigationLink(key: situation.id, destination: { SituationDetailLoaderView(situation: situation) }) {
                            situationRow(situation, showFreePill: true)
                        }
                        .buttonStyle(PFCardButtonStyle())
                        .accessibilityIdentifier("freeSituationRow")
                    }
                }
            }
        }
        .id("freeSamples")
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: PFSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.pfBody.weight(.semibold))
                .foregroundColor(.pfSecondaryText)
            TextField("Search situations", text: searchTextBinding)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.pfBody.weight(.regular))
                        .foregroundColor(.pfSecondaryText)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(PFSpacing.md)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
    }

    // MARK: - (c) Filters

    /// One filter chip: royal filled when selected, white with a
    /// hairline border when not.
    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.pfCaptionBold)
                .foregroundColor(isSelected ? .white : .pfNavy)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.pfRoyal : Color.pfCard)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.pfRoyal : Color.pfBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + (isSelected ? ", selected" : ""))
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Filter situations")

            Text("Difficulty")
                .font(.pfCaptionBold)
                .foregroundColor(.pfNavy)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PFSpacing.sm) {
                    filterChip(title: "All", isSelected: levelFilter == nil) {
                        levelFilter = nil
                    }
                    filterChip(title: "Foundation", isSelected: levelFilter == .foundation) {
                        levelFilter = .foundation
                    }
                    filterChip(title: "Core", isSelected: levelFilter == .core) {
                        levelFilter = .core
                    }
                    filterChip(title: "Advanced", isSelected: levelFilter == .advanced) {
                        levelFilter = .advanced
                    }
                }
                .padding(.vertical, 2)
            }

            Text("Scheme")
                .font(.pfCaptionBold)
                .foregroundColor(.pfNavy)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PFSpacing.sm) {
                    filterChip(title: "All", isSelected: schemeFilter == nil) {
                        schemeFilter = nil
                    }
                    ForEach(availableSchemes, id: \.self) { schemeName in
                        filterChip(title: schemeName, isSelected: schemeFilter == schemeName) {
                            schemeFilter = schemeName
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Text("Schemes come from situation titles only. Situations whose title names no scheme appear under All.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            // The category (All cases, Free samples, or one
            // stage) lives in the category drawer, opened from
            // the category button above. Clear all filters sits
            // beside that button.
        }
    }

    // MARK: - (d) Cases list

    /// The flat case list for the selected category: the current
    /// category's title and count, the cases in catalogue order,
    /// twenty per numbered page with a "Showing A-B of N" label.
    /// Categories live in the drawer, not as accordions: the old
    /// stage groups duplicated the free samples and forced every
    /// case through an extra tap.
    private var allSituationsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: selectedCategory.title)
            Text("\(filteredSituations.count) cases")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            if contentService.isLoadingIndex && contentService.searchIndex == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PFSpacing.lg)
            } else if filteredSituations.isEmpty {
                Text("No cases match this search or these filters. Try a different search, scheme, level or category.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            } else {
                VStack(spacing: PFSpacing.sm) {
                    ForEach(visibleSituations) { situation in
                        PFGuardedNavigationLink(key: situation.id, destination: { SituationDetailLoaderView(situation: situation) }) {
                            situationRow(situation, showFreePill: situation.isFreeSample)
                        }
                        .buttonStyle(PFCardButtonStyle())
                        .accessibilityIdentifier(!situation.isFreeSample && !storeManager.isPracticeUnlocked ? "lockedSituationRow" : "situationRow")
                    }
                    if totalCasePages > 1 {
                        let bounds = PFPagination.rangeBounds(page: effectiveCasePage, totalCount: filteredSituations.count)
                        Text("Showing \(bounds.first)-\(bounds.last) of \(filteredSituations.count) cases")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PFPaginationBar(currentPage: effectiveCasePage, totalPages: totalCasePages) { page in
                            currentPage = page
                            pageScrollTick += 1
                        }
                    }
                }
            }
        }
        .id("allSituations")
    }

    /// A situation row has a distinct case-study identity, different
    /// from a lesson card: a gold leading accent, a thumbnail when
    /// the website exposes one (the briefcase tile otherwise),
    /// navy heading, and the stage and level pills. No row shows a
    /// read time.
    private func situationRow(_ situation: Situation, showFreePill: Bool) -> some View {
        HStack(alignment: .top, spacing: PFSpacing.md) {
            Rectangle()
                .fill(Color.pfGold)
                .frame(width: 4)
                .cornerRadius(2)
            if situation.thumbnail != nil {
                PFThumbnailView(thumbnailPath: situation.thumbnail, size: 56, cornerRadius: 12)
            } else {
                Image(systemName: "briefcase.fill")
                    .font(.pfCardTitle.weight(.semibold))
                    .foregroundColor(Color.pfGoldText)
                    .frame(width: 44, height: 44)
                    .background(Color.pfGoldSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text(situation.title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                PillFlow(spacing: PFSpacing.sm) {
                    PFPill(text: situation.stageName)
                    PFPill(
                        text: situation.level.displayName,
                        background: Color.pfGoldSoft,
                        foreground: Color.pfGoldText
                    )
                    if let schemeName = scheme(for: situation) {
                        PFPill(
                            text: schemeName,
                            background: Color.pfRoyal.opacity(0.10),
                            foreground: .pfRoyal
                        )
                    }
                    if showFreePill {
                        PFPill(
                            text: "Free",
                            background: Color.pfSuccess.opacity(0.12),
                            foreground: .pfSuccess
                        )
                    }
                    if !situation.isFreeSample && !storeManager.isPracticeUnlocked {
                        PFPill(
                            text: "Locked",
                            background: Color.pfGoldSoft,
                            foreground: Color.pfGoldText
                        )
                    }
                }
            }
            Spacer()
            VStack(spacing: PFSpacing.xs) {
                if bookmarkStore.isSituationBookmarked(situation.id) {
                    Image(systemName: "bookmark.fill")
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfGold)
                }
                Image(systemName: "chevron.right")
                    .font(.pfCaption.weight(.semibold))
                    .foregroundColor(.pfSecondaryText)
                    .padding(.top, PFSpacing.xs)
            }
        }
        .padding(PFSpacing.lg)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
        .shadow(color: Color.pfNavy.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    // MARK: - (e) Footer card

    private var footerCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Unlock Practice Experiences: all \(ContentManifest.situationCount) situations\(storeManager.isPriceAvailable(for: ProductCatalogue.practiceProductID) ? " for \(storeManager.priceText(for: ProductCatalogue.practiceProductID))" : "")")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text("1 year of access, by In-App Purchase. The \(ProductCatalogue.freeSampleSituationIDs.count) free samples stay free, and the weekly free case stays free. The Integrated Course includes Practice Experiences too.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                PFPrimaryButton(title: "Go to checkout") {
                    showCheckout = true
                }
            }
        }
    }
}

// MARK: - Wrapping pill layout
//
// Pills flow onto a second row instead of overflowing on a narrow screen.
// This is a plain SwiftUI Layout (iOS 16+), the same floor the rest of the
// app already needs for NavigationStack and ShareLink.
private struct PillFlow: Layout {
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

// MARK: - Situation detail
//
// The full case, in the 7-part case format: the situation, what is
// happening (the full explain text, line breaks kept), the visual
// investigation (flow, diagram or stacked, rendered natively), and
// one thing to remember. No source name or source link is shown:
// the data carries them internally, and they never appear here.
//
// D101 HARD GATE (owner-decided 13 Nov 2026): a locked situation
// shows only the teaser (case label, title, stage and level pills,
// read time) plus the checkout card as the gate, placed before any
// substantive content. The full explain, the takeaway, the visual
// and the Practice Mode entry do not render while locked. Locked
// means not a free sample, not the weekly free case on the weekly
// path, and Payment Situations not unlocked. There is no separate
// hook field in FullSituationItem or Situation, so the teaser
// carries no excerpt text at all: the opening paragraphs are part
// of the explain field and never render for a locked situation.

// MARK: - Situation detail loader

/// Loads the full detail for one case before showing it. List and
/// search rows carry index-mode situations (title, stage and level
/// only, no body text), so opening one fetches its detail chunk
/// through ContentService.situationDetail(id:), which falls back
/// to the full file when the chunk cannot be fetched. Situations
/// that already carry full text (weekly cases, loaded full data)
/// pass straight through with no fetch and no loading state.
/// Locked cases are not fetched: the gate shows from the list
/// data alone, and unlocking while the detail is open triggers
/// the load then. When the fetch fails, the loader shows an
/// error with Retry instead of an empty detail.
struct SituationDetailLoaderView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var storeManager: StoreManager
    let situation: Situation
    var isWeeklyFreeCase: Bool = false

    @State private var resolvedSituation: Situation? = nil
    @State private var loadFinished = false
    @State private var retryTick = 0

    /// The same D101 gate as SituationDetailView: locked when the
    /// situation is not a free sample, not this week's free case
    /// on the weekly path, and Practice Experiences is not
    /// unlocked. Kept in step with the detail's own gate.
    private var isLocked: Bool {
        !situation.isFreeSample && !isWeeklyFreeCase && !storeManager.isPracticeUnlocked
    }

    /// True when the body text still has to be fetched: unlocked,
    /// and the situation carries no explain text yet.
    private var needsLoad: Bool {
        !isLocked && situation.explain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if let resolvedSituation {
                SituationDetailView(situation: resolvedSituation, isWeeklyFreeCase: isWeeklyFreeCase)
            } else if needsLoad && !loadFinished {
                VStack(spacing: PFSpacing.lg) {
                    ProgressView()
                    Text("Loading the case...")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Situation")
                .navigationBarTitleDisplayMode(.inline)
            } else if needsLoad && loadFinished {
                PFErrorStateView(
                    title: "Could not load this case",
                    message: "Check your connection and try again.",
                    retryTitle: "Retry"
                ) {
                    loadFinished = false
                    retryTick += 1
                }
                .padding(PFSpacing.lg)
                .navigationTitle("Situation")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                SituationDetailView(situation: situation, isWeeklyFreeCase: isWeeklyFreeCase)
            }
        }
        .task(id: "\(isLocked)-\(retryTick)") {
            guard needsLoad, resolvedSituation == nil else { return }
            let item = await contentService.situationDetail(id: situation.id)
            guard !Task.isCancelled else { return }
            if let item {
                resolvedSituation = TrainingHub.situation(fromFull: item)
            }
            loadFinished = true
        }
    }
}

struct SituationDetailView: View {
    @EnvironmentObject private var storeManager: StoreManager
    @EnvironmentObject private var contentService: ContentService
    @ObservedObject private var bookmarkStore = PFBookmarkStore.shared
    let situation: Situation

    /// True only when this detail was opened from the weekly free
    /// case path (WeeklyCaseDetailHost). The weekly case is free
    /// by design for its week; the same situation opened from the
    /// list, search or any other path stays gated. Defaults to
    /// false, so every existing call site is unaffected except
    /// for the gate itself.
    var isWeeklyFreeCase: Bool = false

    /// D101 hard gate: locked when the situation is not a free
    /// sample, not this week's free case on the weekly path, and
    /// Practice Experiences is not unlocked. Entitlement routes
    /// through the existing StoreManager boolean only, which
    /// covers both the Practice product and the Integrated
    /// Course. No new entitlement logic lives here.
    private var isLocked: Bool {
        !situation.isFreeSample && !isWeeklyFreeCase && !storeManager.isPracticeUnlocked
    }

    @State private var showCheckout = false
    @State private var selectedDetailTab = 0

    /// All situations, full data first, search index fallback, so
    /// Practice Mode can draw its distractors from real takeaways.
    private var allSituations: [Situation] {
        if let full = contentService.fullSituations, !full.isEmpty {
            return full.map { TrainingHub.situation(fromFull: $0) }
        }
        return contentService.allSituations.map { TrainingHub.situation(from: $0) }
    }

    /// The explain text split on its real structure. See
    /// parseSituationExplain: nothing is invented, and when the text
    /// does not carry the structured format the tabs fall back to the
    /// full explain text.
    private var parsed: ParsedSituationExplain {
        parseSituationExplain(situation.explain)
    }

    /// Practice Mode entry point. The detail tabs above are untouched;
    /// this card sits below them. When the situation has a takeaway
    /// it navigates to PracticeModeView; when it has none, the card
    /// says so instead of offering a decision built from nothing.
    private var practiceModeEntry: some View {
        let eligible = PracticeModeBuilder.isEligible(situation, in: allSituations)
        return PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    PFIconTile(systemImage: "questionmark.circle.fill", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Practice Mode")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text(eligible
                            ? "Decide what you would do next, then reveal the recommended solution."
                            : "Not available for this situation: it has no takeaway to practise against.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if eligible {
                    PFGuardedNavigationLink(key: "practice-\(situation.id)", destination: { PracticeModeView(situation: situation, allSituations: allSituations) }) {
                        HStack {
                            Text("Start Practice Mode")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, PFSpacing.lg)
                        .background(Color.pfRoyal)
                        .cornerRadius(PFSpacing.cornerRadius)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start Practice Mode for this situation")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Investigation entry point, next to the Practice Mode entry
    /// in the unlocked branch only. The case is built through the
    /// engine at Professional difficulty; the experience view lets
    /// the learner pick another difficulty before starting, and the
    /// rebuild callback rebuilds through the engine for it. The
    /// full item comes from the loaded full situations data when
    /// available, else nil, following the allSituations pattern.
    private var investigationEntry: some View {
        let fullItem = contentService.fullSituations?.first { $0.id == situation.id }
        let investigation = InvestigationEngine.caseFor(situation: situation, fullItem: fullItem, difficulty: .professional)
        return PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    PFIconTile(systemImage: "magnifyingglass", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Investigate this case")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("Case \(situation.id)")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                        Text("Work this case from briefing to report: inspect the evidence, test hypotheses, make decisions, and diagnose the root cause.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PFGuardedNavigationLink(key: "investigate-\(situation.id)", destination: { InvestigationExperienceView(
                    investigation: investigation,
                    isFreeSample: situation.isFreeSample,
                    isWeeklyFreeCase: isWeeklyFreeCase,
                    onDifficultyChange: { difficulty in
                        InvestigationEngine.caseFor(situation: situation, fullItem: fullItem, difficulty: difficulty)
                    }
                ) }) {
                    HStack {
                        Text("Investigate this case")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, PFSpacing.lg)
                    .background(Color.pfRoyal)
                    .cornerRadius(PFSpacing.cornerRadius)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Investigate this case")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    PillFlow(spacing: PFSpacing.sm) {
                        PFPill(text: situation.stageName)
                        PFPill(
                            text: situation.level.displayName,
                            background: Color.pfGoldSoft,
                            foreground: Color.pfGoldText
                        )
                        if let schemeName = scheme(for: situation) {
                            PFPill(
                                text: schemeName,
                                background: Color.pfRoyal.opacity(0.10),
                                foreground: .pfRoyal
                            )
                        }
                        if situation.isFreeSample {
                            PFPill(
                                text: "Free sample",
                                background: Color.pfSuccess.opacity(0.12),
                                foreground: .pfSuccess
                            )
                        }
                        if isLocked {
                            PFPill(
                                text: "Locked",
                                background: Color.pfGoldSoft,
                                foreground: Color.pfGoldText
                            )
                        }
                    }
                    Text("Case \(situation.id)")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    HStack(alignment: .top, spacing: PFSpacing.md) {
                        if situation.thumbnail != nil {
                            PFThumbnailView(thumbnailPath: situation.thumbnail, size: 64, cornerRadius: 14)
                        }
                        Text(situation.title)
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // The agenda is discovery metadata, like the title
                // and pills: it says what the case is about, not
                // how it resolves, so it shows even for locked
                // cases. The case body stays behind the D101 gate
                // below.
                if let agenda = situation.agenda?.trimmingCharacters(in: .whitespacesAndNewlines), !agenda.isEmpty {
                    PFAgendaBlock(title: "Why work through this case", agenda: agenda)
                }

                if isLocked {
                    lockedGateView
                } else {
                    Picker("Situation detail", selection: $selectedDetailTab) {
                        Text("Overview").tag(0)
                        Text("Analysis").tag(1)
                        Text("Flow").tag(2)
                    }
                    .pickerStyle(.segmented)

                    switch selectedDetailTab {
                    case 1:
                        analysisTab
                    case 2:
                        flowTab
                    default:
                        overviewTab
                    }

                    practiceModeEntry

                    investigationEntry

                    if !situation.isFreeSample && !storeManager.isPracticeUnlocked {
                        PFCard {
                            VStack(alignment: .leading, spacing: PFSpacing.md) {
                                Text("This situation is part of Practice Experiences. Unlock all \(ContentManifest.situationCount) situations\(storeManager.isPriceAvailable(for: ProductCatalogue.practiceProductID) ? " for \(storeManager.priceText(for: ProductCatalogue.practiceProductID))" : ""), with 1 year of access. The Integrated Course includes Practice Experiences too.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                PFPrimaryButton(title: "Go to checkout") {
                                    showCheckout = true
                                }
                            }
                        }
                    }
                }
            }
            .padding(PFSpacing.lg)
            .id("situationTop")
        }
        .pfScrollToTopOnAppear("situationTop")
        // Copy protection: situation text cannot be selected, a
        // faint identity watermark sits over the content, and
        // recording blurs it out.
        .pfProtectedContent()
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("Situation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    bookmarkStore.toggleSituation(situation.id)
                } label: {
                    Image(systemName: bookmarkStore.isSituationBookmarked(situation.id) ? "bookmark.fill" : "bookmark")
                        .font(.pfCardTitle.weight(.semibold))
                        .foregroundColor(bookmarkStore.isSituationBookmarked(situation.id) ? .pfGold : .pfRoyal)
                }
                .accessibilityLabel(bookmarkStore.isSituationBookmarked(situation.id) ? "Remove bookmark" : "Bookmark this situation")
            }
        }
        .sheet(isPresented: $showCheckout) {
            CheckoutView()
        }
    }

    /// The hard gate for a locked situation (D101): the teaser
    /// header above plus this checkout card, and nothing else. No
    /// tab, no visual, no Practice Mode entry and no explain or
    /// takeaway text renders for a locked situation. The checkout
    /// card is the gate: it sits before any substantive content
    /// because there is no substantive content on this screen
    /// while locked. The copy reuses the existing upsell wording;
    /// no price or product is changed here.
    private var lockedGateView: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    PFIconTile(systemImage: "lock.fill", size: 44)
                    Text("Unlock this case")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                }
                Text("This situation is part of Practice Experiences. Unlock all \(ContentManifest.situationCount) situations\(storeManager.isPriceAvailable(for: ProductCatalogue.practiceProductID) ? " for \(storeManager.priceText(for: ProductCatalogue.practiceProductID))" : ""), with 1 year of access. The \(ProductCatalogue.freeSampleSituationIDs.count) free samples stay free. The Integrated Course includes Practice Experiences too.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFPrimaryButton(title: "Go to checkout") {
                    showCheckout = true
                }
            }
        }
        .accessibilityIdentifier("situationLockedGate")
    }

    // MARK: - Tab helpers

    /// One body-text paragraph, wrapping to the screen width.
    /// Rendered through the shared paragraph renderer, so a long
    /// field that arrives as one block (the full explain, a long
    /// takeaway) still reads as logical paragraphs, while a
    /// paragraph the parser already split renders unchanged.
    private func bodyText(_ text: String) -> some View {
        PFBodyText(text: text)
    }

    /// A labelled section inside a tab.
    private func tabSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text(title)
                .font(.pfCaptionBold)
                .foregroundColor(.pfNavy)
            content()
        }
    }

    /// The full explain text, shown when a part cannot be cleanly
    /// identified, so the case is never shortened or rewritten.
    private var fullExplainSection: some View {
        tabSection(title: "Full case text") {
            bodyText(situation.explain)
        }
    }

    // MARK: - Overview tab

    /// Business Problem (the opening paragraphs), Scenario (the
    /// "what happened" steps), and Key Learning Outcomes (the
    /// situation takeaway, as written in the data).
    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            if parsed.isParsed {
                tabSection(title: "Business Problem") {
                    ForEach(Array(parsed.opening.enumerated()), id: \.offset) { _, paragraph in
                        bodyText(paragraph)
                    }
                }
                if !parsed.flowSteps.isEmpty {
                    tabSection(title: "Scenario") {
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            ForEach(Array(parsed.flowSteps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: PFSpacing.md) {
                                    Text("\(index + 1)")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Color.pfRoyal)
                                        .clipShape(Circle())
                                    bodyText(step)
                                }
                            }
                        }
                    }
                }
                tabSection(title: "Key Learning Outcomes") {
                    bodyText(situation.takeaway)
                }
            } else {
                fullExplainSection
                tabSection(title: "Key Learning Outcomes") {
                    bodyText(situation.takeaway)
                }
            }
        }
    }

    // MARK: - Analysis tab

    /// The flawed requirement and what followed from it, then the
    /// root cause (the paragraphs after "Why?") and the insight
    /// sentence. When the text has no "Why?" paragraph, the root
    /// cause is the paragraphs between the flawed requirement and
    /// the insight sentence, as the parser already splits them.
    private var analysisTab: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            if parsed.isParsed {
                if !parsed.flawedRequirement.isEmpty {
                    tabSection(title: "The flawed requirement") {
                        ForEach(Array(parsed.flawedRequirement.enumerated()), id: \.offset) { _, paragraph in
                            bodyText(paragraph)
                        }
                    }
                }
                if !parsed.rootCause.isEmpty {
                    tabSection(title: "Root cause") {
                        ForEach(Array(parsed.rootCause.enumerated()), id: \.offset) { _, paragraph in
                            bodyText(paragraph)
                        }
                    }
                }
                if let insight = parsed.insight {
                    tabSection(title: "Insight") {
                        bodyText(insight)
                    }
                }
                if parsed.flawedRequirement.isEmpty && parsed.rootCause.isEmpty && parsed.insight == nil {
                    fullExplainSection
                }
            } else {
                fullExplainSection
            }
        }
    }

    // MARK: - Flow tab

    /// The visual (flow, diagram or stacked), rendered natively.
    /// When the situation has no visual, the "what happened" steps
    /// from the explain text render as a native numbered flow. When
    /// there are neither, the tab says so instead of showing an
    /// empty screen.
    /// The "what happened" steps from the explain text as a native
    /// flow, for situations that have no visual. Nil when the text
    /// has no steps to show.
    private var flowStepsAsFlow: SituationFlow? {
        guard !parsed.flowSteps.isEmpty else { return nil }
        let steps = parsed.flowSteps.map { step in
            SituationFlowStep(kind: "step", title: step, note: nil)
        }
        return SituationFlow(stepSeconds: nil, steps: steps)
    }

    private var flowTab: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            if let visual = situation.visual {
                situationVisualSection(visual)
            } else if let flow = flowStepsAsFlow {
                situationFlowView(flow)
            } else {
                Text("No visual is available for this situation.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Visual investigation

    @ViewBuilder
    private func situationVisualSection(_ visual: SituationVisual) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Visual investigation")
                .font(.pfCaptionBold)
                .foregroundColor(.pfNavy)
            switch visual.type {
            case "flow":
                if let flow = visual.flow {
                    situationFlowView(flow)
                }
            case "diagram":
                if let diagram = visual.diagram {
                    situationDiagramView(diagram)
                }
            case "stacked":
                if let stacked = visual.stacked {
                    situationStackedView(stacked)
                }
            default:
                EmptyView()
            }
        }
    }

    /// A flow visual: the steps in order, numbered, with an arrow
    /// between them. Decision steps get a gold diamond and a
    /// "Decision" tag so they read as a choice, not a plain step.
    private func situationFlowView(_ flow: SituationFlow) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(flow.steps.enumerated()), id: \.offset) { index, step in
                    let isDecision = (step.kind ?? "").lowercased() == "decision"
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        HStack(alignment: .top, spacing: PFSpacing.md) {
                            ZStack {
                                if isDecision {
                                    Rectangle()
                                        .fill(Color.pfGold)
                                        .frame(width: 26, height: 26)
                                        .rotationEffect(.degrees(45))
                                } else {
                                    Circle()
                                        .fill(Color.pfRoyal)
                                        .frame(width: 28, height: 28)
                                }
                                Text("\(index + 1)")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.white)
                            }
                            .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                if isDecision {
                                    Text("DECISION")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(Color.pfGoldText)
                                }
                                Text(step.title)
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let note = step.note, !note.isEmpty {
                                    Text(note)
                                        .font(.pfCallout)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if index < flow.steps.count - 1 {
                            HStack(spacing: PFSpacing.md) {
                                Image(systemName: "arrow.down")
                                    .font(.pfBody.weight(.semibold))
                                    .foregroundColor(.pfSecondaryText)
                                    .frame(width: 28)
                                Spacer()
                            }
                            .padding(.vertical, PFSpacing.xs)
                        }
                    }
                }
            }
            .padding(PFSpacing.md)
        }
    }

    /// A labelled diagram: the centre box, then its parts as cards.
    /// The centre is the main point of the situation. It is a white
    /// card like the parts, but marked in a different form: a gold
    /// border, a "MAIN POINT" tag, and a royal title, so it reads as
    /// the central idea without a dark background.
    private func situationDiagramView(_ diagram: SituationDiagram) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text("MAIN POINT")
                        .font(.pfCaptionBold)
                        .foregroundColor(Color.pfGoldText)
                    Text(diagram.centre)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfRoyal)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                    .stroke(Color.pfGold, lineWidth: 2)
            )
            ForEach(Array(diagram.parts.enumerated()), id: \.offset) { _, part in
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(part.label)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        if let note = part.note, !note.isEmpty {
                            Text(note)
                                .font(.pfCallout)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// A stacked comparison: a proportional bar with a legend below.
    private func situationStackedView(_ stacked: SituationStacked) -> some View {
        let total = stacked.segments.reduce(0) { $0 + max(0, $1.value) }
        let palette: [Color] = [.pfRoyal, .pfGold, .pfNavy, Color(red: 0.08, green: 0.50, blue: 0.24), Color(red: 0.49, green: 0.23, blue: 0.93), Color(red: 0.71, green: 0.33, blue: 0.04)]
        return VStack(alignment: .leading, spacing: PFSpacing.md) {
            if total > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(Array(stacked.segments.enumerated()), id: \.offset) { index, segment in
                            Rectangle()
                                .fill(palette[index % palette.count])
                                .frame(width: max(0, geometry.size.width * CGFloat(segment.value / total)))
                                .frame(height: 28)
                        }
                    }
                }
                .frame(height: 28)
                .cornerRadius(6)
            }
            ForEach(Array(stacked.segments.enumerated()), id: \.offset) { index, segment in
                HStack(alignment: .top, spacing: PFSpacing.sm) {
                    Rectangle()
                        .fill(palette[index % palette.count])
                        .frame(width: 14, height: 14)
                        .cornerRadius(4)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: PFSpacing.sm) {
                            Text(segment.label)
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text(formattedStackedValue(segment.value, unit: stacked.unit))
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfRoyal)
                        }
                        if let note = segment.note, !note.isEmpty {
                            Text(note)
                                .font(.pfCallout)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func formattedStackedValue(_ value: Double, unit: String?) -> String {
        let number = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
        if let unit = unit, !unit.isEmpty {
            return number + " " + unit
        }
        return number
    }
}
