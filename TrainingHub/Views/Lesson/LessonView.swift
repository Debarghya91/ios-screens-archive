// LessonView.swift
// Payments Training Hub iOS - One narrated lesson: diagram first, narration off
// by default (Play starts it), key moments synced to the audio,
// transcript, checklist, sources, quiz and the next lesson. One mode
// at a time: the diagram never auto-expands full screen, the audio
// never auto-plays, and the audio card sizes to its content instead
// of pushing the lesson text below the fold.
// Layout rules: the diagram shows first under the header; every text
// view wraps inside the screen width with no fixed container widths,
// so nothing clips at any edge on an iPhone SE or a Pro Max. The
// navigation bar is opaque so no text shows cut off behind it, and the
// bottom padding clears the tab bar. Text uses the design system sizes,
// which scale with the system text size.
// No em dashes in any user-facing text.

import SwiftUI
import Foundation

// MARK: - Local bookmarks
//
// Bookmarks live only on this device, in UserDefaults namespaced per
// account through AccountScopedStorage, keyed by lesson id and
// situation id. Bookmarks are stored locally, never synced; the
// signed-out namespace holds bookmarks saved before the sign-in
// gate, and the migration offer moves them into the account.
// One shared instance, so a bookmark set in a detail view is reflected
// in every list that shows the same item.
final class PFBookmarkStore: ObservableObject {
    static let shared = PFBookmarkStore()

    @Published private(set) var lessonIDs: Set<String> = []
    @Published private(set) var situationIDs: Set<String> = []

    private enum Keys {
        static let lessons = "pf.bookmarkedLessons.v1"
        static let situations = "pf.bookmarkedSituations.v1"
    }

    private init() {
        load()
    }

    /// Reload for the current account namespace, clearing the
    /// previous account's bookmarks first. Called by AuthService
    /// on sign-in, sign-out and account deletion.
    func reloadForCurrentAccount() {
        lessonIDs = []
        situationIDs = []
        load()
    }

    private func load() {
        AccountScopedStorage.adoptLegacyKey(Keys.lessons)
        AccountScopedStorage.adoptLegacyKey(Keys.situations)
        let defaults = UserDefaults.standard
        if let ids = defaults.array(forKey: AccountScopedStorage.currentKey(Keys.lessons)) as? [String] {
            lessonIDs = Set(ids)
        }
        if let ids = defaults.array(forKey: AccountScopedStorage.currentKey(Keys.situations)) as? [String] {
            situationIDs = Set(ids)
        }
    }

    func isLessonBookmarked(_ id: String) -> Bool { lessonIDs.contains(id) }
    func isSituationBookmarked(_ id: String) -> Bool { situationIDs.contains(id) }

    func toggleLesson(_ id: String) {
        if lessonIDs.contains(id) { lessonIDs.remove(id) } else { lessonIDs.insert(id) }
        save()
        // Lesson bookmarks sync to the account (SyncService), so a
        // change flags a sync. Situation bookmarks stay local only
        // and do not flag one.
        SyncService.shared.noteLocalChange()
    }

    func toggleSituation(_ id: String) {
        if situationIDs.contains(id) { situationIDs.remove(id) } else { situationIDs.insert(id) }
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(Array(lessonIDs), forKey: AccountScopedStorage.currentKey(Keys.lessons))
        defaults.set(Array(situationIDs), forKey: AccountScopedStorage.currentKey(Keys.situations))
    }
}

// MARK: - Lesson view

/// Opened as a sheet from every lesson tap through
/// LessonSheetRouter, and from lesson links through the
/// deep-link sheet in MainTabView. Inside the sheet, related
/// and next-lesson links push within the sheet's own
/// NavigationStack, and the audio auto-advance navigates the
/// same way.
struct LessonView: View {
    let entry: SearchEntry

    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var storeManager: StoreManager
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var bookmarkStore = PFBookmarkStore.shared
    @ObservedObject private var downloadStore = LessonDownloadStore.shared
    @StateObject private var audioService = AudioPlayerService()

    /// Binding for the sign-in sheet: shown when a Buy action
    /// found no session. Dismissing it without signing in clears
    /// the flag; signing in clears it through the entitlement
    /// sync and dismisses the sheet, returning the learner to
    /// the Buy button.
    private var signInSheetBinding: Binding<Bool> {
        Binding(
            get: { storeManager.signInRequiredForPurchase != nil && !authService.isSignedIn },
            set: { isPresented in
                if !isPresented { storeManager.clearSignInRequiredForPurchase() }
            }
        )
    }

    /// Content / Transcript / Resources tab below the player.
    @State private var lessonTab = 0
    /// True when the Content tab shows the full detailed
    /// explanation instead of its first two paragraphs.
    @State private var isExplanationExpanded = false

    @State private var detail: LessonDetail? = nil
    @State private var isLoadingDetail = true
    @State private var loadError: String? = nil
    @State private var hasStartedAudio = false
    @State private var hasLoadedDetail = false

    /// Where the loaded detail came from. Nil until a load finishes.
    /// When .cached, the banner above the lesson says the copy on
    /// this device is being shown, with a Retry for the live page.
    @State private var detailSource: LessonDetailSource? = nil

    /// The beat the learner tapped in the flow, if any. Tapping a
    /// beat seeks the audio to it and marks the row selected, so the
    /// beat note stands out. Nil until a beat is tapped.
    @State private var selectedBeatID: String? = nil

    /// Quiz answers: question id to the tapped option index.
    @State private var selectedAnswers: [String: Int] = [:]
    @State private var didMarkComplete = false

    /// Seek slider state. The slider reads audioService.currentTime and
    /// only seeks when the learner finishes dragging.
    @State private var seekValue: Double = 0
    @State private var isScrubbing = false

    /// The note composer state. The highlighted paragraph (tapped in
    /// the transcript) is quoted into the note when one is selected.
    @State private var showNoteComposer = false
    @State private var noteText = ""
    @State private var highlightedParagraphIndex: Int? = nil

    /// The full-screen lesson visual, opened from the "How it
    /// flows" section. The audio keeps playing underneath.
    @State private var showFullScreenVisual = false

    /// Whether this lesson already has notes, for the toolbar icon.
    @State private var hasNotes = false

    /// Programmatic navigation to the previous or next lesson, used by
    /// the arrow row and by auto-advance when the narration finishes.
    @State private var pendingNavEntry: SearchEntry? = nil
    @State private var isNavLinkActive = false
    @State private var didAutoAdvance = false

    /// Shown when the narration finishes and auto-advance is off:
    /// offers "Play next lesson" instead of moving on its own.
    @State private var showFinishedPrompt = false

    /// Opens the Purchases screen from the locked lesson card.
    @State private var showCheckout = false

    /// Arms the remove-download confirmation: removing the saved
    /// audio is confirmed before it happens, and the section then
    /// shows the download state again, which is the after
    /// feedback (streaming still works afterwards).
    @State private var showRemoveDownloadConfirmation = false

    /// The paragraph currently highlighted in the transcript, if any.
    /// Tapping a transcript paragraph highlights it and jumps the
    /// audio to it; the same text is quoted into a new note.
    private var highlightedText: String? {
        guard let index = highlightedParagraphIndex,
              transcriptParagraphs.indices.contains(index) else { return nil }
        return transcriptParagraphs[index]
    }

    /// True once the quiz has been submitted and scored. Answers can
    /// be changed until Submit; after Submit they are locked and the
    /// score is recorded.
    @State private var quizSubmitted = false

    /// Navigation generation: incremented on every manual navigation,
    /// so a delayed auto-advance fires only when the learner has not
    /// already moved to another lesson.
    @State private var navGeneration = 0

    /// Note shown under the transcript header, for example when a
    /// paragraph has no audio timing.
    @State private var transcriptNote: String? = nil

    init(entry: SearchEntry) {
        self.entry = entry
    }

    // MARK: - Derived values

    private var audioFileName: String {
        detail?.audioFileName ?? entry.audioFileName ?? (entry.id + ".mp3")
    }

    private var chapterTitle: String {
        detail?.chapterTitle ?? PFChapterHelper.chapterTitle(for: entry)
    }

    private var lessonTitle: String {
        detail?.title ?? entry.title
    }

    /// "Chapter 26, Lesson 3 of 8" for a regular lesson: the book
    /// chapter and lesson numbers plus the chapter's catalogue
    /// lesson count. Supplemental lessons show the chapter label
    /// only (no lesson number); held-out lessons show nothing
    /// here, the chapter name above is the context.
    private var positionCaption: String? {
        guard let number = PFChapterHelper.chapterNumber(from: entry.id),
              let book = PFBookModeReadingOrder.bookNumber(forInternalNumber: number) else { return nil }
        if entry.isSupplemental { return "Chapter \(book)" }
        let display = PFBookModeReadingOrder.displayNumber(forLessonID: entry.id)
            ?? contentService.lessonPositionInChapter(for: entry)
            ?? entry.lessonNumber
        guard let display else { return "Chapter \(book)" }
        let total = chapterLessons.filter { !$0.isSupplemental }.count
        guard total > 0 else { return "Chapter \(book), Lesson \(display)" }
        return "Chapter \(book), Lesson \(display) of \(total)"
    }

    /// "Course 3, Lesson 142 of 774 in the full course": the course number
    /// and the position among all in-course lessons in reading
    /// order. Nil for held-out lessons and lessons outside the
    /// loaded catalogue.
    private var bookPositionCaption: String? {
        guard let number = PFChapterHelper.chapterNumber(from: entry.id),
              let part = PFBookModeReadingOrder.part(forInternalNumber: number),
              let position = contentService.bookPosition(for: entry) else { return nil }
        return "Course \(part.number), Lesson \(position.position) of \(position.total) in the full course"
    }

    private var transcriptText: String {
        detail?.transcript ?? entry.text
    }

    /// True when the transcript is the shortened catalogue text
    /// (entry.text) because the full lesson detail has not loaded
    /// yet. The transcript header says so, instead of showing the
    /// short text as if it were the full transcript.
    private var isTranscriptShortened: Bool {
        detail?.transcript == nil
    }

    private var takeaways: [String] {
        Array((detail?.takeaways ?? []).prefix(5))
    }

    private var doThisItems: [String] {
        detail?.doThisAtWork ?? []
    }

    private var sources: [String] {
        detail?.sources ?? []
    }

    private var quiz: [QuizQuestion] {
        detail?.quiz ?? []
    }

    private var quizIntro: String {
        detail?.quizIntro ?? ""
    }

    private var beats: [LessonBeat] {
        detail?.beats ?? []
    }

    /// True when this lesson's beats carry no per-beat timings.
    /// Supplemental lessons have recorded narration but no timed
    /// beat data, so their beats are untimed: the flow shows every
    /// step, but nothing highlights a current beat, nothing seeks
    /// from a beat or a paragraph, and no "Now playing" badge
    /// appears. Website lessons are unaffected: their beats keep
    /// real start and end times.
    private var beatsAreUntimed: Bool {
        entry.isSupplemental
    }

    /// The "In this lesson" intro: the first real takeaway when the
    /// lesson has one, otherwise the beat titles in order. This is
    /// not called an objective: the lesson page carries no objective
    /// field, so none is invented. Nil when neither exists.
    private var inThisLessonIntro: String? {
        if let first = detail?.takeaways.first, !first.isEmpty {
            return first
        }
        guard !beats.isEmpty else { return nil }
        return beats.map { $0.title }.joined(separator: ", ")
    }

    /// Other lessons in this chapter, in catalogue order, excluding
    /// this lesson. Real titles only, from the live catalogue. Empty
    /// when the chapter is unknown or has no other lessons.
    private var relatedLessons: [SearchEntry] {
        chapterLessons.filter { $0.id != entry.id }
    }

    /// The listening length from the lesson data, shown only when
    /// the lesson carries a real duration. Hidden when the duration
    /// is 0, which includes supplemental lessons. Never a reading
    /// time: it is the narration length.
    private var listeningLengthText: String? {
        guard let duration = detail?.durationSec, duration > 0 else { return nil }
        return formatTime(duration)
    }

    /// The player status in words, so playing and paused are never
    /// shown by colour or icon shape alone.
    private var audioStatusText: String {
        if audioService.isPlaying { return "Playing" }
        if hasStartedAudio { return "Paused" }
        return "Not started yet"
    }

    /// True only once playback has actually started in this view:
    /// the learner pressed Play and a track is loaded. The beats
    /// flow "Now playing" badge is gated on this, so it never
    /// shows before the first Play tap, when the audio clock still
    /// sits at 0 on the first beat. It stays on while paused
    /// mid-playback, and goes off once the narration has finished
    /// (the same half-second end margin resume() uses).
    private var isNowPlayingBadgeVisible: Bool {
        guard hasStartedAudio, audioService.duration > 0 else { return false }
        return audioService.currentTime < audioService.duration - 0.5
    }

    /// The beat being narrated right now, from the audio clock. The last
    /// beat stays highlighted once its end time has passed. Nil for
    /// untimed beats: with all beat times at zero, the clock check
    /// below would falsely highlight the last beat, so supplemental
    /// lessons never get a current beat.
    private var currentBeatIndex: Int? {
        guard !beatsAreUntimed, !beats.isEmpty else { return nil }
        let now = audioService.currentTime
        if let index = beats.firstIndex(where: { now >= $0.startTime && now < $0.endTime }) {
            return index
        }
        if now >= (beats.last?.endTime ?? 0) {
            return beats.count - 1
        }
        return nil
    }

    /// The audio length. The player reports the real length once the item
    /// is ready; the lesson data carries it as a fallback until then.
    private var audioDuration: Double {
        if audioService.duration > 0 { return audioService.duration }
        return detail?.durationSec ?? 0
    }

    /// The honest time for this lesson, showing both formats when
    /// both exist: the listen time from the real audio length
    /// (player, then lesson data, then the bundled narration
    /// manifest) together with the read time from the full
    /// readable text (transcript, takeaways, checklist). The read
    /// time appears only once the full detail has loaded: before
    /// that the only text is the truncated catalogue excerpt, and
    /// timing it would stamp a fake read time. Lessons without
    /// narration show the read time alone; lessons with neither
    /// show nothing, never a guessed number.
    private var lessonTimeLabel: String? {
        let listenText: String? = {
            guard !audioFileName.isEmpty else { return nil }
            if audioDuration > 0 {
                return LessonDurations.durationText(Int(audioDuration))
            }
            guard let sec = LessonDurations.seconds(for: entry.id), sec > 0 else { return nil }
            return LessonDurations.durationText(sec)
        }()
        let readMinutes: Int? = {
            guard let detail else { return nil }
            let fullText = ([detail.transcript] + detail.takeaways + detail.doThisAtWork)
                .joined(separator: " ")
            return ReadTime.minutes(for: fullText)
        }()
        switch (listenText, readMinutes) {
        case let (listen?, read?):
            return "Listen about \(listen) · Read about \(read) min"
        case let (listen?, nil):
            return "About \(listen) listen"
        case let (nil, read?):
            return "About \(read) min read"
        case (nil, nil):
            return nil
        }
    }

    private var correctCount: Int {
        quiz.filter { question in
            selectedAnswers[question.id] == question.correctOptionIndex
        }.count
    }

    private var quizAttempted: Bool {
        !selectedAnswers.isEmpty
    }

    private var allQuizAnswered: Bool {
        !quiz.isEmpty && selectedAnswers.count == quiz.count
    }

    /// This lesson's index in book reading order, for prev/next
    /// navigation across chapter boundaries.
    private var readingIndex: Int? {
        contentService.readingOrderLessons.firstIndex { $0.id == entry.id }
    }

    /// The chapter prefix of this lesson id, for example "ch1" for
    /// "ch1s1". Lesson ids are "ch<chapter>s<lesson>".
    private var chapterPrefix: String? {
        guard let sIndex = entry.id.lastIndex(of: "s") else { return nil }
        let prefix = String(entry.id[..<sIndex])
        guard prefix.hasPrefix("ch"), !prefix.dropFirst(2).isEmpty else { return nil }
        return prefix
    }

    /// Lessons of this chapter, in catalogue order.
    private var chapterLessons: [SearchEntry] {
        guard let prefix = chapterPrefix else { return [] }
        return contentService.allLessons.filter { $0.id.hasPrefix(prefix + "s") }
    }

    /// Previous lesson in book reading order: the previous lesson
    /// in the chapter when there is one, otherwise the last lesson
    /// of the previous chapter in the reading map, never the
    /// numerically previous chapter.
    private var previousLessonEntry: SearchEntry? {
        guard let index = readingIndex, index > 0 else { return nil }
        return contentService.readingOrderLessons[index - 1]
    }

    /// Next lesson: the next lesson the lesson page names wins,
    /// then the next lesson in book reading order.
    private var nextLessonEntry: SearchEntry? {
        if let nextID = detail?.nextLessonID,
           let named = contentService.allLessons.first(where: { $0.id == nextID }) {
            return named
        }
        guard let index = readingIndex, index + 1 < contentService.readingOrderLessons.count else { return nil }
        return contentService.readingOrderLessons[index + 1]
    }

    private var nextLessonTitle: String {
        detail?.nextLessonTitle ?? nextLessonEntry?.title ?? ""
    }

    /// The last recorded quiz score for this lesson, if any. Scores are
    /// recorded as soon as the quiz is fully answered and persist in
    /// ProgressStore, so reopening the lesson shows the last score.
    private var savedQuizScore: Int? {
        progressStore.quizScore(for: entry.id)
    }

    /// Transcript split into paragraphs, in order.
    private var transcriptParagraphs: [String] {
        transcriptText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The audio timestamp for a transcript paragraph, in seconds.
    /// Paragraphs map to the beats in order: paragraph i starts at
    /// beat i when there is one, otherwise at the nearest beat. With
    /// no beats, or with untimed beats, there is no timestamp:
    /// paragraphs never spread evenly across the audio length, and
    /// untimed beat times (all zero) must never seek the audio to
    /// the start, because that would invent timestamps the
    /// narration does not have. Nil means the paragraph highlights
    /// on tap but does not seek.
    private func timestamp(forParagraph index: Int) -> Double? {
        guard !beatsAreUntimed, !transcriptParagraphs.isEmpty else { return nil }
        if !beats.isEmpty {
            if index < beats.count { return beats[index].startTime }
            return beats.last?.startTime
        }
        return nil
    }

    /// Jump the audio to a transcript paragraph's timestamp and
    /// highlight that paragraph. A paragraph with no timestamp cannot
    /// jump the audio, so it is not highlighted as if it were synced:
    /// a note says so instead. Tapping the highlighted paragraph
    /// again re-seeks to it, instead of silently clearing the
    /// highlight without explanation.
    private func jumpToParagraph(_ index: Int) {
        guard let time = timestamp(forParagraph: index) else {
            highlightedParagraphIndex = nil
            transcriptNote = "This paragraph has no audio timing, so it cannot jump the audio."
            return
        }
        transcriptNote = nil
        highlightedParagraphIndex = index
        audioService.seek(to: time)
    }

    /// Jump the audio to a beat's start time and mark the beat
    /// selected, so its note stands out in the flow. Playback is not
    /// started here: the Play button starts the narration, as
    /// everywhere else in this view. Seeking uses the audio
    /// service seek API, the same call the transcript uses. For
    /// untimed beats there is no jump: tapping only marks the beat
    /// selected, and never seeks the audio to the start.
    private func jumpToBeat(_ beat: LessonBeat) {
        selectedBeatID = beat.id
        guard !beatsAreUntimed else { return }
        audioService.seek(to: beat.startTime)
    }

    /// Detailed explanation: the first two paragraphs of the
    /// transcript, or the full explanation when expanded, split
    /// into readable paragraphs so each reads as its own block
    /// with breathing room, never one wall of text. The splitting
    /// never changes any wording: it only breaks long blocks at
    /// paragraph and sentence boundaries.
    private var detailedExplanationParagraphs: [String] {
        let source = isExplanationExpanded ? expandedExplanationSource : Array(transcriptParagraphs.prefix(2))
        return source.flatMap { splitIntoReadableParagraphs($0) }
    }

    /// The paragraphs the expanded explanation shows: every
    /// transcript paragraph except the last when it serves as
    /// the real-world example fallback, so the expanded text
    /// never duplicates the example section below it.
    private var expandedExplanationSource: [String] {
        if realWorldExamples.isEmpty, transcriptParagraphs.count > 2 {
            return Array(transcriptParagraphs.dropLast())
        }
        return transcriptParagraphs
    }

    /// True when the explanation has more to show than its
    /// collapsed first two paragraphs: the expand button appears
    /// only then, so it never promises content that is not there.
    private var canExpandExplanation: Bool {
        expandedExplanationSource.count > 2
    }

    /// Split a block of lesson text into readable paragraphs
    /// without changing any wording. Line breaks mark paragraph
    /// boundaries first; a long block is then split into sentence
    /// groups (at most three sentences, about 480 characters) so
    /// it never renders as one wall of text. Sentence boundaries
    /// come from the system sentence enumeration, so abbreviations
    /// and decimals do not split sentences.
    private func splitIntoReadableParagraphs(_ text: String) -> [String] {
        let blocks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var paragraphs: [String] = []
        for block in blocks {
            paragraphs.append(contentsOf: splitLongBlock(block))
        }
        return paragraphs
    }

    /// Split one long block into sentence groups. Short blocks
    /// come back unchanged.
    private func splitLongBlock(_ block: String) -> [String] {
        var sentences: [String] = []
        block.enumerateSubstrings(in: block.startIndex..<block.endIndex, options: [.bySentences]) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        guard sentences.count > 3 || block.count > 480 else { return [block] }
        guard sentences.count > 1 else { return [block] }
        var chunks: [String] = []
        var current = ""
        var currentCount = 0
        for sentence in sentences {
            if !current.isEmpty && (currentCount >= 3 || current.count + 1 + sentence.count > 480) {
                chunks.append(current)
                current = ""
                currentCount = 0
            }
            current = current.isEmpty ? sentence : current + " " + sentence
            currentCount += 1
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Real-world example fallback: the last transcript paragraph,
    /// used only when the lesson has no real-world example items.
    private var transcriptLastParagraph: String? {
        guard transcriptParagraphs.count > 2 else { return nil }
        return transcriptParagraphs.last
    }

    /// A practice prompt taken from the lesson text when there is no quiz:
    /// the first question sentence in the transcript, if there is one.
    private var practicePrompt: String {
        let sentences = transcriptText
            .components(separatedBy: ". ")
            .flatMap { $0.components(separatedBy: "\n") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let question = sentences.first(where: { $0.contains("?") }) {
            return question
        }
        return "Read the lesson text above and think of one place at work where this applies, then mark the lesson complete."
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                headerSection

                if isLessonLocked {
                    lockedLessonSection
                } else if isLoadingDetail && detail == nil {
                    loadingSection
                } else {
                    if isFreeSample {
                        freeSampleBanner
                    } else if isSequentialSample {
                        sequentialSampleBanner
                    }
                    if detailSource == .cached {
                        cachedCopyBanner
                    }
                    inThisLessonSection
                    diagramSection
                    if audioFileName.isEmpty {
                        noNarrationSection
                    } else {
                        audioSection
                    }

                    if showFinishedPrompt, let nextEntry = nextLessonEntry {
                        finishedPromptSection(entry: nextEntry)
                    }

                    if let loadError {
                        errorSection(message: loadError)
                    }

                    lessonNavSection

                    lessonTabsSection

                    quizSection

                    relatedLessonsSection

                    completionSection

                    if let nextEntry = nextLessonEntry {
                        nextLessonSection(entry: nextEntry)
                    }
                }
            }
            .padding(.horizontal, PFSpacing.lg)
            .padding(.top, PFSpacing.lg)
            // Bottom padding clears the floating tab bar so the last
            // content is never hidden behind it. The shared
            // clearance value: the same 112pt every tab list uses
            // through pfTabBarClearance(), kept as in-content
            // padding here because this ScrollView is the
            // reference pattern the shared value was taken from.
            .padding(.bottom, PFSpacing.tabBarClearance)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("lessonTop")
        }
        .pfScrollToTopOnAppear("lessonTop")
        // Floating play/pause: the audio controls live inside the
        // ScrollView and scroll away with the lesson, so this
        // button shares the same player state and stays reachable
        // while scrolled down. It shows only for unlocked lessons
        // that have narration audio.
        .overlay(alignment: .bottomTrailing) {
            floatingAudioButton
        }
        // Copy protection: lesson text cannot be selected, a faint
        // identity watermark sits over the content, and recording
        // blurs it out. The note composer sheet is outside this
        // ScrollView, so notes stay editable.
        .pfProtectedContent()
        .background(Color.pfBackground)
        .navigationTitle("Lesson")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    noteText = ""
                    showNoteComposer = true
                } label: {
                    Image(systemName: hasNotes ? "note.text" : "note.text.badge.plus")
                        .font(.pfCardTitle.weight(.semibold))
                        .foregroundColor(hasNotes ? .pfGold : .pfRoyal)
                }
                .accessibilityLabel(hasNotes ? "Add a note, this lesson already has notes" : "Add a note")
                Button {
                    bookmarkStore.toggleLesson(entry.id)
                } label: {
                    Image(systemName: bookmarkStore.isLessonBookmarked(entry.id) ? "bookmark.fill" : "bookmark")
                        .font(.pfCardTitle.weight(.semibold))
                        .foregroundColor(bookmarkStore.isLessonBookmarked(entry.id) ? .pfGold : .pfRoyal)
                }
                .accessibilityLabel(bookmarkStore.isLessonBookmarked(entry.id) ? "Remove bookmark" : "Bookmark this lesson")
            }
        }
        // Opaque navigation bar: text scrolling underneath it is hidden
        // instead of showing cut off behind the bar.
        .toolbarBackground(Color.pfBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .background(
            // The prev/next link exists only while a navigation is
            // actually requested. An always-present link to this
            // same view makes every LessonView build a nested
            // LessonView at graph-build time, which recurses and
            // kills the process before the first frame: gate runs
            // 44078305813 and 44089979766 both died within a
            // second of any lesson tap, on the chapter-row path
            // and the introduction-card path alike, with no crash
            // report. navigateToLesson sets the pending entry
            // before it flips the link active, so the link appears
            // with the right destination already in place, and the
            // pushed lesson starts with its own link inactive.
            Group {
                if isNavLinkActive {
                    NavigationLink(
                        destination: LessonView(entry: pendingNavEntry ?? entry),
                        isActive: $isNavLinkActive
                    ) { EmptyView() }
                    .hidden()
                }
            }
        )
        .sheet(isPresented: $showCheckout) {
            CheckoutView()
        }
        .sheet(isPresented: signInSheetBinding) {
            WelcomeView()
        }
        .onAppear {
            // Probe: the view appeared, so the presentation
            // completed. A tap breadcrumb with no appear
            // breadcrumb means the presentation itself stuck.
            CrashBreadcrumbs.record("lesson appear \(entry.id)")
        }
        .task {
            // Probe: the task firing proves SwiftUI ran the
            // view's work, even for a locked lesson. Recorded
            // before the lock check, so a locked lesson still
            // leaves this trace.
            CrashBreadcrumbs.record("lesson task \(entry.id)")
            // Locked lessons start nothing: no progress event, no
            // audio, no detail load, no auto full-screen visual.
            // A purchase unlocks the lesson while this view is open;
            // the onChange below starts it then.
            if !isLessonLocked {
                await setupLesson()
            }
        }
        .onChange(of: isLessonLocked) { _, locked in
            if locked {
                // The lesson locked under an open view (sign-out,
                // refund, or expiry): stop the narration at once,
                // so audio never keeps playing for locked content.
                audioService.stop()
                hasStartedAudio = false
                didAutoAdvance = false
                showFinishedPrompt = false
            } else {
                Task { await setupLesson() }
            }
        }
        .onDisappear {
            audioService.stop()
            // Nil the finish/next/previous callbacks: they capture
            // this view, and the view owns the audio service, so
            // leaving them set keeps the service alive forever.
            // setupLesson() re-wires them on the next appear.
            audioService.onFinished = nil
            audioService.onNextLesson = nil
            audioService.onPreviousLesson = nil
            // Reset the started flag so Play starts the audio fresh
            // if the learner comes back to this lesson.
            hasStartedAudio = false
            didAutoAdvance = false
        }
        .onChange(of: audioService.currentTime) { _, newValue in
            if !isScrubbing {
                seekValue = newValue
            }
        }
        .sheet(isPresented: $showNoteComposer) {
            noteComposerSheet
        }
        .fullScreenCover(isPresented: $showFullScreenVisual) {
            LessonVisualFullScreenView(
                svg: detail?.diagramSVG,
                beats: beats,
                currentBeatIndex: currentBeatIndex,
                lessonTitle: lessonTitle,
                audioService: audioService,
                onClose: { showFullScreenVisual = false }
            )
        }
        .confirmationDialog(
            "Remove this download?",
            isPresented: $showRemoveDownloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove download", role: .destructive) {
                // removeDownload(for:) is synchronous: the file is
                // removed and the state flips to notDownloaded
                // before this returns, so the section below
                // immediately shows the download state again.
                downloadStore.removeDownload(for: entry.id)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The downloaded narration is removed from this device. You can download it again any time, and streaming still works afterwards.")
        }
    }

    // MARK: - Lesson notes

    /// Refresh the filled note icon from the shared notes store.
    private func refreshHasNotes() {
        hasNotes = !NotesStore.shared.notes(for: entry.id).isEmpty
    }

    /// Save the composer note to the shared notes store, quoting the
    /// highlighted transcript paragraph when one is selected.
    private func saveNote() {
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NotesStore.shared.addNote(
            lessonID: entry.id,
            lessonTitle: lessonTitle,
            text: text,
            highlightedText: highlightedText
        )
        refreshHasNotes()
        showNoteComposer = false
    }

    /// Small note composer: a text field.
    /// The highlighted transcript paragraph, when there is one, is
    /// shown as the quote that will be saved with the note.
    private var noteComposerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                if let highlighted = highlightedText {
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Quoted from the lesson")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                        Text(highlighted)
                            .font(.pfCallout)
                            .foregroundColor(.pfSecondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(PFSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.pfGoldSoft)
                    .cornerRadius(PFSpacing.cornerRadius)
                }
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Your note")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                    TextField("Write a note about this lesson", text: $noteText, axis: .vertical)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .lineLimit(4...8)
                        .padding(PFSpacing.md)
                        .background(Color.pfCard)
                        .cornerRadius(PFSpacing.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                                .stroke(Color.pfBorder, lineWidth: 1)
                        )
                }
                PFPrimaryButton(title: "Save note") {
                    saveNote()
                }
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                Spacer()
            }
            .padding(PFSpacing.lg)
            .background(Color.pfBackground)
            .navigationTitle("Add a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showNoteComposer = false
                    }
                    .foregroundColor(.pfRoyal)
                }
            }
        }
    }

    // MARK: - 1. Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text(chapterTitle)
                .font(.pfCallout)
                .fontWeight(.semibold)
                .foregroundColor(.pfRoyal)
                .lineLimit(2)

            if let positionCaption {
                Text(positionCaption)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
            }
            if let bookPositionCaption {
                Text(bookPositionCaption)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
            }

            HStack(alignment: .top, spacing: PFSpacing.md) {
                if entry.thumbnail != nil {
                    PFThumbnailView(thumbnailPath: entry.thumbnail, size: 64, cornerRadius: 14)
                }
                Text(lessonTitle)
                    .font(.pfHeroTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let agenda = entry.agenda?.trimmingCharacters(in: .whitespacesAndNewlines), !agenda.isEmpty {
                PFAgendaBlock(title: "Why take this lesson", agenda: agenda)
            }

            HStack(spacing: PFSpacing.sm) {
                PFPill(text: entry.type.displayName)
                if let timeLabel = lessonTimeLabel {
                    Label(timeLabel, systemImage: "clock")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                }
                if progressStore.isLessonComplete(entry.id) || didMarkComplete {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSuccess)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loading and error

    private var loadingSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFLoadingView(message: "Loading lesson...")
            PFSkeletonView()
            PFSkeletonView()
        }
    }

    private func errorSection(message: String) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Label("Could not load the full lesson", systemImage: "exclamationmark.triangle.fill")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfError)
                Text(message)
                    .font(.pfCallout)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You can still read the lesson text below and listen to the audio.")
                    .font(.pfCallout)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFSecondaryButton(title: "Retry") {
                    Task { await retryLoadDetail() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shown when the lesson on screen came from the copy saved on
    /// this device because the live page could not be loaded. The
    /// cached lesson stays fully usable underneath; Retry tries the
    /// live page again.
    private var cachedCopyBanner: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.pfNavy)
                        .accessibilityHidden(true)
                    Text("Showing the copy saved on this device. The latest version could not be loaded.")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PFSecondaryButton(title: "Retry live version") {
                    Task { await retryLoadDetail() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "In this lesson": the first real takeaway, or the beat titles
    /// when there is no takeaway. Never labelled an objective, and
    /// hidden entirely when neither exists.
    private var inThisLessonSection: some View {
        Group {
            if let intro = inThisLessonIntro {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFSectionHeader(title: "In this lesson")
                    PFCard {
                        Text(intro)
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - 2. Lesson flow, first under the header

    /// The floating play/pause button: one circular gold button,
    /// bottom trailing, above the floating tab bar pill. It calls
    /// the same playButtonTapped as the audio section (first tap
    /// starts the narration, later taps toggle), and its icon
    /// follows audioService.isPlaying, so it can never disagree
    /// with the main player controls.
    private var floatingAudioButton: some View {
        Group {
            if !isLessonLocked && !audioFileName.isEmpty {
                Button(action: { playButtonTapped() }) {
                    Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.pfNavy)
                        .frame(width: 56, height: 56)
                        .background(Color.pfGold)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
                }
                .accessibilityLabel(audioService.isPlaying ? "Pause narration" : "Play narration")
                .accessibilityHint("Plays or pauses this lesson's narration.")
                .padding(.trailing, PFSpacing.lg)
                .padding(.bottom, 100)
            }
        }
    }

    /// The lesson visual for every lesson: the beats as a native
    /// vertical flow. The website's flow-diagram SVG is never
    /// shown in the app: rendered in a narrow WebView it came
    /// out tiny and unreadable, while the native flow reads
    /// clearly. Flow lessons get arrows between the points.
    /// Supplemental lessons render this same section from their
    /// bundled flow descriptor, with untimed beats: every step
    /// shows, with no current-beat highlight and no seeking.
    private var diagramSection: some View {
        Group {
            if !beats.isEmpty {
                beatsFlowSection
            }
        }
    }

    /// True when the lesson has a flow diagram: website lessons
    /// carry the flow-diagram SVG from the lesson page, and
    /// supplemental flow lessons carry a diagram generated from
    /// their flow descriptor. Those lessons get arrows between the
    /// flow points, showing the direction of the flow. Other
    /// lessons get a plain rail.
    private var hasFlowDiagram: Bool {
        detail?.diagramSVG?.isEmpty == false
    }

    /// The beats as a vertical flow, with the beat matching the
    /// narration highlighted. No numbers: the beats are the
    /// lesson's points, not a sequence. For untimed beats there is
    /// no highlight and no "Now playing" badge: currentBeatIndex
    /// is nil, so every point renders at rest.
    private var beatsFlowSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "How it flows")
            PFCard {
                BeatsFlowContent(
                    beats: beats,
                    currentBeatIndex: currentBeatIndex,
                    showsFlowArrows: hasFlowDiagram,
                    showsNowPlayingBadge: isNowPlayingBadgeVisible,
                    selectedBeatID: selectedBeatID,
                    isUntimed: beatsAreUntimed,
                    onBeatTapped: { beat in jumpToBeat(beat) }
                )
            }
            Button {
                showFullScreenVisual = true
            } label: {
                Label("View full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfRoyal)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View the lesson visual full screen")
            .accessibilityHint("Opens the flow visual filling the whole screen. Audio keeps playing.")
        }
    }

    /// Shown in place of the audio player for a lesson with no
    /// audio file: the full text below is the lesson, the player
    /// never appears and never fails.
    private var noNarrationSection: some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: "text.book.closed.fill", size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text("No narration")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text("This lesson has no recorded narration. Read the full text below.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 3. Audio player (sizes to its content)

    private var audioSection: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(alignment: .center, spacing: PFSpacing.md) {
                    Button(action: { playButtonTapped() }) {
                        Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.pfSectionTitle.weight(.bold))
                            .foregroundColor(.white)
                            .padding(18)
                            .background(Color.pfRoyal)
                            .clipShape(Circle())
                            .accessibilityLabel(audioService.isPlaying ? "Pause" : "Play")
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Listen to this lesson")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("Tap play to start the narration, then read along below.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let listeningLength = listeningLengthText {
                            Text("Listening length: \(listeningLength)")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfSecondaryText)
                        }
                        Text(audioStatusText)
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                        if audioService.isLoading && audioService.duration == 0 {
                            ProgressView()
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: PFSpacing.xs) {
                    Slider(
                        value: Binding(
                            get: { isScrubbing ? seekValue : audioService.currentTime },
                            set: { seekValue = $0 }
                        ),
                        in: 0...max(audioDuration, 1),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing {
                                audioService.seek(to: seekValue)
                            }
                        }
                    )
                    .tint(.pfRoyal)
                    .disabled(audioDuration <= 0)
                    .accessibilityLabel("Audio position")
                    .accessibilityValue("\(formatTime(isScrubbing ? seekValue : audioService.currentTime)) of \(formatTime(audioDuration))")

                    HStack {
                        Text(formatTime(isScrubbing ? seekValue : audioService.currentTime))
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .monospacedDigit()
                        Spacer()
                        Text(formatTime(audioDuration))
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .monospacedDigit()
                    }
                }

                // Controls row: five equal flexible buttons, so the row
                // fits a small iPhone SE width without clipping. No button
                // has a fixed width, each takes an equal share of the row.
                // The player bar matches the mockup: 15s skip both ways,
                // volume, speed ("1.0x") and a sleep timer.
                HStack(spacing: 0) {
                    audioControlButton(
                        icon: "gobackward.15",
                        label: "Back 15s"
                    ) {
                        audioService.seekBackward()
                    }
                    audioControlButton(
                        icon: audioService.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: audioService.isMuted ? "Unmute" : "Mute"
                    ) {
                        audioService.toggleMute()
                    }
                    Menu {
                        ForEach(AudioPlayerService.playbackSpeeds, id: \.self) { speed in
                            Button(Self.speedLabel(for: speed)) {
                                audioService.setSpeed(speed)
                            }
                        }
                    } label: {
                        audioControlLabel(icon: "gauge.with.needle", label: audioService.speedLabel)
                    }
                    .accessibilityLabel("Playback speed, \(audioService.speedLabel)")
                    Menu {
                        Button("Off") {
                            audioService.setSleepTimer(minutes: nil)
                        }
                        ForEach(AudioPlayerService.sleepTimerOptions, id: \.self) { minutes in
                            Button("\(minutes) minutes") {
                                audioService.setSleepTimer(minutes: minutes)
                            }
                        }
                    } label: {
                        audioControlLabel(icon: "moon.zzz", label: audioService.sleepTimerMinutes == nil ? "Sleep" : audioService.sleepTimerLabel)
                    }
                    .accessibilityLabel("Sleep timer, \(audioService.sleepTimerMinutes == nil ? "Off" : audioService.sleepTimerLabel)")
                    audioControlButton(
                        icon: "goforward.15",
                        label: "Forward 15s"
                    ) {
                        audioService.seekForward()
                    }
                }

                downloadSection

                // Playback queue: auto-advance is off by default. When
                // it is on, the next lesson starts on its own when this
                // one finishes; when it is off, a "Play next lesson"
                // card is offered instead.
                Toggle(isOn: Binding(
                    get: { audioService.autoAdvanceEnabled },
                    set: { audioService.setAutoAdvance($0) }
                )) {
                    Text("Auto-play next lesson")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                }
                .tint(.pfRoyal)

                // Reserved status space: resumed, fallback and error
                // lines always have this room, so the card never
                // changes height when one of them appears.
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    if let resumed = audioService.resumedFromPosition, resumed > 0 {
                        Text("Resumed from \(formatTimePadded(resumed))")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if AudioPlayerService.savedPosition(for: entry.id) > 0 {
                        // Saved position, playback not started yet:
                        // show where reopening resumes from.
                        Text("Resume from \(formatTimePadded(AudioPlayerService.savedPosition(for: entry.id)))")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if audioService.isUsingFallback {
                        Text("The main audio was unavailable, so this lesson is playing from the backup copy. The content is the same.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if audioService.isPlayingDownloadedCopy {
                        Text("Playing the downloaded copy saved on this device.")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if audioService.errorMessage != nil {
                        Text("The audio could not be played. Check your connection and tap Retry audio.")
                            .font(.pfCallout)
                            .foregroundColor(.pfError)
                            .fixedSize(horizontal: false, vertical: true)
                        PFSecondaryButton(title: "Retry audio") {
                            audioService.play(fileName: audioFileName, lessonID: entry.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Explicit offline download for this lesson's narration. This
    /// control only exists in the unlocked lesson view, under the
    /// same gating as playback, so a locked lesson can never be
    /// downloaded from here. Nothing downloads automatically: the
    /// download starts only on the learner's tap, and it does not
    /// continue if the app is closed before it finishes.
    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            switch downloadStore.state(for: entry.id) {
            case .notDownloaded:
                Text("Listen offline by downloading the narration to this device.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFSecondaryButton(title: "Download audio") {
                    Task { await downloadStore.downloadAudio(for: entry) }
                }
            case .downloading:
                HStack(spacing: PFSpacing.sm) {
                    ProgressView()
                    Text("Downloading audio...")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .downloaded:
                Label("Downloaded to this device", systemImage: "arrow.down.circle.fill")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                Text("Playing this lesson uses the downloaded copy. Remove it to free space; streaming still works afterwards.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFSecondaryButton(title: "Remove download") {
                    showRemoveDownloadConfirmation = true
                }
            case .failed(let message):
                Text(message)
                    .font(.pfCallout)
                    .foregroundColor(.pfError)
                    .fixedSize(horizontal: false, vertical: true)
                PFSecondaryButton(title: "Try download again") {
                    Task { await downloadStore.downloadAudio(for: entry) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One audio control label: icon above a short label, flexible
    /// width. Shared by the tap buttons and the Speed and Sleep menus,
    /// so every control looks the same.
    private func audioControlLabel(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.pfCardTitle.weight(.regular))
                .foregroundColor(.pfRoyal)
            Text(label)
                .font(.pfCaption.weight(.semibold))
                .foregroundColor(.pfNavy)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }

    /// One audio control: icon above a short label, flexible width.
    private func audioControlButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            audioControlLabel(icon: icon, label: label)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// "1.0x" style label for one playback speed, matching the
    /// player's speedLabel for the current rate.
    private static func speedLabel(for rate: Float) -> String {
        switch rate {
        case 0.75: return "0.75x"
        case 1.25: return "1.25x"
        case 1.5: return "1.5x"
        case 2.0: return "2.0x"
        default: return "1.0x"
        }
    }

    /// Zero-padded MM:SS, for the "Resumed from 08:43" line.
    private func formatTimePadded(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - 4. Previous and next lesson arrows

    private var lessonNavSection: some View {
        HStack(spacing: PFSpacing.md) {
            lessonNavButton(
                direction: .previous,
                entry: previousLessonEntry,
                label: "Previous"
            )
            Spacer()
            lessonNavButton(
                direction: .next,
                entry: nextLessonEntry,
                label: "Next"
            )
        }
    }

    private enum NavDirection {
        case previous
        case next
    }

    /// Previous / Next button: a royal circle arrow, the direction
    /// label, and the target lesson title (two lines max). When there
    /// is no lesson in that direction the button is greyed out and
    /// disabled, and the title reads "No previous lesson" or
    /// "No next lesson".
    private func lessonNavButton(
        direction: NavDirection,
        entry target: SearchEntry?,
        label: String
    ) -> some View {
        let isEnabled = target != nil
        let circle = Image(systemName: direction == .previous ? "chevron.left" : "chevron.right")
            .font(.pfSectionTitle.weight(.bold))
            .foregroundColor(.white)
            .frame(width: 56, height: 56)
            .background(isEnabled ? Color.pfRoyal : Color.pfSecondaryText.opacity(0.4))
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 2)
        let text = VStack(alignment: direction == .previous ? .leading : .trailing, spacing: 2) {
            Text(label)
                .font(.pfCardTitle)
                .foregroundColor(isEnabled ? .pfNavy : .pfSecondaryText)
            Text(target?.title ?? "No \(label.lowercased()) lesson")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .lineLimit(2)
                .multilineTextAlignment(direction == .previous ? .leading : .trailing)
        }
        .frame(maxWidth: 140, alignment: direction == .previous ? .leading : .trailing)
        return Button {
            if let target {
                navigateToLesson(target)
            }
        } label: {
            if direction == .previous {
                HStack(spacing: PFSpacing.sm) { circle; text }
            } else {
                HStack(spacing: PFSpacing.sm) { text; circle }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label + (target.map { " lesson: " + $0.title } ?? " lesson, none available"))
    }

    /// Push the given lesson. Used by the arrow row and by auto-advance.
    private func navigateToLesson(_ target: SearchEntry) {
        guard target.id != entry.id, !isNavLinkActive else { return }
        navGeneration += 1
        pendingNavEntry = target
        isNavLinkActive = true
    }

    /// When the narration finishes, move to the next lesson within a
    /// second, but only when auto-play is on. When it is off, offer
    /// "Play next lesson" instead and stay on this lesson.
    private func advanceToNextLesson() {
        guard !didAutoAdvance, let next = nextLessonEntry else { return }
        didAutoAdvance = true
        // Capture the generation: if the learner manually navigated
        // to another lesson in the half second before this fires,
        // the generation has moved on and this delayed navigation
        // is dropped instead of pushing a second copy of the lesson.
        let generation = navGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard self.navGeneration == generation else { return }
            self.navigateToLesson(next)
        }
    }

    /// Offer the next lesson when narration finishes with auto-play
    /// off. Nothing happens when there is no next lesson.
    private func handleAudioFinished() {
        showFinishedPrompt = false
        if audioService.autoAdvanceEnabled {
            advanceToNextLesson()
        } else if nextLessonEntry != nil {
            showFinishedPrompt = true
        }
    }

    /// The "lesson finished" card: Play next lesson, or stay here.
    private func finishedPromptSection(entry nextEntry: SearchEntry) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Lesson finished")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Up next: \(nextEntry.title)")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: PFSpacing.md) {
                    PFPrimaryButton(title: "Play next lesson") {
                        showFinishedPrompt = false
                        navigateToLesson(nextEntry)
                    }
                    Button("Stay here") {
                        showFinishedPrompt = false
                    }
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfRoyal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.pfRoyal.opacity(0.08))
                    .cornerRadius(PFSpacing.cornerRadius)
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func wireFinishHandler() {
        audioService.onFinished = {
            self.handleAudioFinished()
        }
        // Headphone, lock-screen and car next/previous commands move
        // to the neighbouring lesson. A nil neighbour leaves the
        // command reporting failure, so it never fires on nothing.
        // Same capture pattern as onFinished above: the view struct
        // is captured by value, matching the existing handler.
        audioService.onNextLesson = {
            guard let next = self.nextLessonEntry else { return }
            self.navigateToLesson(next)
        }
        audioService.onPreviousLesson = {
            guard let previous = self.previousLessonEntry else { return }
            self.navigateToLesson(previous)
        }
    }

    // MARK: - Content / Transcript / Resources tabs

    private var lessonTabsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Picker("Lesson content", selection: $lessonTab) {
                Text("Content").tag(0)
                Text("Transcript").tag(1)
                Text("Resources").tag(2)
            }
            .pickerStyle(.segmented)

            switch lessonTab {
            case 1:
                transcriptSection
            case 2:
                resourcesTabSection
            default:
                contentTabSection
            }
        }
    }

    /// Content tab: key takeaways, the detailed explanation (the
    /// first two paragraphs of the transcript, expandable to the
    /// full explanation), and the real-world example.
    private var contentTabSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.xl) {
            if !takeaways.isEmpty {
                takeawaysSection
            }
            detailedExplanationSection
            realWorldExampleSection
        }
    }

    private var detailedExplanationSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Detailed explanation")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    ForEach(Array(detailedExplanationParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .lineSpacing(7)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if canExpandExplanation {
                PFSecondaryButton(title: isExplanationExpanded ? "Show less" : "Show the full explanation") {
                    withAnimation {
                        isExplanationExpanded.toggle()
                    }
                }
            }
        }
    }

    /// Real-world example: reading content, not tasks. Each
    /// example renders as its own card with no checkbox, no
    /// strikethrough and no tap action. When the lesson has no
    /// example items, the last paragraph of the transcript is
    /// shown instead, split into readable paragraphs, when the
    /// transcript is long enough to have one. Nothing is shown
    /// when neither exists.
    private var realWorldExampleSection: some View {
        Group {
            if !realWorldExamples.isEmpty {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFSectionHeader(title: "Real-World Example")
                    realWorldExampleCards
                }
            } else if let example = transcriptLastParagraph {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFSectionHeader(title: "Real-World Example")
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.lg) {
                            ForEach(Array(splitIntoReadableParagraphs(example).enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .lineSpacing(7)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// The example items in source order, with repeats removed:
    /// exact duplicates, and any item whose text already appears
    /// inside an earlier item, are dropped, so no example text
    /// repeats. Items are plain strings in the lesson data, with
    /// no separate title or body field, so each item is shown
    /// whole, in the order the lesson lists it.
    private var realWorldExamples: [String] {
        var unique: [String] = []
        for item in doThisItems {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !unique.contains(trimmed) else { continue }
            guard !unique.contains(where: { $0.contains(trimmed) }) else { continue }
            unique.append(trimmed)
        }
        return unique
    }

    /// Resources tab: the lesson sources, and the lesson's key points.
    private var resourcesTabSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.xl) {
            if !sources.isEmpty {
                sourcesSection
            } else {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFSectionHeader(title: "Sources")
                    PFCard {
                        Text("No sources are listed for this lesson.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !takeaways.isEmpty {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFSectionHeader(title: "Key points")
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            ForEach(Array(takeaways.enumerated()), id: \.offset) { _, takeaway in
                                HStack(alignment: .top, spacing: PFSpacing.md) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.pfCardTitle.weight(.regular))
                                        .foregroundColor(.pfGold)
                                        .padding(.top, 2)
                                    Text(takeaway)
                                        .font(.pfBody)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// Mark as Complete, always in this one place, in the same
    /// position whether or not the lesson has a quiz and whether or
    /// not the quiz is answered. The quiz card and the practice card
    /// never show their own button, so there is exactly one button
    /// on screen and it never moves.
    private var completionSection: some View {
        Group {
            if !progressStore.isLessonComplete(entry.id) && !didMarkComplete {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("Finished listening and reading? Mark the lesson complete to track your progress.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        markCompleteButton
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 5. Key takeaways

    private var takeawaysSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Key takeaways")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    ForEach(Array(takeaways.enumerated()), id: \.offset) { _, takeaway in
                        HStack(alignment: .top, spacing: PFSpacing.md) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.pfCardTitle.weight(.regular))
                                .foregroundColor(.pfGold)
                                .padding(.top, 2)
                            Text(takeaway)
                                .font(.pfBody)
                                .foregroundColor(.pfNavy)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 6. Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Full lesson text")
            Text("Tap a paragraph to jump the audio to it. Paragraphs without a timestamp cannot jump the audio.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isTranscriptShortened && !transcriptParagraphs.isEmpty {
                Text("Shortened version: the full transcript is still loading.")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfRoyal)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let transcriptNote {
                Text(transcriptNote)
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfRoyal)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    ForEach(Array(transcriptParagraphs.enumerated()), id: \.offset) { index, paragraph in
                        let isHighlighted = highlightedParagraphIndex == index
                        Button {
                            jumpToParagraph(index)
                        } label: {
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                if let time = timestamp(forParagraph: index) {
                                    HStack(spacing: PFSpacing.xs) {
                                        Image(systemName: "play.circle.fill")
                                            .font(.pfCaption.weight(.regular))
                                            .foregroundColor(.pfRoyal)
                                        Text(formatTime(time))
                                            .font(.pfCaptionBold)
                                            .foregroundColor(.pfRoyal)
                                            .monospacedDigit()
                                    }
                                }
                                Text(paragraph)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .lineSpacing(4)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(PFSpacing.sm)
                            .background(isHighlighted ? Color.pfGoldSoft : Color.clear)
                            .cornerRadius(PFSpacing.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                                    .stroke(isHighlighted ? Color.pfGold : Color.clear, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(timestamp(forParagraph: index) == nil ? "Paragraph \(index + 1), no audio timing" : "Jump audio to paragraph \(index + 1)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 7. Real-world example

    /// One reading card per real-world example. No checkbox, no
    /// strikethrough, no tap action: examples are read, not done.
    private var realWorldExampleCards: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            ForEach(Array(realWorldExamples.enumerated()), id: \.offset) { _, example in
                PFCard {
                    PFBodyText(text: example, lineSpacing: 7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 8. Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Sources")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                        Text(source)
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 9. Quiz

    private var quizSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Check your understanding")

            if !quizIntro.isEmpty {
                PFCard {
                    Text(quizIntro)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // The best recorded score, shown when reopening the lesson.
            // Previous answers are restored below, so the learner sees
            // what they answered last time.
            if let savedScore = savedQuizScore, !quiz.isEmpty {
                PFCard {
                    HStack(spacing: PFSpacing.sm) {
                        Image(systemName: "trophy.fill")
                            .font(.pfCardTitle.weight(.regular))
                            .foregroundColor(.pfGold)
                        Text("Best score: You scored \(savedScore) of \(quiz.count)")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if quiz.isEmpty {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text(practicePrompt)
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(Array(quiz.enumerated()), id: \.element.id) { index, question in
                    quizQuestionCard(question, number: index + 1)
                }

                // Submit: the score is recorded only when the learner
                // taps Submit, never the moment the last answer is
                // tapped. Answers can be changed until then.
                if allQuizAnswered && !quizSubmitted {
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            Text("All questions answered. Submit to see your score.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            PFPrimaryButton(title: "Submit answers") {
                                progressStore.recordQuizScore(
                                    lessonID: entry.id,
                                    correct: correctCount,
                                    total: quiz.count
                                )
                                quizSubmitted = true
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // After Submit: the score, and a Retake that clears
                // the answers so the quiz can be taken again. The
                // recorded score history stays; the best score stands.
                if quizSubmitted {
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            Text("You scored \(correctCount) of \(quiz.count)")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            PFSecondaryButton(title: "Retake quiz") {
                                progressStore.clearQuizAnswers(lessonID: entry.id)
                                selectedAnswers = [:]
                                quizSubmitted = false
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func quizQuestionCard(_ question: QuizQuestion, number: Int) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Q\(number). " + question.question)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: PFSpacing.sm) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                        quizOptionRow(question: question, optionIndex: optionIndex, option: option)
                    }
                }

                if quizSubmitted, let selected = selectedAnswers[question.id] {
                    let isCorrect = selected == question.correctOptionIndex
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(isCorrect ? "Correct" : "Not quite")
                            .font(.pfCaptionBold)
                            .foregroundColor(isCorrect ? .pfSuccess : .pfError)
                        PFBodyText(text: question.explanation, font: .pfCallout, textColor: .pfSecondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func quizOptionRow(question: QuizQuestion, optionIndex: Int, option: String) -> some View {
        let selected = selectedAnswers[question.id]
        let isSelected = selected == optionIndex
        let isCorrectOption = optionIndex == question.correctOptionIndex
        // Correct/incorrect colours show only after Submit. Before
        // that, the selected option is simply highlighted, and the
        // learner can change it.
        let background: Color
        if !isSelected {
            background = Color.pfNavySoft
        } else if quizSubmitted && isCorrectOption {
            background = Color.pfSuccess.opacity(0.12)
        } else if quizSubmitted {
            background = Color.pfError.opacity(0.12)
        } else {
            background = Color.pfRoyal.opacity(0.12)
        }
        let border: Color
        if !isSelected {
            border = Color.pfNavy.opacity(0.10)
        } else if quizSubmitted && isCorrectOption {
            border = .pfSuccess
        } else if quizSubmitted {
            border = .pfError
        } else {
            border = .pfRoyal
        }

        return Button {
            guard !quizSubmitted else { return }
            selectedAnswers[question.id] = optionIndex
            progressStore.saveQuizAnswer(lessonID: entry.id, questionID: question.id, optionIndex: optionIndex)
        } label: {
            HStack(alignment: .top, spacing: PFSpacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.pfCardTitle.weight(.regular))
                    .foregroundColor(isSelected ? (quizSubmitted ? (isCorrectOption ? .pfSuccess : .pfError) : .pfRoyal) : .pfSecondaryText)
                    .padding(.top, 1)
                Text(option)
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PFSpacing.md)
            .background(background)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(quizSubmitted)
    }

    private var markCompleteButton: some View {
        Group {
            if progressStore.isLessonComplete(entry.id) || didMarkComplete {
                Label("Lesson complete", systemImage: "checkmark.circle.fill")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfSuccess)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PFPrimaryButton(title: "Mark lesson complete") {
                    progressStore.markLessonComplete(id: entry.id, title: lessonTitle)
                    // Record the score here only when the quiz was
                    // answered but never submitted: Submit already
                    // recorded it, and recording twice would duplicate
                    // the attempt in history.
                    if quizAttempted && !quizSubmitted {
                        progressStore.recordQuizScore(
                            lessonID: entry.id,
                            correct: correctCount,
                            total: quiz.count
                        )
                    }
                    didMarkComplete = true
                }
            }
        }
    }

    // MARK: - Related lessons

    /// More lessons in this chapter, below the quiz. Real titles
    /// from the live catalogue, each opening that lesson. Hidden
    /// when this chapter has no other lessons. A locked sibling
    /// opens into the same locked lesson state as everywhere else;
    /// no gating is changed here.
    private var relatedLessonsSection: some View {
        Group {
            if !relatedLessons.isEmpty {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFSectionHeader(title: "More in this chapter")
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            ForEach(relatedLessons) { lesson in
                                NavigationLink(destination: LessonView(entry: lesson)) {
                                    HStack(spacing: PFSpacing.md) {
                                        if lesson.thumbnail != nil {
                                            PFThumbnailView(thumbnailPath: lesson.thumbnail, size: 36, cornerRadius: 8)
                                        }
                                        Text(lesson.title)
                                            .font(.pfBody)
                                            .foregroundColor(.pfNavy)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right")
                                            .font(.pfBody.weight(.semibold))
                                            .foregroundColor(.pfRoyal)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open lesson: \(lesson.title)")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - 10. Next lesson

    private func nextLessonSection(entry nextEntry: SearchEntry) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Next lesson")
            NavigationLink(destination: LessonView(entry: nextEntry)) {
                HStack(spacing: PFSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nextLessonTitle.isEmpty ? nextEntry.title : nextLessonTitle)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Continue to the next lesson")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfRoyal)
                }
                .padding(PFSpacing.lg)
                .background(Color.pfCard)
                .cornerRadius(PFSpacing.cardRadius)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Locked lesson

    /// The chapter this lesson belongs to, for example "ch5".
    /// Nil when the lesson id carries no chapter number; such a
    /// lesson is never locked.
    private var chapterID: String? {
        guard let number = PFChapterHelper.chapterNumber(from: entry.id) else { return nil }
        return "ch\(number)"
    }

    /// True when this lesson's chapter is not unlocked: neither the
    /// part containing it nor the Integrated Course is owned. A
    /// free lesson (the first lesson of each chapter, or one of
    /// the part's 2 sequential samples) is never locked: it opens
    /// with full content, no purchase.
    private var isLessonLocked: Bool {
        guard let chapterID else { return false }
        if PFChapterHelper.isFreeLesson(entry, in: contentService) { return false }
        return !storeManager.isChapterUnlocked(chapterID)
    }

    /// True when this lesson is the free sample of its chapter and
    /// the chapter itself is locked, so the banner can say so.
    private var isFreeSample: Bool {
        guard let chapterID else { return false }
        return PFChapterHelper.isSampleLesson(entry, in: contentService)
            && !storeManager.isChapterUnlocked(chapterID)
    }

    /// True when this lesson is one of its part's sequential free
    /// samples (but not the chapter's first lesson, which the
    /// free-sample banner covers) and the chapter itself is
    /// locked, so the sequential banner can say so.
    private var isSequentialSample: Bool {
        guard let chapterID else { return false }
        return !PFChapterHelper.isSampleLesson(entry, in: contentService)
            && PFChapterHelper.isSequentialSampleLesson(entry)
            && !storeManager.isChapterUnlocked(chapterID)
    }

    /// The 0-based position of this lesson within its part's
    /// sequential samples, or nil when it is not one of them.
    /// Position 1 is the second (last) free sample: the buy
    /// prompt goes with it.
    private var sequentialSampleIndex: Int? {
        FreeSampleRules.sequentialSampleIndex(forLessonID: entry.id)
    }

    /// The part that unlocks this lesson's chapter, for the lock
    /// screen copy. Nil when the lesson is unlocked.
    private var unlockingProduct: CourseProduct? {
        guard let chapterID else { return nil }
        return storeManager.unlockingProduct(for: chapterID)
    }

    /// Shown at the top of a free sample lesson in a locked chapter:
    /// this lesson is free and complete, the rest of the chapter is
    /// not. One line, so the lesson itself stays the focus.
    private var freeSampleBanner: some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: "gift.fill", size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text("Free sample lesson")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text("This lesson is free, with the full content. The rest of this chapter unlocks with the course.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Shown at the top of a sequential free sample lesson in a
    /// locked chapter: the first sample says it is free, and the
    /// second (last) sample carries the buy prompt for the course.
    private var sequentialSampleBanner: some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: "gift.fill", size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(sequentialSampleIndex == 1 ? "Last free sample in this course" : "Free sample lesson")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    if sequentialSampleIndex == 1, let part = unlockingProduct {
                        Text("This is the second of 2 free samples from \(part.name). Unlock the course\(storeManager.isPriceAvailable(for: part.productID) ? " for \(storeManager.priceText(for: part.productID))" : "") to keep reading, with 1 year of access.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        PFSecondaryButton(title: "See purchase options") {
                            showCheckout = true
                        }
                    } else {
                        Text("This lesson is free, with the full content. The rest of this course unlocks when you buy it.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Shown in place of the lesson when its chapter is locked: the
    /// lesson stays listed and its title stays visible, but the
    /// narration, transcript and quiz stay locked until the course
    /// or the Integrated Course is bought. Buying from here unlocks
    /// the lesson in place.
    private var lockedLessonSection: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "lock.fill", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Locked lesson")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("Buy the course to unlock this chapter.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let part = unlockingProduct {
                    Text("This lesson is part of \(part.name). Buy it for \(storeManager.priceText(for: part.productID)) to unlock this chapter for 1 year, or unlock all chapters with The Integrated Course for \(storeManager.priceText(for: StoreManager.fullCourseProductID)).")
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    PFGoldButton(title: storeManager.isBusy ? "Please wait..." : "Buy \(part.name) for \(storeManager.priceText(for: part.productID))") {
                        // Clear any stale launch-time store message;
                        // the result shows in the single purchase
                        // alert owned by the tab view.
                        storeManager.clearStatusMessage()
                        Task { await storeManager.purchase(productID: part.productID) }
                    }
                    .disabled(storeManager.isBusy)
                    .opacity(storeManager.isBusy ? 0.5 : 1)
                } else {
                    Text("This lesson is part of the course. Buy The Integrated Course for \(storeManager.priceText(for: StoreManager.fullCourseProductID)) to unlock it for 1 year.")
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PFSecondaryButton(title: "See purchase options") {
                    showCheckout = true
                }
                Text(StoreManager.buildPhaseBuyOpensContent ? "For now, Buy opens the course on this device. No payment is taken." : "Sign in first, then pay securely with your Apple ID.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Loading and audio

    /// The lesson-open setup: progress, audio, detail and the auto
    /// full-screen visual. Runs once when the lesson opens unlocked,
    /// or when a purchase unlocks it while this view is open. The
    /// load and audio guards inside make repeat calls safe.
    private func setupLesson() async {
        CrashBreadcrumbs.record("lesson open \(entry.id)")
        progressStore.recordLessonStarted(lessonID: entry.id, title: lessonTitle)
        // Recently opened, for the Home "Pick up where you left
        // off" list. Recorded on every open, even when the lesson
        // is already complete; Home filters completed ones out.
        RecentLessonsStore.shared.record(lessonID: entry.id)
        wireFinishHandler()
        refreshHasNotes()
        // Narration is off by default: nothing auto-plays. The Play
        // button in the audio card starts it when the learner taps it.
        await loadDetail()
        // Previous quiz answers, so reopening the lesson shows them.
        selectedAnswers = progressStore.savedQuizAnswers(for: entry.id)
        quizSubmitted = savedQuizScore != nil && !quiz.isEmpty && selectedAnswers.count == quiz.count
        // The detail carries the real chapter title: refresh the
        // lock-screen Now Playing metadata with it.
        audioService.updateLessonMetadata(title: lessonTitle, chapterTitle: chapterTitle)
    }

    private func loadDetail() async {
        if hasLoadedDetail { return }
        isLoadingDetail = true
        loadError = nil
        detailSource = nil
        if let loaded = await contentService.loadLessonDetailWithSource(entry: entry) {
            detail = loaded.detail
            detailSource = loaded.source
            CrashBreadcrumbs.record("lesson detail loaded \(entry.id)")
            // The full detail replaces the summary paragraphs: a
            // highlight left over from the summary could point at
            // the wrong paragraph in the full text.
            highlightedParagraphIndex = nil
            hasLoadedDetail = true
        } else {
            loadError = "This lesson could not be loaded. Check your connection and tap Retry."
        }
        isLoadingDetail = false
    }

    /// Retry the lesson load from scratch, including after a cached
    /// copy was shown. Clears the loaded guard so the live page is
    /// tried again; a failed retry falls back to the cached copy
    /// when one exists, and the banner stays honest about it.
    private func retryLoadDetail() async {
        hasLoadedDetail = false
        detailSource = nil
        await loadDetail()
    }

    /// Start the narration when the learner taps Play. The first tap
    /// loads the audio; later taps pause and resume it.
    private func playButtonTapped() {
        if !hasStartedAudio {
            hasStartedAudio = true
            audioService.play(fileName: audioFileName, lessonID: entry.id, title: lessonTitle, chapterTitle: chapterTitle)
        } else {
            audioService.togglePlayPause()
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

// MARK: - Beats flow content

/// The beats of a lesson as a vertical flow, with the beat
/// matching the narration highlighted in gold. The "Now playing"
/// badge shows only when showsNowPlayingBadge is true, so it
/// never appears before playback has actually started. The markers are
/// plain dots, not numbers: the beats are the lesson's points,
/// not a sequence. Flow lessons get arrows between the points,
/// showing the direction of the flow; other lessons get a
/// plain rail. Shared by the inline lesson card and the
/// full-screen visual, so both show the same steps. In the lesson
/// view the rows are tappable: tapping a beat seeks the audio to
/// it. Each row exposes its title and note as its accessibility
/// label, and the flow exposes a point count summary. When the
/// beats are untimed (supplemental lessons), tapping a row marks
/// the point as selected instead of jumping the audio, and the
/// accessibility hint says so.
struct BeatsFlowContent: View {
    let beats: [LessonBeat]
    let currentBeatIndex: Int?
    let showsFlowArrows: Bool
    let showsNowPlayingBadge: Bool
    let selectedBeatID: String?
    /// True when the beats carry no per-beat timings. Rows then
    /// select rather than seek, and no row claims to jump audio.
    let isUntimed: Bool
    let onBeatTapped: ((LessonBeat) -> Void)?

    init(
        beats: [LessonBeat],
        currentBeatIndex: Int?,
        showsFlowArrows: Bool,
        showsNowPlayingBadge: Bool = false,
        selectedBeatID: String? = nil,
        isUntimed: Bool = false,
        onBeatTapped: ((LessonBeat) -> Void)? = nil
    ) {
        self.beats = beats
        self.currentBeatIndex = currentBeatIndex
        self.showsFlowArrows = showsFlowArrows
        self.showsNowPlayingBadge = showsNowPlayingBadge
        self.selectedBeatID = selectedBeatID
        self.isUntimed = isUntimed
        self.onBeatTapped = onBeatTapped
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(beats.enumerated()), id: \.element.id) { index, beat in
                beatRow(beat: beat, index: index)
            }
        }
        .padding(PFSpacing.md)
        .accessibilityLabel("Lesson flow, \(beats.count) points")
    }

    /// One beat row. When onBeatTapped is set, the row is a button
    /// that seeks the audio to the beat, or only marks the beat
    /// selected when the beats are untimed; otherwise it is plain
    /// content, as in the dormant full-screen visual. The dot and
    /// arrow visuals are unchanged. The current and selected beats
    /// are marked with text and icon shape as well as colour, never
    /// colour alone. The highlight change is instant, with no
    /// animation, so there is nothing for Reduce Motion to gate.
    @ViewBuilder
    private func beatRow(beat: LessonBeat, index: Int) -> some View {
        let isCurrent = index == currentBeatIndex
        let isSelected = beat.id == selectedBeatID
        // The badge follows real playback only: the current beat is
        // still marked by dot and background before playback, but
        // the "Now playing" badge and spoken label appear only when
        // playback has actually started.
        let showsBadge = isCurrent && showsNowPlayingBadge
        let label = beatAccessibilityLabel(for: beat, isNowPlaying: showsBadge, isSelected: isSelected)
        let content = HStack(alignment: .top, spacing: PFSpacing.md) {
            VStack(spacing: 0) {
                Circle()
                    .fill(isCurrent ? Color.pfGold : Color.pfRoyal)
                    .frame(width: 14, height: 14)
                    .padding(.top, 4)
                if index < beats.count - 1 {
                    if showsFlowArrows {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.pfRoyal.opacity(0.6))
                            .frame(height: 22)
                    } else {
                        Rectangle()
                            .fill(Color.pfRoyal.opacity(0.35))
                            .frame(width: 2, height: 22)
                    }
                }
            }
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                Text(beat.title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                if !beat.note.isEmpty {
                    Text(beat.note)
                        .font(.pfCallout)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsBadge {
                    Label("Now playing", systemImage: "speaker.wave.2.fill")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                }
                if isSelected {
                    Label("Selected point", systemImage: "checkmark.circle.fill")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, index < beats.count - 1 ? PFSpacing.sm : 0)
        }
        .padding(.vertical, 2)
        .frame(minHeight: 44, alignment: .top)
        .background(isCurrent ? Color.pfRoyal.opacity(0.06) : Color.clear)
        .cornerRadius(PFSpacing.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                .stroke(isSelected ? Color.pfGold : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        if let onBeatTapped {
            Button(action: { onBeatTapped(beat) }) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityHint(isUntimed ? "Marks this point as selected" : "Jumps the audio to this point")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
        }
    }

    /// The spoken label for one beat: its title and note, plus
    /// "Now playing" and "Selected" when they apply.
    private func beatAccessibilityLabel(for beat: LessonBeat, isNowPlaying: Bool, isSelected: Bool) -> String {
        var parts = [beat.title]
        if !beat.note.isEmpty { parts.append(beat.note) }
        if isNowPlaying { parts.append("Now playing") }
        if isSelected { parts.append("Selected") }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Full-screen lesson visual

/// The lesson visual (flow diagram or beats flow) filling the whole
/// iPhone screen. Opened from the "How it flows" section of the
/// lesson view. The audio keeps playing: this view only shows
/// the visual, and the play/pause button below controls the same player.
struct LessonVisualFullScreenView: View {
    let svg: String?
    let beats: [LessonBeat]
    let currentBeatIndex: Int?
    let lessonTitle: String
    @ObservedObject var audioService: AudioPlayerService
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.pfNavy.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: PFSpacing.md) {
                    Text(lessonTitle)
                        .font(.pfCardTitle)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel("Close full screen")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("How it flows")
                            .font(.pfSectionTitle)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let svg, !svg.isEmpty {
                            LessonDiagramView(svg: svg, activeBeat: currentBeatIndex ?? 0)
                                .frame(maxWidth: .infinity)
                                .padding(PFSpacing.lg)
                                .background(Color.white)
                                .cornerRadius(PFSpacing.cardRadius)
                        } else if !beats.isEmpty {
                            BeatsFlowContent(beats: beats, currentBeatIndex: currentBeatIndex, showsFlowArrows: svg?.isEmpty == false, showsNowPlayingBadge: audioService.isPlaying)
                                .background(Color.white)
                                .cornerRadius(PFSpacing.cardRadius)
                        } else {
                            Text("No visual is available for this lesson yet.")
                                .font(.pfBody)
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, PFSpacing.lg)
                }
                // Copy protection on the diagram too: watermark over
                // the visual, blur while recording. The close button
                // and audio controls sit outside this ScrollView, so
                // they stay usable while recording is on.
                .pfProtectedContent()

                HStack(spacing: PFSpacing.md) {
                    Button(action: { audioService.togglePlayPause() }) {
                        Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.pfNavy)
                            .frame(width: 44, height: 44)
                            .background(Color.pfGold)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(audioService.isPlaying ? "Pause" : "Play")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioService.isPlaying ? "Listening" : "Paused")
                            .font(.pfCaptionBold)
                            .foregroundColor(.white)
                        Text("\(formatTime(audioService.currentTime)) / \(formatTime(audioService.duration))")
                            .font(.pfCaption)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    Spacer()
                    Text("Tap the X to return to the lesson")
                        .font(.pfCaption)
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.08))
            }
        }
        .onDisappear {
            // Catches a dismissal that did not come from the close
            // button, so the visual never pops back up on its own.
            onClose()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
