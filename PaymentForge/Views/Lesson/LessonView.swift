// LessonView.swift
// PaymentForge iOS - One narrated lesson: diagram first, autoplaying
// narration, key moments synced to the audio, transcript, checklist,
// sources, quiz and the next lesson.
// Layout rules: the diagram shows first under the header; the audio card
// keeps one fixed height so loading, fallback and error lines never move
// the page; every text view wraps inside the screen width with no fixed
// container widths, so nothing clips at any edge on an iPhone SE or a
// Pro Max. The navigation bar is opaque so no text shows cut off behind
// it, and the bottom padding clears the tab bar. Text uses the design
// system sizes, which scale with the system text size.
// No em dashes in any user-facing text.

import SwiftUI
import Foundation

// MARK: - Local bookmarks (guest, no sign-in)
//
// Bookmarks live only on this device, in UserDefaults, keyed by lesson
// id and situation id. No account and no sign-in is ever required.
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
        let defaults = UserDefaults.standard
        if let ids = defaults.array(forKey: Keys.lessons) as? [String] {
            lessonIDs = Set(ids)
        }
        if let ids = defaults.array(forKey: Keys.situations) as? [String] {
            situationIDs = Set(ids)
        }
    }

    func isLessonBookmarked(_ id: String) -> Bool { lessonIDs.contains(id) }
    func isSituationBookmarked(_ id: String) -> Bool { situationIDs.contains(id) }

    func toggleLesson(_ id: String) {
        if lessonIDs.contains(id) { lessonIDs.remove(id) } else { lessonIDs.insert(id) }
        save()
    }

    func toggleSituation(_ id: String) {
        if situationIDs.contains(id) { situationIDs.remove(id) } else { situationIDs.insert(id) }
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(Array(lessonIDs), forKey: Keys.lessons)
        defaults.set(Array(situationIDs), forKey: Keys.situations)
    }
}

// MARK: - Lesson view

/// Pushed via NavigationLink from Home, Courses, Search and Situations.
struct LessonView: View {
    let entry: SearchEntry

    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var storeManager: StoreManager
    @ObservedObject private var bookmarkStore = PFBookmarkStore.shared
    @StateObject private var audioService = AudioPlayerService()

    /// Content / Transcript / Resources tab below the player.
    @State private var lessonTab = 0

    @State private var detail: LessonDetail? = nil
    @State private var isLoadingDetail = true
    @State private var loadError: String? = nil
    @State private var hasStartedAudio = false
    @State private var hasLoadedDetail = false

    /// Local checklist state, per lesson, in memory only. Keys are the
    /// item indices as strings, for example "0", "1", "2".
    @State private var checkedDoThis: Set<String> = []

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
    @State private var noteCollection = "General"
    @State private var highlightedParagraphIndex: Int? = nil

    /// Note collections offered in the composer picker.
    private let noteCollections = ["General", "Key points", "Questions", "To review"]

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

    /// The paragraph currently highlighted in the transcript, if any.
    /// Tapping a transcript paragraph highlights it and jumps the
    /// audio to it; the same text is quoted into a new note.
    private var highlightedText: String? {
        guard let index = highlightedParagraphIndex,
              transcriptParagraphs.indices.contains(index) else { return nil }
        return transcriptParagraphs[index]
    }

    /// Auto full-screen visual: when the lesson opens and the narration
    /// starts playing, the visual expands to full screen on its own.
    /// The learner closes it with the close button; it is shown once
    /// per lesson open and never re-opens after the learner closes it.
    /// The audio keeps playing in both views.
    @State private var showVisualFullScreen = false
    @State private var didAutoShowVisual = false
    @State private var visualDismissedByUser = false

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

    private var transcriptText: String {
        detail?.transcript ?? entry.text
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

    /// The beat being narrated right now, from the audio clock. The last
    /// beat stays highlighted once its end time has passed.
    private var currentBeatIndex: Int? {
        guard !beats.isEmpty else { return nil }
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

    /// Neighbours in catalogue order, from the loaded search index.
    private var catalogueIndex: Int? {
        contentService.allLessons.firstIndex { $0.id == entry.id }
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

    private var chapterIndex: Int? {
        chapterLessons.firstIndex { $0.id == entry.id }
    }

    /// Previous lesson: the previous lesson in this chapter when there
    /// is one, otherwise the previous lesson in catalogue order.
    private var previousLessonEntry: SearchEntry? {
        if let index = chapterIndex, index > 0 { return chapterLessons[index - 1] }
        guard let index = catalogueIndex, index > 0 else { return nil }
        return contentService.allLessons[index - 1]
    }

    private var catalogueNextEntry: SearchEntry? {
        guard let index = catalogueIndex, index + 1 < contentService.allLessons.count else { return nil }
        return contentService.allLessons[index + 1]
    }

    private var chapterNextEntry: SearchEntry? {
        guard let index = chapterIndex, index + 1 < chapterLessons.count else { return nil }
        return chapterLessons[index + 1]
    }

    /// Next lesson: the next lesson the lesson page names wins, then
    /// the next lesson in this chapter, then catalogue order.
    private var nextLessonEntry: SearchEntry? {
        if let nextID = detail?.nextLessonID,
           let named = contentService.allLessons.first(where: { $0.id == nextID }) {
            return named
        }
        if let next = chapterNextEntry { return next }
        return catalogueNextEntry
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
    /// no beats there is no timestamp: paragraphs never spread evenly
    /// across the audio length, because that would invent timestamps
    /// the narration does not have. Nil means the paragraph highlights
    /// on tap but does not seek.
    private func timestamp(forParagraph index: Int) -> Double? {
        guard !transcriptParagraphs.isEmpty else { return nil }
        if !beats.isEmpty {
            if index < beats.count { return beats[index].startTime }
            return beats.last?.startTime
        }
        return nil
    }

    /// Jump the audio to a transcript paragraph's timestamp and
    /// highlight that paragraph. Tapping the highlighted paragraph
    /// again clears the highlight without moving the audio.
    private func jumpToParagraph(_ index: Int) {
        if highlightedParagraphIndex == index {
            highlightedParagraphIndex = nil
            return
        }
        highlightedParagraphIndex = index
        if let time = timestamp(forParagraph: index) {
            audioService.seek(to: time)
        }
    }

    /// Detailed explanation: the first paragraphs of the transcript,
    /// kept as separate paragraphs so each reads as its own block.
    private var detailedExplanationParagraphs: [String] {
        Array(transcriptParagraphs.prefix(2))
    }

    /// Real-world example fallback: the last transcript paragraph,
    /// used only when the lesson has no "Do this at work" items.
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
                    diagramSection
                    audioSection

                    if showFinishedPrompt, let nextEntry = nextLessonEntry {
                        finishedPromptSection(entry: nextEntry)
                    }

                    if let loadError {
                        errorSection(message: loadError)
                    }

                    lessonNavSection

                    lessonTabsSection

                    quizSection

                    completionSection

                    if let nextEntry = nextLessonEntry {
                        nextLessonSection(entry: nextEntry)
                    }
                }
            }
            .padding(.horizontal, PFSpacing.lg)
            .padding(.top, PFSpacing.lg)
            // Bottom padding clears the floating tab bar so the last
            // content is never hidden behind it.
            .padding(.bottom, 112)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    noteCollection = "General"
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
            NavigationLink(
                destination: LessonView(entry: pendingNavEntry ?? entry),
                isActive: $isNavLinkActive
            ) { EmptyView() }
            .hidden()
        )
        .task {
            // Locked lessons start nothing: no progress event, no
            // audio, no detail load, no auto full-screen visual.
            // A purchase unlocks the lesson while this view is open;
            // the onChange below starts it then.
            if !isLessonLocked {
                await setupLesson()
            }
        }
        .onChange(of: isLessonLocked) { _, locked in
            if !locked {
                Task { await setupLesson() }
            }
        }
        .onDisappear {
            audioService.stop()
            // Allow autoplay again if the learner comes back to this
            // lesson: otherwise the start-once guard would leave the
            // audio stopped until Play is tapped.
            hasStartedAudio = false
            didAutoAdvance = false
        }
        .onChange(of: audioService.currentTime) { _, newValue in
            if !isScrubbing {
                seekValue = newValue
            }
        }
        .onChange(of: audioService.isPlaying) { _, newValue in
            if newValue {
                maybeAutoShowVisual()
            }
        }
        .onChange(of: selectedAnswers) { _, _ in
            // Record the score as soon as the quiz is fully answered,
            // so it persists even if the lesson is left before the
            // Mark as Complete button is tapped.
            if allQuizAnswered {
                progressStore.recordQuizScore(
                    lessonID: entry.id,
                    correct: correctCount,
                    total: quiz.count
                )
            }
        }
        .sheet(isPresented: $showNoteComposer) {
            noteComposerSheet
        }
        .fullScreenCover(isPresented: $showVisualFullScreen) {
            LessonVisualFullScreenView(
                svg: detail?.diagramSVG,
                beats: beats,
                currentBeatIndex: currentBeatIndex,
                lessonTitle: lessonTitle,
                audioService: audioService,
                onClose: closeVisualFullScreen
            )
        }
        .alert(
            "Purchase",
            isPresented: Binding(
                get: { storeManager.statusMessage != nil },
                set: { if !$0 { storeManager.clearStatusMessage() } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(storeManager.statusMessage ?? "")
        }
    }

    // MARK: - Auto full-screen visual

    /// Whether this lesson has a visual to show full screen.
    private var hasVisual: Bool {
        if let svg = detail?.diagramSVG, !svg.isEmpty { return true }
        return !beats.isEmpty
    }

    /// Show the visual full screen once, when the lesson has loaded
    /// and the narration is playing. Does nothing after the learner
    /// has closed it.
    private func maybeAutoShowVisual() {
        guard detail != nil, hasVisual, audioService.isPlaying,
              !didAutoShowVisual, !visualDismissedByUser else { return }
        didAutoShowVisual = true
        showVisualFullScreen = true
    }

    /// Close the full-screen visual and remember the choice for this
    /// lesson open, so it never pops back up on its own.
    private func closeVisualFullScreen() {
        visualDismissedByUser = true
        showVisualFullScreen = false
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
            highlightedText: highlightedText,
            collection: noteCollection
        )
        refreshHasNotes()
        showNoteComposer = false
    }

    /// Small note composer: a text field and a collection picker.
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
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Collection")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                    Picker("Collection", selection: $noteCollection) {
                        ForEach(noteCollections, id: \.self) { collection in
                            Text(collection).tag(collection)
                        }
                    }
                    .pickerStyle(.segmented)
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

            Text(lessonTitle)
                .font(.pfHeroTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: PFSpacing.sm) {
                PFPill(text: entry.type.displayName)
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
        PFCard {
            HStack(spacing: PFSpacing.md) {
                ProgressView()
                Text("Loading lesson...")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    Task { await loadDetail() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 2. Lesson diagram, first under the header

    private var diagramSection: some View {
        Group {
            if let svg = detail?.diagramSVG, !svg.isEmpty {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFSectionHeader(title: "How it flows")
                    PFCard {
                        LessonDiagramView(svg: svg, activeBeat: currentBeatIndex ?? 0)
                            .frame(height: 300)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    }
                }
            } else if !beats.isEmpty {
                beatsFlowSection
            }
        }
    }

    /// Fallback visual for lessons whose visual is not a flow SVG
    /// (for example a comparison table). The beats are the same steps
    /// the website shows, so they render here as a vertical flow with
    /// the beat matching the narration highlighted, instead of the
    /// lesson opening with no visual at all.
    private var beatsFlowSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "How it flows")
            PFCard {
                BeatsFlowContent(beats: beats, currentBeatIndex: currentBeatIndex)
            }
        }
    }

    // MARK: - 3. Audio player, one fixed height

    private var audioSection: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(alignment: .center, spacing: PFSpacing.md) {
                    Button(action: { audioService.togglePlayPause() }) {
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
                        Text("Narration plays while you read along below.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
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
                    audioControlButton(
                        icon: "gauge.with.needle",
                        label: audioService.speedLabel
                    ) {
                        audioService.cycleSpeed()
                    }
                    audioControlButton(
                        icon: "moon.zzz",
                        label: audioService.sleepTimerMinutes == nil ? "Sleep" : audioService.sleepTimerLabel
                    ) {
                        audioService.cycleSleepTimer()
                    }
                    audioControlButton(
                        icon: "goforward.15",
                        label: "Forward 15s"
                    ) {
                        audioService.seekForward()
                    }
                }

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
                    } else if AudioPlayerService.savedPosition(for: entry.id) > 5 {
                        // Saved position, playback not started yet:
                        // show where reopening resumes from.
                        Text("Resume from \(formatTimePadded(AudioPlayerService.savedPosition(for: entry.id)))")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if audioService.isUsingFallback {
                        Text("Playing from the backup audio host.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage = audioService.errorMessage {
                        Text(errorMessage)
                            .font(.pfCallout)
                            .foregroundColor(.pfError)
                            .fixedSize(horizontal: false, vertical: true)
                        PFSecondaryButton(title: "Retry audio") {
                            audioService.play(fileName: audioFileName, lessonID: entry.id)
                        }
                    }
                }
                .frame(height: 112, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One consistent player size: the card height does not change
            // when loading, fallback or error text appears.
            .frame(height: 400, alignment: .top)
        }
    }

    /// One audio control: icon above a short label, flexible width.
    private func audioControlButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
        pendingNavEntry = target
        isNavLinkActive = true
    }

    /// When the narration finishes, move to the next lesson within a
    /// second, but only when auto-play is on. When it is off, offer
    /// "Play next lesson" instead and stay on this lesson.
    private func advanceToNextLesson() {
        guard !didAutoAdvance, let next = nextLessonEntry else { return }
        didAutoAdvance = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
    /// first paragraphs of the transcript), and the real-world example.
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
        }
    }

    /// Real-world example: the "Do this at work" checklist when the
    /// lesson has one, otherwise the last paragraph of the transcript
    /// when the transcript is long enough to have one. Nothing is
    /// shown when neither exists.
    private var realWorldExampleSection: some View {
        Group {
            if !doThisItems.isEmpty {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFSectionHeader(title: "Real-World Example")
                    doThisChecklistCard
                }
            } else if let example = transcriptLastParagraph {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFSectionHeader(title: "Real-World Example")
                    PFCard {
                        Text(example)
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .lineSpacing(7)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
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

    /// Mark as Complete, shown on its own when no other Mark as
    /// Complete button is visible: a quiz that is not fully answered
    /// yet has no button in the quiz card, and a lesson with no quiz
    /// at all has its button in the practice card. In those two
    /// states this section is the button; otherwise the quiz or
    /// practice card already shows it, so this section stays empty
    /// and there is never a duplicate button on screen.
    private var completionSection: some View {
        Group {
            if !progressStore.isLessonComplete(entry.id) && !didMarkComplete
                && !quiz.isEmpty && !allQuizAnswered {
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
            Text("Tap a paragraph to jump the audio to it, when a timestamp is shown. Tap it again to clear the highlight.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        .accessibilityLabel("Jump audio to paragraph \(index + 1)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 7. Do this at work

    /// The "Do this at work" checklist as a card on its own, so the
    /// Content tab can show it under its own "Real-World Example"
    /// heading. Tapping an item toggles its checkmark; the checks are
    /// kept in memory for this lesson open only.
    private var doThisChecklistCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                ForEach(Array(doThisItems.enumerated()), id: \.offset) { index, item in
                    let key = String(index)
                    let isChecked = checkedDoThis.contains(key)
                    Button {
                        if isChecked {
                            checkedDoThis.remove(key)
                        } else {
                            checkedDoThis.insert(key)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: PFSpacing.md) {
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .font(.pfSectionTitle.weight(.regular))
                                .foregroundColor(isChecked ? .pfSuccess : .pfSecondaryText)
                                .padding(.top, 1)
                            Text(item)
                                .font(.pfBody)
                                .foregroundColor(.pfNavy)
                                .strikethrough(isChecked)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

            // The last recorded score, shown when reopening the lesson
            // before any answer is tapped in this visit.
            if let savedScore = savedQuizScore, selectedAnswers.isEmpty, !quiz.isEmpty {
                PFCard {
                    HStack(spacing: PFSpacing.sm) {
                        Image(systemName: "trophy.fill")
                            .font(.pfCardTitle.weight(.regular))
                            .foregroundColor(.pfGold)
                        Text("Last score: You scored \(savedScore) of \(quiz.count)")
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
                        markCompleteButton
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(Array(quiz.enumerated()), id: \.element.id) { index, question in
                    quizQuestionCard(question, number: index + 1)
                }

                if allQuizAnswered {
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            Text("You scored \(correctCount) of \(quiz.count)")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            markCompleteButton
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

                if let selected = selectedAnswers[question.id] {
                    let isCorrect = selected == question.correctOptionIndex
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(isCorrect ? "Correct" : "Not quite")
                            .font(.pfCaptionBold)
                            .foregroundColor(isCorrect ? .pfSuccess : .pfError)
                        Text(question.explanation)
                            .font(.pfCallout)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func quizOptionRow(question: QuizQuestion, optionIndex: Int, option: String) -> some View {
        let selected = selectedAnswers[question.id]
        let isAnswered = selected != nil
        let isSelected = selected == optionIndex
        let isCorrectOption = optionIndex == question.correctOptionIndex

        let background: Color
        if !isAnswered || !isSelected {
            background = Color.pfNavySoft
        } else if isCorrectOption {
            background = Color.pfSuccess.opacity(0.12)
        } else {
            background = Color.pfError.opacity(0.12)
        }
        let border: Color
        if !isAnswered || !isSelected {
            border = Color.pfNavy.opacity(0.10)
        } else if isCorrectOption {
            border = .pfSuccess
        } else {
            border = .pfError
        }

        return Button {
            guard selectedAnswers[question.id] == nil else { return }
            selectedAnswers[question.id] = optionIndex
        } label: {
            HStack(alignment: .top, spacing: PFSpacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.pfCardTitle.weight(.regular))
                    .foregroundColor(isSelected ? (isCorrectOption ? .pfSuccess : .pfError) : .pfSecondaryText)
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
        .disabled(isAnswered)
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
                    if quizAttempted {
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
    /// bundle containing it nor the Integrated Course is owned.
    private var isLessonLocked: Bool {
        guard let chapterID else { return false }
        return !storeManager.isChapterUnlocked(chapterID)
    }

    /// The bundle that unlocks this lesson's chapter, for the lock
    /// screen copy. Nil when the lesson is unlocked.
    private var unlockingProduct: CourseProduct? {
        guard let chapterID else { return nil }
        return storeManager.unlockingProduct(for: chapterID)
    }

    /// Shown in place of the lesson when its chapter is locked: the
    /// lesson stays listed and its title stays visible, but the
    /// narration, transcript and quiz stay locked until the bundle
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
                if let bundle = unlockingProduct {
                    Text("This lesson is part of \(bundle.name). Buy it for \(storeManager.priceText(for: bundle.productID)) to unlock this chapter, or get everything with The Integrated Course for \(storeManager.priceText(for: PaymentConfig.fullCourseProductID)).")
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    PFGoldButton(title: storeManager.isBusy ? "Please wait..." : "Buy \(bundle.name) for \(storeManager.priceText(for: bundle.productID))") {
                        Task { await storeManager.purchase(productID: bundle.productID) }
                    }
                    .disabled(storeManager.isBusy)
                    .opacity(storeManager.isBusy ? 0.5 : 1)
                } else {
                    Text("This lesson is part of a course. Buy The Integrated Course for \(storeManager.priceText(for: PaymentConfig.fullCourseProductID)) to unlock it.")
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PFSecondaryButton(title: "See all courses") {
                    showCheckout = true
                }
                Text("Pay securely with your Apple ID, or by UPI from the Purchases screen. No account needed.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showCheckout) {
            CheckoutView()
        }
    }

    // MARK: - Loading and audio

    /// The lesson-open setup: progress, audio, detail and the auto
    /// full-screen visual. Runs once when the lesson opens unlocked,
    /// or when a purchase unlocks it while this view is open. The
    /// load and audio guards inside make repeat calls safe.
    private func setupLesson() async {
        progressStore.recordLessonStarted(lessonID: entry.id, title: lessonTitle)
        // Recently opened, for the Home "Pick up where you left
        // off" list. Recorded on every open, even when the lesson
        // is already complete; Home filters completed ones out.
        RecentLessonsStore.shared.record(lessonID: entry.id)
        wireFinishHandler()
        refreshHasNotes()
        startAudioOnce()
        await loadDetail()
        // The detail carries the real chapter title: refresh the
        // lock-screen Now Playing metadata with it.
        audioService.updateLessonMetadata(title: lessonTitle, chapterTitle: chapterTitle)
        maybeAutoShowVisual()
    }

    private func loadDetail() async {
        if hasLoadedDetail { return }
        isLoadingDetail = true
        loadError = nil
        do {
            let loaded = try await contentService.loadLessonDetail(entry: entry)
            detail = loaded
            hasLoadedDetail = true
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingDetail = false
    }

    private func startAudioOnce() {
        guard !hasStartedAudio else { return }
        hasStartedAudio = true
        audioService.play(fileName: audioFileName, lessonID: entry.id, title: lessonTitle, chapterTitle: chapterTitle)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

// MARK: - Beats flow content

/// The beats of a lesson as a vertical numbered flow, with the beat
/// matching the narration highlighted in gold. Shared by the inline
/// lesson card and the full-screen visual, so both show the same steps.
struct BeatsFlowContent: View {
    let beats: [LessonBeat]
    let currentBeatIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(beats.enumerated()), id: \.element.id) { index, beat in
                HStack(alignment: .top, spacing: PFSpacing.md) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(index == currentBeatIndex ? Color.pfGold : Color.pfRoyal)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text("\(index + 1)")
                                    .font(.pfCaption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                        if index < beats.count - 1 {
                            Rectangle()
                                .fill(Color.pfRoyal.opacity(0.35))
                                .frame(width: 2, height: 22)
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, index < beats.count - 1 ? PFSpacing.sm : 0)
                }
                .padding(.vertical, 2)
                .background(index == currentBeatIndex ? Color.pfRoyal.opacity(0.06) : Color.clear)
                .cornerRadius(PFSpacing.cornerRadius)
            }
        }
        .padding(PFSpacing.md)
    }
}

// MARK: - Full-screen lesson visual

/// The lesson visual (flow diagram or beats flow) filling the whole
/// iPhone screen. The lesson opens into this automatically when the
/// narration starts; the close button returns to the normal lesson
/// view. The audio keeps playing: this view only shows the visual,
/// and the play/pause button below controls the same player.
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
                            BeatsFlowContent(beats: beats, currentBeatIndex: currentBeatIndex)
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
