// ChatAssistantView.swift
// PaymentForge iOS - Local chat assistant screen.
// A real working chat that answers ONLY from the course content
// already in the app. It makes no AI provider call, no server call
// and no edge function call, so it works fully offline with no API
// key and no tokens. Questions go to ChatAssistantService, which
// searches the local search index and shows the course's own words
// with a link to open the full lesson, guide or Situation.
// Chat history lives in memory for this session only. Guest is the
// default: the assistant works for guests and never forces sign-in.
// Layout: user questions on the right, assistant answers on the
// left with a chat tile, source titles under each answer that open
// the lesson or Situation, suggested follow-up chips, and a bottom
// input field with a send button. Greetings and casual questions
// get a short, warm reply and a steer back to the course.
// No em dashes in any user-facing text.

import SwiftUI

struct ChatAssistantView: View {
    @EnvironmentObject private var contentService: ContentService
    @StateObject private var assistant = ChatAssistantService()
    @State private var draft = ""
    @State private var typingPulse = false

    /// Starter questions, from real catalogue topics. Tapping one
    /// sends it as a real question; nothing here is a canned answer.
    private let starterQuestions = ChatAssistantService.starterQuestions

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        if assistant.messages.isEmpty && assistant.errorMessage == nil && !assistant.isLoading {
                            welcomeCard
                        }
                        ForEach(assistant.messages.indices, id: \.self) { index in
                            messageRow(for: assistant.messages[index], isLatest: index == assistant.messages.count - 1)
                        }
                        if assistant.isLoading {
                            typingRow
                        }
                        if let errorMessage = assistant.errorMessage {
                            PFErrorStateView(
                                title: "The chat assistant could not answer",
                                message: errorMessage,
                                retryTitle: "Try again"
                            ) {
                                Task { await assistant.retryLastQuestion() }
                            }
                        }
                        Color.clear.frame(height: 1).id("chatBottom")
                    }
                    .padding(PFSpacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: assistant.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: assistant.isLoading) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: assistant.errorMessage) { _, _ in
                    scrollToBottom(proxy)
                }
                inputBar
            }
        }
        .background(Color.pfBackground)
        .navigationTitle("Chat Assistant")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sending

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !assistant.isLoading
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !assistant.isLoading else { return }
        draft = ""
        Task { await assistant.sendQuestion(trimmed) }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            proxy.scrollTo("chatBottom", anchor: .bottom)
        }
    }

    // MARK: - Welcome

    /// Shown before the first question: what the assistant is, and
    /// starter questions that send as real questions when tapped.
    private var welcomeCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.md) {
                    PaperclipMascot(size: 48)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Chat Assistant")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("I'm the Payments Training Hub chat assistant. I answer only from your lessons, guides and Payment Cases.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Try one of these, or type your own question below.")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(starterQuestions, id: \.self) { question in
                    Button {
                        send(question)
                    } label: {
                        Text(question)
                            .font(.pfCallout)
                            .foregroundColor(.pfRoyal)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.pfRoyal.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(assistant.isLoading)
                    .accessibilityLabel("Ask: \(question)")
                }
            }
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private func messageRow(for message: ChatAssistantMessage, isLatest: Bool = false) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.pfBody)
                    .foregroundColor(.white)
                    .padding(.horizontal, PFSpacing.md)
                    .padding(.vertical, 10)
                    .background(Color.pfRoyal)
                    .cornerRadius(16)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Your question: \(message.text)")
            }
        case .assistant:
            HStack(alignment: .top, spacing: PFSpacing.sm) {
                AssistantMessageAvatar(animate: isLatest)
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    ChatAssistantMarkdownView(text: message.text)
                    if !message.sources.isEmpty {
                        sourcesRow(for: message)
                    }
                    if !message.followUps.isEmpty {
                        followUpChips(for: message)
                    }
                }
                .padding(PFSpacing.md)
                .background(Color.pfCard)
                .cornerRadius(PFSpacing.cardRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                        .stroke(Color.pfBorder, lineWidth: 1)
                )
            }
        }
    }

    /// The paperclip mascot beside each assistant answer, with a
    /// small nod when the newest answer appears: the talking
    /// movement while the response is being shown.
    private struct AssistantMessageAvatar: View {
        let animate: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var nod: CGFloat = 0

        var body: some View {
            PaperclipMascot(size: 36)
                .offset(y: nod)
                .onAppear {
                    guard animate, !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.22)) { nod = -3 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        withAnimation(.easeInOut(duration: 0.22)) { nod = 0 }
                    }
                }
        }
    }

    /// The paperclip mascot beside the typing indicator: eyes
    /// up, thinking of the answer.
    private var thinkingAvatar: some View {
        PaperclipMascot(size: 36, expression: .thinking)
    }

    /// Three pulsing dots while the answer is being prepared.
    private var typingRow: some View {
        HStack(alignment: .top, spacing: PFSpacing.sm) {
            thinkingAvatar
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.pfRoyal)
                        .frame(width: 8, height: 8)
                        .opacity(typingPulse ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.2),
                            value: typingPulse
                        )
                }
            }
            .padding(.horizontal, PFSpacing.md)
            .padding(.vertical, 14)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                    .stroke(Color.pfBorder, lineWidth: 1)
            )
            .onAppear { typingPulse = true }
            .onDisappear { typingPulse = false }
        }
        .accessibilityLabel("The chat assistant is thinking")
    }

    // MARK: - Sources

    /// The exact citations the answer was grounded in: chapter
    /// and lesson for lessons, type and title otherwise. Each
    /// citation that matches a real catalogue entry opens that
    /// lesson, guide or Situation; a citation with no match is
    /// shown as plain text, never linked to something invented.
    private func sourcesRow(for message: ChatAssistantMessage) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.xs) {
            Text("Sources")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            ForEach(message.sources) { source in
                sourceLink(for: source)
            }
        }
    }

    @ViewBuilder
    private func sourceLink(for source: ChatAssistantSource) -> some View {
        if let entry = assistant.entry(forSource: source) {
            NavigationLink(destination: destination(for: entry)) {
                HStack(spacing: PFSpacing.xs) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(source.citation)
                        .font(.pfCaptionBold)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(.pfRoyal)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.pfRoyal.opacity(0.08))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open source: \(source.citation)")
            .accessibilityHint("Opens the \(entry.type.displayName.lowercased()) \(source.title)")
        } else {
            Text(source.citation)
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Source: \(source.citation)")
        }
    }

    /// The screen for a source entry: lessons open the lesson
    /// player, Situations open the Situation detail, and guides,
    /// labs, tests and FAQs open the entry detail.
    @ViewBuilder
    private func destination(for entry: SearchEntry) -> some View {
        switch entry.type {
        case .lesson:
            LessonView(entry: entry)
        case .situation:
            SituationDetailView(situation: situationFor(entry: entry))
        default:
            EntryDetailView(entry: entry)
        }
    }

    private func situationFor(entry: SearchEntry) -> Situation {
        if let full = contentService.fullSituations?.first(where: { $0.id == entry.id }) {
            return situation(fromFull: full)
        }
        return situation(from: entry)
    }

    // MARK: - Follow-ups

    /// Suggested follow-up questions from the last answer. Tapping
    /// one sends it as the next question.
    private func followUpChips(for message: ChatAssistantMessage) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.xs) {
            Text("Suggested follow-ups")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            ForEach(message.followUps, id: \.self) { followUp in
                Button {
                    send(followUp)
                } label: {
                    HStack(spacing: PFSpacing.xs) {
                        Text(followUp)
                            .font(.pfCallout)
                            .foregroundColor(.pfRoyal)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.pfRoyal)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.pfCard)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.pfBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(assistant.isLoading)
                .accessibilityLabel("Ask follow-up: \(followUp)")
            }
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: PFSpacing.sm) {
            TextField("Ask a payments question...", text: $draft)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .onSubmit { send(draft) }
                .accessibilityLabel("Ask a payments question")
                .padding(.horizontal, PFSpacing.md)
                .padding(.vertical, 12)
                .background(Color.pfBackground)
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.pfBorder, lineWidth: 1)
                )
            Button {
                send(draft)
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(canSend ? Color.pfRoyal : Color.pfSecondaryText.opacity(0.4))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send question")
            .accessibilityHint("Sends your question to the chat assistant")
        }
        .padding(.horizontal, PFSpacing.lg)
        .padding(.vertical, PFSpacing.sm)
        .background(Color.pfCard)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Color.pfBorder),
            alignment: .top
        )
    }
}

// MARK: - Markdown rendering (bold + comparison tables)

/// Renders the assistant's markdown answer: bold text and pipe
/// tables. Tables become real SwiftUI grids; every other line is
/// rendered as text with **bold** segments honoured. No other
/// markdown is interpreted, so an unexpected answer still renders
/// as plain text.
struct ChatAssistantMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            ForEach(blocks.indices, id: \.self) { index in
                blockView(blocks[index])
            }
        }
    }

    private var blocks: [ChatAssistantMarkdownBlock] {
        ChatAssistantMarkdownParser.blocks(from: text)
    }

    @ViewBuilder
    private func blockView(_ block: ChatAssistantMarkdownBlock) -> some View {
        switch block {
        case .paragraph(let paragraph):
            ChatAssistantRichText(text: paragraph)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
        case .table(let headers, let rows):
            ChatAssistantTableView(headers: headers, rows: rows)
        }
    }
}

enum ChatAssistantMarkdownBlock {
    case paragraph(String)
    case table(headers: [String], rows: [[String]])
}

enum ChatAssistantMarkdownParser {
    /// Split an answer into paragraph blocks and pipe-table blocks.
    /// A blank line ends a paragraph; consecutive lines starting
    /// with "|" form one table.
    static func blocks(from text: String) -> [ChatAssistantMarkdownBlock] {
        var blocks: [ChatAssistantMarkdownBlock] = []
        var paragraphLines: [String] = []
        var tableLines: [String] = []

        func flushParagraph() {
            let joined = paragraphLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.paragraph(joined))
            }
            paragraphLines = []
        }

        func flushTable() {
            if let table = table(from: tableLines) {
                blocks.append(table)
            } else if !tableLines.isEmpty {
                // Lines that looked like a table but did not parse
                // are shown as plain text, never dropped.
                blocks.append(.paragraph(tableLines.joined(separator: "\n")))
            }
            tableLines = []
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") {
                flushParagraph()
                tableLines.append(trimmed)
            } else {
                if !tableLines.isEmpty {
                    flushTable()
                }
                if trimmed.isEmpty {
                    flushParagraph()
                } else {
                    paragraphLines.append(line)
                }
            }
        }
        flushParagraph()
        flushTable()
        return blocks
    }

    /// Parse collected pipe lines into a table. The first row is
    /// the header, a separator row of dashes is skipped, and the
    /// rest are data rows. Returns nil when there is no usable
    /// header row or no data rows.
    private static func table(from lines: [String]) -> ChatAssistantMarkdownBlock? {
        let rows = lines.map { splitRow($0) }.filter { !$0.isEmpty }
        guard let headers = rows.first, !headers.isEmpty else { return nil }
        let dataRows = rows.dropFirst().filter { !isSeparatorRow($0) }
        guard !dataRows.isEmpty else { return nil }
        let width = headers.count
        let padded = dataRows.map { row in
            row + Array(repeating: "", count: max(0, width - row.count))
        }
        return .table(headers: headers, rows: padded)
    }

    private static func splitRow(_ line: String) -> [String] {
        line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }
}

/// One paragraph with **bold** segments rendered bold. Backticks
/// are stripped, since the course text uses them for message names
/// such as pacs.008 and they read better without them.
struct ChatAssistantRichText: View {
    let text: String

    var body: some View {
        parsed
    }

    private var parsed: Text {
        let cleaned = text.replacingOccurrences(of: "`", with: "")
        var result = Text("")
        var rest = cleaned
        while let open = rest.range(of: "**") {
            let before = String(rest[..<open.lowerBound])
            if !before.isEmpty {
                result = result + Text(before)
            }
            let afterOpen = rest[open.upperBound...]
            if let close = afterOpen.range(of: "**") {
                let boldPart = String(afterOpen[..<close.lowerBound])
                if !boldPart.isEmpty {
                    result = result + Text(boldPart).bold()
                }
                rest = String(afterOpen[close.upperBound...])
            } else {
                result = result + Text("**" + String(afterOpen))
                rest = ""
            }
        }
        if !rest.isEmpty {
            result = result + Text(rest)
        }
        return result
    }
}

/// A comparison table as a real grid: bold header row on a soft
/// navy background, one row per aspect, hairline outer border.
struct ChatAssistantTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(headers.indices, id: \.self) { index in
                    ChatAssistantRichText(text: headers[index])
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                        .padding(8)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .background(Color.pfNavySoft)
                }
            }
            ForEach(rows.indices, id: \.self) { rowIndex in
                GridRow {
                    ForEach(rows[rowIndex].indices, id: \.self) { columnIndex in
                        ChatAssistantRichText(text: rows[rowIndex][columnIndex])
                            .font(.pfCaption)
                            .foregroundColor(.pfNavy)
                            .padding(8)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .background(rowIndex % 2 == 1 ? Color.pfNavySoft.opacity(0.5) : Color.clear)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel(tableAccessibilityLabel)
    }

    private var tableAccessibilityLabel: String {
        var parts: [String] = []
        parts.append(headers.joined(separator: ", "))
        for row in rows {
            parts.append(row.joined(separator: ", "))
        }
        return "Comparison table. " + parts.joined(separator: ". ")
    }
}
