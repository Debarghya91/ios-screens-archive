// ISO20022ExplorerView.swift
// Payments Training Hub iOS - Native ISO 20022 message explorer.
// Teaches message structure from the ISO 20022 base schema only.
// Scheme usage guides decide what is mandatory in a live payment;
// this explorer states no scheme rules. All sample values are
// fictional. Related lessons come from the live search index, never
// invented. The Explorer is FREE for everyone: it has no product,
// is never paywalled, and must never gain a purchase gate.
// No em dashes in any user-facing text.

import SwiftUI

// MARK: - Shared copy

/// Copy shared by every explorer screen, kept in one place so the
/// disclaimers can never drift apart between screens.
enum ISO20022ExplorerCopy {
    /// The permanent disclaimer, shown on the explorer, on every
    /// message detail, on the journey and on the mapping workbench.
    static let schemeDisclaimer = "Base schema only. Mandatory and optional in this explorer follow the ISO 20022 base schema. Scheme usage guides, for example CBPR+ or SEPA, decide what is actually mandatory in a live payment. This explorer teaches message structure, not scheme rules."
    static let fictionalValuesNote = "All names, identifiers, amounts and references in samples are fictional and for teaching only."
    static let abbreviatedSampleNote = "Abbreviated sample. Parts omitted. The namespace declaration and non-essential blocks are omitted."
}

// MARK: - Explorer

/// The ISO 20022 message explorer: the ten covered messages grouped
/// by family, plus the follow-the-payment journey and the mapping
/// workbench. Carries no NavigationStack of its own: the host stack
/// provides navigation when pushed, and the drawer sheet wraps it
/// in a stack with a Done button, the PracticeSheetView pattern.
///
/// Pass initialMessageID to open one message directly, for example
/// from a lesson or a search result. The code is matched
/// case-insensitively; an unknown code simply shows the list.
struct ISO20022ExplorerView: View {
    @EnvironmentObject private var contentService: ContentService

    /// The selected family, kept in scene storage so the filter
    /// survives process death and relaunch. Stored as the raw
    /// family string; an empty string means all families.
    @SceneStorage("iso20022.selectedFamily") private var selectedFamilyRaw: String = ""
    private var selectedFamily: ISO20022Family? {
        get { ISO20022Family(rawValue: selectedFamilyRaw) }
        nonmutating set { selectedFamilyRaw = newValue?.rawValue ?? "" }
    }
    @State private var initialDetailActive = false
    @State private var didOpenInitialMessage = false

    private let initialMessage: ISO20022Message?

    init(initialMessageID: String? = nil) {
        if let initialMessageID {
            self.initialMessage = ISO20022Catalogue.message(id: initialMessageID)
        } else {
            self.initialMessage = nil
        }
    }

    private var familiesToShow: [ISO20022Family] {
        if let selectedFamily { return [selectedFamily] }
        return ISO20022Family.allCases
    }

    private func messages(for family: ISO20022Family) -> [ISO20022Message] {
        ISO20022Catalogue.messages.filter { $0.family == family }
    }

    var body: some View {
        ZStack {
                Color.pfBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: PFSpacing.lg) {
                        introCard
                        ISO20022DisclaimerCard()
                        if contentService.isShowingCachedContent {
                            PFOfflineBanner()
                        }
                        journeyLink
                        mappingLink
                        familyFilter
                        ForEach(familiesToShow, id: \.self) { family in
                            familySection(family)
                        }
                    }
                    .padding(PFSpacing.lg)
                    .id("explorerTop")
                }
                .pfScrollToTopOnAppear("explorerTop", resetWhen: selectedFamily?.rawValue ?? "")
            }
            .pfTabBarClearance()
            .navigationTitle("ISO 20022 Explorer")
            .navigationBarTitleDisplayMode(.inline)
            .background {
                if let initialMessage {
                    NavigationLink(
                        destination: ISO20022MessageDetailView(message: initialMessage),
                        isActive: $initialDetailActive
                    ) { EmptyView() }
                    .hidden()
                }
            }
            .onAppear {
                if initialMessage != nil && !didOpenInitialMessage {
                    didOpenInitialMessage = true
                    initialDetailActive = true
                }
            }
            .task {
                await contentService.loadSearchIndex()
            }
    }

    // MARK: - Intro

    private var introCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("How payments are written")
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                Text("Explore \(ISO20022Catalogue.messages.count) ISO 20022 messages. Open a message to read its purpose, study an abbreviated sample and expand every element to see what it means, an example value and how it is used.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Related lessons come from the live catalogue of \(ContentManifest.lessonCount) lessons across \(ContentManifest.chapterCount) chapters.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Journey and mapping links

    private var journeyLink: some View {
        NavigationLink(destination: ISO20022JourneyView()) {
            PFCard {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "map.fill", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Follow the payment")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("pain.001 to pacs.008 to pacs.002, with the same fictional values throughout.")
                            .font(.pfCallout)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.pfSecondaryText)
                        .pfDecorative()
                }
            }
        }
        .buttonStyle(PFCardButtonStyle())
    }

    private var mappingLink: some View {
        NavigationLink(destination: ISO20022MappingView()) {
            PFCard {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "tablecells.fill", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Mapping workbench")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("How core fields map from pain.001 to pacs.008 to pacs.002. Illustrative only.")
                            .font(.pfCallout)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.pfSecondaryText)
                        .pfDecorative()
                }
            }
        }
        .buttonStyle(PFCardButtonStyle())
    }

    // MARK: - Family filter

    private var familyFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PFSpacing.sm) {
                PFChip(text: "All messages", isSelected: selectedFamily == nil) {
                    selectedFamily = nil
                }
                ForEach(ISO20022Family.allCases, id: \.self) { family in
                    PFChip(text: family.displayName, isSelected: selectedFamily == family) {
                        selectedFamily = family
                    }
                }
            }
            .padding(.vertical, PFSpacing.xs)
        }
        .accessibilityLabel("Filter messages by family")
    }

    // MARK: - Family sections

    private func familySection(_ family: ISO20022Family) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFSectionHeader(title: family.displayName)
            PFBodyText(text: family.description, font: .pfCallout, textColor: .pfSecondaryText)
            ForEach(messages(for: family)) { message in
                messageRow(message)
            }
        }
    }

    private func messageRow(_ message: ISO20022Message) -> some View {
        NavigationLink(destination: ISO20022MessageDetailView(message: message)) {
            PFCard {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: message.family.systemImage, size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(message.id)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text(message.displayName)
                            .font(.pfCallout)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Root element: \(message.rootElement)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.pfSecondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.pfSecondaryText)
                        .pfDecorative()
                }
            }
        }
        .buttonStyle(PFCardButtonStyle())
        .accessibilityLabel("Open \(message.id), \(message.displayName)")
    }
}

// MARK: - Disclaimer card

/// The permanent scheme disclaimer, shown on every explorer screen
/// so the base-schema framing is never more than a glance away.
struct ISO20022DisclaimerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Label("Base schema only", systemImage: "info.circle.fill")
                .font(.pfCardTitle)
                .foregroundColor(.pfNavy)
            Text(ISO20022ExplorerCopy.schemeDisclaimer)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PFSpacing.lg)
        .background(Color.pfGoldSoft)
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfGold.opacity(0.5), lineWidth: 1)
        )
    }
}

// MARK: - Sample XML card

/// An abbreviated sample in monospace, horizontally scrollable, with
/// the abbreviated and fictional labels always attached to it.
struct ISO20022SampleXMLCard: View {
    let sampleXML: String

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.sm) {
                    Text("Sample XML")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Spacer()
                    PFPill(
                        text: "Fictional values",
                        background: Color.pfGoldSoft,
                        foreground: Color.pfGoldText
                    )
                }
                Text(ISO20022ExplorerCopy.abbreviatedSampleNote)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ISO20022ExplorerCopy.fictionalValuesNote)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(sampleXML)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.pfNavy)
                        .textSelection(.enabled)
                        .padding(PFSpacing.md)
                }
                .background(Color.pfNavySoft)
                .cornerRadius(PFSpacing.smallRadius)
            }
        }
    }
}

// MARK: - Message detail

/// The detail screen for one message: purpose, relationships,
/// abbreviated sample, the expandable field tree, common structural
/// problems and related lessons from the live search index.
struct ISO20022MessageDetailView: View {
    let message: ISO20022Message

    @EnvironmentObject private var contentService: ContentService
    @State private var expandedFieldIDs: Set<String> = []

    /// Every field id in the tree, for Expand all.
    private var allFieldIDs: Set<String> {
        var ids: Set<String> = []
        func collect(_ fields: [ISO20022Field]) {
            for field in fields {
                ids.insert(field.id)
                collect(field.children)
            }
        }
        collect(message.fields)
        return ids
    }

    var body: some View {
        ZStack {
            Color.pfBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    headerCard
                    ISO20022DisclaimerCard()
                    purposeSection
                    relationshipsSection
                    ISO20022SampleXMLCard(sampleXML: message.sampleXML)
                    structureSection
                    validationSection
                    ISO20022RelatedLessonsSection(message: message)
                }
                .padding(PFSpacing.lg)
                .id("messageDetailTop")
            }
            .pfScrollToTopOnAppear("messageDetailTop")
        }
        .pfTabBarClearance()
        .navigationTitle(message.id)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await contentService.loadSearchIndex()
        }
    }

    // MARK: - Header and purpose

    private var headerCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text(message.id)
                    .font(.pfScreenTitle)
                    .foregroundColor(.pfNavy)
                Text(message.displayName)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("ISO name: \(message.isoName)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.pfSecondaryText)
                Text("Root element: \(message.rootElement)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.pfSecondaryText)
                PFPill(text: message.family.displayName)
            }
        }
    }

    private var purposeSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFSectionHeader(title: "Purpose")
            PFCard {
                PFBodyText(text: message.purpose)
            }
        }
    }

    // MARK: - Relationships

    private var relationshipsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFSectionHeader(title: "How it connects")
            ForEach(message.relationships) { relationship in
                relationshipRow(relationship)
            }
        }
    }

    private func relationshipRow(_ relationship: ISO20022Relationship) -> some View {
        Group {
            if let related = ISO20022Catalogue.message(id: relationship.relatedMessageID) {
                NavigationLink(destination: ISO20022MessageDetailView(message: related)) {
                    relationshipContent(relationship)
                }
                .buttonStyle(PFCardButtonStyle())
                .accessibilityLabel("Open \(related.id), \(related.displayName)")
            } else {
                relationshipContent(relationship)
            }
        }
    }

    private func relationshipContent(_ relationship: ISO20022Relationship) -> some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: relationship.kind)
                        Text(relationship.relatedMessageID)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                    }
                    Text(relationship.note)
                        .font(.pfCallout)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
                    .pfDecorative()
            }
        }
    }

    // MARK: - Structure tree

    private var structureSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFSectionHeader(title: "Explore the structure")
            Text("Tap an element to expand it and read its definition, an example value and a usage note. Mandatory means required by the base schema when the parent block is present. Optional means the base schema allows the message without it.")
                .font(.pfCallout)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: PFSpacing.lg) {
                Button("Expand all") {
                    expandedFieldIDs = allFieldIDs
                }
                .pfMinimumTouchTarget()
                Button("Collapse all") {
                    expandedFieldIDs = []
                }
                .pfMinimumTouchTarget()
            }
            .font(.pfCallout)
            .fontWeight(.semibold)
            .foregroundColor(.pfRoyal)
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    ForEach(message.fields) { field in
                        ISO20022FieldRow(
                            field: field,
                            depth: 0,
                            expandedIDs: $expandedFieldIDs
                        )
                    }
                }
            }
        }
    }

    // MARK: - Validation problems

    private var validationSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFSectionHeader(title: "Common structural problems")
            Text("General educational examples only. Whether a live payment is accepted also depends on the scheme usage guide and the receiving bank, which this explorer does not cover.")
                .font(.pfCallout)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    ForEach(ISO20022ValidationProblem.commonProblems) { problem in
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text(problem.title)
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            PFBodyText(text: problem.explanation, textColor: .pfSecondaryText)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Field row

/// One expandable row of the field tree. Tapping toggles the detail:
/// definition, base-schema requirement, example value and usage
/// note, then the child elements indented below. The requirement is
/// shown as text, never by colour alone, and the control carries an
/// accessibility label stating its expanded state.
struct ISO20022FieldRow: View {
    let field: ISO20022Field
    let depth: Int
    @Binding var expandedIDs: Set<String>

    private var isExpanded: Bool { expandedIDs.contains(field.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Button {
                if isExpanded {
                    expandedIDs.remove(field.id)
                } else {
                    expandedIDs.insert(field.id)
                }
            } label: {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.pfCallout)
                        .fontWeight(.semibold)
                        .foregroundColor(.pfRoyal)
                        .pfDecorative()
                    Text(field.element)
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.pfNavy)
                    Spacer()
                    requirementPill
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") element \(field.element)")
            .accessibilityHint("Shows the definition, example value and usage note.")
            if isExpanded {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    PFBodyText(text: field.definition)
                    Text(field.requirement.label)
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    if let exampleValue = field.exampleValue {
                        Text("Example (fictional): ")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                        + Text(exampleValue)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundColor(.pfNavy)
                    }
                    Text("Usage: ")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    + Text(field.usageNote)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                    ForEach(field.children) { child in
                        ISO20022FieldRow(
                            field: child,
                            depth: depth + 1,
                            expandedIDs: $expandedIDs
                        )
                    }
                }
                .padding(.leading, PFSpacing.lg)
            }
        }
        .padding(.leading, CGFloat(depth) * PFSpacing.md)
    }

    private var requirementPill: some View {
        PFPill(
            text: field.requirement.shortLabel,
            background: field.requirement == .mandatory
                ? Color.pfRoyal.opacity(0.10)
                : Color.pfNavy.opacity(0.08),
            foreground: field.requirement == .mandatory ? .pfRoyal : .pfNavy
        )
    }
}

// MARK: - Related lessons

/// Lessons from the live search index whose title or catalogue text
/// mentions the message code. Only real loaded entries are ever
/// shown; when none matches, the section says so honestly instead
/// of inventing a link. Rows open LessonView exactly as Home and
/// Search do. A lesson that is the free sample for its chapter
/// carries a Free sample pill; gating itself is handled by
/// LessonView and is never restated here.
struct ISO20022RelatedLessonsSection: View {
    let message: ISO20022Message

    @EnvironmentObject private var contentService: ContentService

    /// How many matching lessons are shown before the count note.
    private static let maxShown = 5

    private var relatedLessons: [SearchEntry] {
        let code = message.id.lowercased()
        return contentService.allLessons.filter { entry in
            entry.title.lowercased().contains(code)
                || entry.text.lowercased().contains(code)
        }
    }

    var body: some View {
        // Computed once per body evaluation: the filter scans the
        // catalogue with two lowercased string matches per entry,
        // and the branches below used to run it three times.
        let related = relatedLessons
        return VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFSectionHeader(title: "Related lessons")
            Text("Lessons whose title or catalogue text mentions \(message.id).")
                .font(.pfCallout)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if contentService.searchIndex == nil {
                if let error = contentService.indexError {
                    PFErrorStateView(
                        title: "Could not load the course catalogue",
                        message: error,
                        retryTitle: "Retry"
                    ) {
                        Task { await contentService.loadSearchIndex() }
                    }
                } else {
                    PFLoadingView(message: "Loading the course catalogue...")
                }
            } else if related.isEmpty {
                PFCard {
                    Text("No lesson in the loaded catalogue mentions \(message.id) in its title or text. The catalogue may still teach this message under a different name, so try searching for the message name.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if contentService.isShowingCachedContent {
                    PFOfflineBanner()
                }
                ForEach(Array(related.prefix(Self.maxShown))) { entry in
                    lessonRow(entry)
                }
                if related.count > Self.maxShown {
                    Text("Showing \(Self.maxShown) of \(related.count) matching lessons. Search the catalogue for the full list.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func lessonRow(_ entry: SearchEntry) -> some View {
        NavigationLink(destination: LessonView(entry: entry)) {
            PFCard {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "play.fill", size: 40)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(entry.title)
                            .font(.pfCallout)
                            .fontWeight(.semibold)
                            .foregroundColor(.pfNavy)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subtitle = subtitle(for: entry) {
                            Text(subtitle)
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                        }
                        if PFChapterHelper.isSampleLesson(entry, in: contentService) {
                            PFPill(
                                text: "Free sample",
                                background: Color.pfGoldSoft,
                                foreground: Color.pfGoldText
                            )
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.pfSecondaryText)
                        .pfDecorative()
                }
            }
        }
        .buttonStyle(PFCardButtonStyle())
        .accessibilityLabel("Open lesson \(entry.title)")
    }

    private func subtitle(for entry: SearchEntry) -> String? {
        guard let chapter = entry.chapterNumber else { return nil }
        // Book numbers only: the internal chapter number never
        // shows. A held-out chapter has no book number, so the
        // subtitle falls back to the chapter name.
        guard let book = PFBookModeReadingOrder.bookNumber(forInternalNumber: chapter) else {
            return entry.chapterName
        }
        // Supplemental lessons have no lesson number in the
        // catalogue, so the subtitle names the chapter only and
        // never shows the 901-style authoring sequence.
        if entry.isSupplemental {
            return "Chapter \(book)"
        }
        if let display = PFBookModeReadingOrder.displayNumber(forLessonID: entry.id) {
            return "Chapter \(book), Lesson \(display)"
        }
        if let position = contentService.lessonPositionInChapter(for: entry) {
            return "Chapter \(book), Lesson \(position)"
        }
        if let lesson = entry.lessonNumber {
            return "Chapter \(book), Lesson \(lesson)"
        }
        return nil
    }
}

// MARK: - Follow the payment journey

/// The follow-the-payment journey: pain.001 to pacs.008 to pacs.002
/// using the same fictional values throughout, so the learner can
/// see what travels unchanged and what each message adds.
struct ISO20022JourneyView: View {
    var body: some View {
        ZStack {
            Color.pfBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    ISO20022DisclaimerCard()
                    introCard
                    sharedValuesCard
                    ForEach(Array(ISO20022Journey.steps.enumerated()), id: \.offset) { index, step in
                        VStack(spacing: PFSpacing.lg) {
                            stepSection(index: index, step: step)
                            if index < ISO20022Journey.steps.count - 1 {
                                Image(systemName: "arrow.down")
                                    .font(.pfSectionTitle)
                                    .foregroundColor(.pfRoyal)
                                    .pfDecorative()
                            }
                        }
                    }
                }
                .padding(PFSpacing.lg)
                .id("isoJourneyTop")
            }
            .pfScrollToTopOnAppear("isoJourneyTop")
        }
        .pfTabBarClearance()
        .navigationTitle("Follow the payment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var introCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("One payment, \(ISO20022Journey.steps.count) messages")
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                Text("Follow one fictional payment from the customer instruction to the bank-to-bank leg and back as a status report. The same amount and references appear in every sample, so watch what stays the same and what each message adds.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sharedValuesCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("The same fictional values throughout")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                ForEach(ISO20022Journey.sharedValues) { shared in
                    HStack(alignment: .firstTextBaseline, spacing: PFSpacing.sm) {
                        Text(shared.label)
                            .font(.pfCallout)
                            .foregroundColor(.pfSecondaryText)
                        Spacer()
                        Text(shared.value)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundColor(.pfNavy)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Text("All values are fictional and illustrative, including the UETR-style reference, which uses the well known example UUID.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stepSection(index: Int, step: ISO20022JourneyStep) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("Step \(index + 1) of \(ISO20022Journey.steps.count): \(step.messageID)")
                .font(.pfCaptionBold)
                .foregroundColor(.pfRoyal)
            PFSectionHeader(title: step.stepTitle)
            PFBodyText(text: step.narrative, textColor: .pfSecondaryText)
            ISO20022SampleXMLCard(sampleXML: step.sampleXML)
            if let message = ISO20022Catalogue.message(id: step.messageID) {
                NavigationLink(destination: ISO20022MessageDetailView(message: message)) {
                    HStack(spacing: PFSpacing.xs) {
                        Text("Explore \(step.messageID) in full")
                            .font(.pfCallout)
                            .fontWeight(.semibold)
                            .foregroundColor(.pfRoyal)
                        Image(systemName: "chevron.right")
                            .font(.pfCallout)
                            .fontWeight(.semibold)
                            .foregroundColor(.pfRoyal)
                            .pfDecorative()
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Explore \(step.messageID) in full")
            }
        }
    }
}

// MARK: - Mapping workbench

/// The mapping workbench: core fields traced across pain.001,
/// pacs.008 and pacs.002. Paths follow the base schema structures
/// shown in this explorer. The mapping is illustrative, and scheme
/// usage guides govern what is required in a live payment.
struct ISO20022MappingView: View {
    var body: some View {
        ZStack {
            Color.pfBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    ISO20022DisclaimerCard()
                    introCard
                    ForEach(ISO20022MappingWorkbench.rows) { row in
                        mappingCard(row)
                    }
                }
                .padding(PFSpacing.lg)
            }
        }
        .pfTabBarClearance()
        .navigationTitle("Mapping workbench")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var introCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("How \(ISO20022MappingWorkbench.rows.count) core fields map")
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                Text("Each card traces one concept from the customer instruction through the bank-to-bank payment to the status report. This mapping is illustrative: field paths follow the base schema structures shown in this explorer, and scheme usage guides govern what is required in a live payment.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func mappingCard(_ row: ISO20022MappingRow) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text(row.concept)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                mappingLine(label: "pain.001", value: row.pain001)
                mappingLine(label: "pacs.008", value: row.pacs008)
                mappingLine(label: "pacs.002", value: row.pacs002)
                Divider()
                PFBodyText(text: row.note, font: .pfCallout, textColor: .pfSecondaryText)
            }
        }
    }

    private func mappingLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PFSpacing.sm) {
            Text(label)
                .font(.pfCaptionBold)
                .foregroundColor(.pfRoyal)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.pfCallout)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
