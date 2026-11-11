// ChatAssistantService.swift
// PaymentForge iOS - Local chat assistant, hybrid answer writing.
// Retrieval is fully local and token-free: the app searches the
// course content already on the device (the search index, via
// SearchService and ChatAnswerPipeline) and finds the passages
// that answer the question. Answer writing goes through the
// chat-assistant edge function, which uses free LLM models
// (Groq free tier, then Gemini free tier) to turn those passages
// into a clear, professional answer. The LLM writes ONLY from the
// passages it is sent, never from its own knowledge. When the edge
// function is slow, fails, or the daily free budget is used up,
// the app shows its own local passage answer instead, so the
// chatbot never breaks and never leaves the learner staring at a
// spinner. No API key lives in the app: the keys stay in Supabase
// secrets, read only by the edge function.
// Guardrails, enforced here with keyword and pattern matching:
//   - Answer only from course content. Never invent anything
//     beyond the passage text.
//   - Say plainly when the course does not cover a question, and
//     suggest the closest topic.
//   - Stay on payments, banking and learning topics. Politely
//     decline unrelated questions.
//   - Never give personal financial advice.
//   - Never claim to be human. It identifies itself as the
//     Payments Training Hub chat assistant.
//   - Greetings and casual questions get a short, warm reply and
//     a steer back to the course.
// Chat history lives in memory for this session only.
// Guest is the default: the assistant works for guests and never
// forces sign-in.
// No em dashes in any user-facing text.

import Foundation
import SwiftUI

// MARK: - Wire types

/// One source an answer is grounded in: the catalogue entry it
/// came from, with its exact citation ("Chapter 39, Lesson 3:
/// pacs.002 Explained") so the learner can see where the answer
/// came from and tap through to it. The entry id is the stable
/// identity; the title is kept for the fallback title match.
struct ChatAssistantSource: Identifiable, Hashable {
    let entryID: String
    let title: String
    let citation: String
    var id: String { entryID.isEmpty ? title : entryID }

    init(entry: SearchEntry) {
        self.entryID = entry.id
        self.title = entry.title
        self.citation = entry.citation
    }

    init(title: String) {
        self.entryID = ""
        self.title = title
        self.citation = title
    }
}

// MARK: - Chat message

enum ChatAssistantRole {
    case user
    case assistant
}

/// One chat message. Assistant messages carry the sources their
/// answer was grounded in and the follow-up questions to try next;
/// user messages carry neither.
struct ChatAssistantMessage: Identifiable {
    let id = UUID()
    let role: ChatAssistantRole
    let text: String
    let sources: [ChatAssistantSource]
    let followUps: [String]

    init(role: ChatAssistantRole, text: String, sources: [ChatAssistantSource] = [], followUps: [String] = []) {
        self.role = role
        self.text = text
        self.sources = sources
        self.followUps = followUps
    }
}

// MARK: - Service

/// Owns one chat assistant session. History lives in memory only,
/// for this session; nothing is stored in Supabase and nothing is
/// sent to any server.
@MainActor
final class ChatAssistantService: ObservableObject {
    static let moreExcerptChars = 1500

    @Published private(set) var messages: [ChatAssistantMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String? = nil

    private let contentService = ContentService.shared

    /// The last assistant message, for the follow-up chips under
    /// the chat and for "tell me more". Nil when no assistant
    /// answer has arrived yet.
    var lastAssistantMessage: ChatAssistantMessage? {
        messages.last { $0.role == .assistant }
    }

    /// Starter questions shown before the first question and
    /// offered after a reply that has no better follow-up.
    static let starterQuestions = [
        "What is an MT103?",
        "How does a pacs.008 work?",
        "Explain nostro and vostro"
    ]

    /// Send a question: classify it, then answer locally. A
    /// failed send (the search index could not load) leaves the
    /// user's question in the list so Retry can send it again.
    func sendQuestion(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        messages.append(ChatAssistantMessage(role: .user, text: trimmed))
        let reply = await answer(question: trimmed)
        switch reply {
        case .message(let message):
            messages.append(message)
        case .failure(let text):
            errorMessage = text
        }
        isLoading = false
    }

    /// Send the last user question again, for the Retry button. The
    /// question and anything after it are removed first, so the
    /// retry does not duplicate the question in the list.
    func retryLastQuestion() async {
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else { return }
        let question = messages[lastUserIndex].text
        messages.removeSubrange(lastUserIndex...)
        await sendQuestion(question)
    }

    /// The catalogue entry for a source: by entry id first (the
    /// stable identity), then by a case-insensitive exact title
    /// match. Nil when no entry in the loaded index matches.
    func entry(forSource source: ChatAssistantSource) -> SearchEntry? {
        guard let entries = contentService.searchIndex?.entries else { return nil }
        if !source.entryID.isEmpty,
           let byID = entries.first(where: { $0.id == source.entryID }) {
            return byID
        }
        let wanted = source.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        return entries.first {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted
        }
    }

    /// The catalogue entry for a source title, so the view can open
    /// the lesson, guide or Situation the answer was grounded in.
    /// Case-insensitive exact title match; nil when no entry in the
    /// loaded index has that title.
    func entry(forSourceTitle title: String) -> SearchEntry? {
        entry(forSource: ChatAssistantSource(title: title))
    }

    // MARK: - Answering

    private enum AnswerResult {
        case message(ChatAssistantMessage)
        case failure(String)
    }

    /// Classify the question and build the reply. Retrieval is
    /// local; answer writing goes through the free chat-assistant
    /// edge function, with the local passage answer as fallback.
    private func answer(question: String) async -> AnswerResult {
        // Personal financial advice is declined first: it is a
        // safety guardrail, not a course question.
        if isAdviceRequest(question) {
            return .message(ChatAssistantMessage(
                role: .assistant,
                text: "I can't give personal financial advice or advice about your money. I can help you learn how payments and banking work, though. What would you like to learn about?",
                followUps: Self.starterQuestions
            ))
        }
        // Casual conversation gets a short, warm reply.
        if let conversational = conversationalReply(for: question) {
            return .message(ChatAssistantMessage(
                role: .assistant,
                text: conversational,
                followUps: Self.starterQuestions
            ))
        }
        // "Tell me more" expands the last answer's top source with
        // a longer excerpt from the same course entry.
        if isFollowUpRequest(question), let more = moreDetailMessage() {
            return .message(more)
        }
        // Course question: retrieve the answering passages locally,
        // then let the free LLM write a professional answer from
        // them. When that call is slow or fails, the local passage
        // answer is shown instead, so the learner always gets an
        // answer and never waits on a spinner.
        if contentService.searchIndex == nil {
            await contentService.loadSearchIndex()
        }
        guard let entries = contentService.searchIndex?.entries, !entries.isEmpty else {
            return .failure("The course content could not be loaded. Check your connection and try again.")
        }
        guard let local = ChatAnswerPipeline.localAnswer(question: question, entries: entries) else {
            // Graceful not-found: one sentence, plus the closest
            // topic the course does cover, with its source link.
            // Never show an irrelevant lesson as if it were the
            // answer.
            if let closest = ChatAnswerPipeline.closestTopic(question: question, entries: entries),
               containsDomainKeyword(question) {
                let intent = ChatAnswerPipeline.detectIntent(question)
                return .message(ChatAssistantMessage(
                    role: .assistant,
                    text: "The course does not cover that yet. The closest topic it covers is \(closest.title).",
                    sources: [ChatAssistantSource(entry: closest)],
                    followUps: ChatAnswerPipeline.followUps(question: question, intent: intent, entry: closest)
                ))
            }
            return .message(ChatAssistantMessage(
                role: .assistant,
                text: "I can only help with the Payments Training Hub course content, payments and banking. Try asking about a lesson, or open a lesson from the Learn tab.",
                followUps: Self.starterQuestions
            ))
        }
        // Try the free LLM answer writer first. It gets the
        // question and the top 3 passages only, so one call stays
        // lean and the daily free budget stretches further.
        if let written = await writtenAnswer(question: question, local: local) {
            return .message(written)
        }
        return .message(localAnswerMessage(local: local))
    }

    /// The local answer as a chat message: the direct answer, the
    /// source line, the source links and two real follow-up
    /// questions. This is also the fallback when the LLM answer
    /// writer is unavailable, so the learner always gets a good
    /// answer.
    private func localAnswerMessage(local: ChatLocalAnswer) -> ChatAssistantMessage {
        ChatAssistantMessage(
            role: .assistant,
            text: local.text,
            sources: local.sources.map { ChatAssistantSource(entry: $0) },
            followUps: local.followUps
        )
    }

    /// Ask the chat-assistant edge function to write a professional
    /// answer from the local passages. Returns nil on any failure
    /// (slow, rate-limited, daily budget used up, function not
    /// deployed yet), so the caller falls back to the local answer.
    /// The call is bounded at 25 seconds: the learner never waits
    /// on a spinner longer than that.
    private func writtenAnswer(question: String, local: ChatLocalAnswer) async -> ChatAssistantMessage? {
        struct PassagePayload: Encodable {
            let title: String
            let excerpt: String
        }
        struct AnswerRequest: Encodable {
            let question: String
            let passages: [PassagePayload]
        }
        struct AnswerResponse: Decodable {
            let answer: String?
            let followUps: [String]?
        }
        // The passages that grounded the local answer, at most 3,
        // each trimmed so the prompt stays lean.
        var passages: [PassagePayload] = []
        for source in local.sources.prefix(3) {
            let body = source.bodyText
            let excerpt = String(body.prefix(600))
            passages.append(PassagePayload(title: source.title, excerpt: excerpt))
        }
        if passages.isEmpty {
            return nil
        }
        let request = AnswerRequest(question: question, passages: passages)
        do {
            let data = try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await SupabaseClient.shared.invokeFunction(name: "chat-assistant", body: request, accessToken: nil)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 25_000_000_000)
                    throw ChatAnswerError.timedOut
                }
                guard let first = try await group.next() else {
                    throw ChatAnswerError.timedOut
                }
                group.cancelAll()
                return first
            }
            guard let decoded = try? JSONDecoder().decode(AnswerResponse.self, from: data),
                  let answer = decoded.answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            // The written answer keeps the local sources (the real
            // course entries, for tap-through) and the local
            // follow-ups when the function gave none. The source
            // line names the exact chapter and lesson, so the
            // LLM-written answer carries the same proof as the
            // local one.
            let followUps = (decoded.followUps ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let finalFollowUps = followUps.isEmpty ? local.followUps : Array(followUps.prefix(2))
            let sourceLine = "\n\nSource: " + local.sources.map(\.citation).joined(separator: " and ")
            // Never show a written answer that forgot its source.
            let text = (answer.contains("Source:") || answer.contains("From the course:")) ? answer : answer + sourceLine
            return ChatAssistantMessage(
                role: .assistant,
                text: text,
                sources: local.sources.map { ChatAssistantSource(entry: $0) },
                followUps: finalFollowUps
            )
        } catch {
            return nil
        }
    }

    private enum ChatAnswerError: Error {
        case timedOut
    }

    /// "Tell me more" (or similar) after an answer: a longer
    /// excerpt from the same top source, so the learner gets more
    /// of the course's own words. Nil when there is no previous
    /// assistant answer with a source.
    private func moreDetailMessage() -> ChatAssistantMessage? {
        guard let last = lastAssistantMessage,
              let topSource = last.sources.first,
              let entry = entry(forSource: topSource) else {
            return nil
        }
        let body = trimmedExcerpt(entry.bodyText, maxChars: Self.moreExcerptChars)
        let text = "\(body)\n\nSource: \(entry.citation)"
        let intent = ChatAnswerPipeline.detectIntent(topSource.title)
        let followUps = ChatAnswerPipeline.followUps(question: topSource.title, intent: intent, entry: entry)
        return ChatAssistantMessage(
            role: .assistant,
            text: text,
            sources: last.sources,
            followUps: followUps
        )
    }

    /// Trim an excerpt to a readable length, ending at a word
    /// boundary. Adds an ellipsis when the text was cut, so the
    /// learner knows the full lesson has more.
    private func trimmedExcerpt(_ text: String, maxChars: Int) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxChars else { return cleaned }
        let cut = cleaned.prefix(maxChars)
        if let lastSpace = cut.lastIndex(of: " ") {
            return String(cut[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return String(cut).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    // MARK: - Conversational patterns

    /// A short, warm reply for a greeting or casual question, or
    /// nil when the message is not conversational. Matching is by
    /// keyword and pattern only; there is no AI.
    private func conversationalReply(for question: String) -> String? {
        let n = normalized(question)
        if isHowAreYou(n) {
            return "I'm doing well, thanks for asking! I'm here to help you learn payments and banking. What would you like to ask about?"
        }
        if isWhoAreYou(n) {
            return "I'm the Payments Training Hub chat assistant, an AI helper for learners. I help with payments, banking, ISO 20022, SWIFT and the course content. Ask me anything from your lessons."
        }
        if isThanks(n) {
            return "You're welcome! Happy to help. Ask me anything else about payments and banking."
        }
        if isBye(n) {
            return "Goodbye! Good luck with your learning. I'm here whenever you need help with payments and banking."
        }
        if isGreeting(n) {
            return "Hello! I'm the Payments Training Hub chat assistant. I can explain payment messages, rails, exceptions, and more. Try asking what a pacs.008 is, or how UPI settlement works."
        }
        return nil
    }

    /// Lowercase, strip punctuation, collapse spaces. Used so a
    /// greeting still matches with a capital letter or a "!" at
    /// the end.
    private func normalized(_ text: String) -> String {
        let lowered = text.lowercased()
        let stripped = lowered.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == " " ? Character(scalar) : " "
        }
        return String(stripped).split(separator: " ").joined(separator: " ")
    }

    private func wordCount(_ normalized: String) -> Int {
        normalized.split(separator: " ").count
    }

    private func isGreeting(_ n: String) -> Bool {
        let greetings: Set<String> = [
            "hi", "hello", "hey", "hi there", "hello there", "hey there",
            "morning", "good morning", "good afternoon", "good evening",
            "hiya", "yo", "namaste"
        ]
        if greetings.contains(n) { return true }
        if n.hasPrefix("good morning") || n.hasPrefix("good afternoon") || n.hasPrefix("good evening") {
            return wordCount(n) <= 4
        }
        if let first = n.split(separator: " ").first, ["hi", "hello", "hey"].contains(String(first)) {
            return wordCount(n) <= 3
        }
        return false
    }

    private func isHowAreYou(_ n: String) -> Bool {
        n.contains("how are you")
            || n.contains("how are u")
            || n.contains("how r you")
            || n.contains("how s it going")
            || n.contains("how is it going")
            || n.contains("what s up")
            || n.contains("whats up")
            || n.contains("how are you doing")
            || n.contains("how are you today")
    }

    private func isWhoAreYou(_ n: String) -> Bool {
        n.contains("who are you")
            || n.contains("what are you")
            || n.contains("who r you")
            || n.contains("what r you")
            || n.contains("what is your name")
            || n.contains("whats your name")
            || n.contains("who made you")
            || n.contains("are you human")
            || n.contains("are you a robot")
            || n.contains("are you real")
    }

    private func isThanks(_ n: String) -> Bool {
        if n == "thanks" || n == "thank you" || n == "thank you so much" || n == "thanks a lot" || n == "thanks so much" {
            return true
        }
        if (n.hasPrefix("thank you") || n.hasPrefix("thanks")) && wordCount(n) <= 5 {
            return true
        }
        return false
    }

    private func isBye(_ n: String) -> Bool {
        if ["bye", "goodbye", "good bye", "see you", "see you later", "good night"].contains(n) {
            return true
        }
        if (n.hasPrefix("bye") || n.hasPrefix("goodbye")) && wordCount(n) <= 3 {
            return true
        }
        return false
    }

    /// "Tell me more" and similar, only when there is a previous
    /// assistant answer to expand.
    private func isFollowUpRequest(_ question: String) -> Bool {
        guard lastAssistantMessage != nil, !lastAssistantMessage!.sources.isEmpty else { return false }
        let n = normalized(question)
        return n == "tell me more"
            || n == "more"
            || n == "give me an example"
            || n == "show me an example"
            || n == "explain more"
            || n == "go on"
            || n == "continue"
            || n == "what else"
            || n == "tell me more about it"
            || n == "can you explain more"
            || n.hasPrefix("tell me more")
            || n.hasPrefix("give me an example")
    }

    // MARK: - Guardrail keyword checks

    /// Personal financial advice. These phrases mean the learner
    /// is asking about their own money, not about how payments
    /// work. The list is deliberately narrow, so a course question
    /// that mentions a word like "investment" in passing is not
    /// blocked.
    private func isAdviceRequest(_ question: String) -> Bool {
        let lower = question.lowercased()
        let phrases = [
            "should i invest", "should i buy", "should i sell",
            "invest in", "buy stock", "sell stock",
            "my money", "my salary", "my savings",
            "personal loan", "home loan",
            "best bank", "best credit card",
            "which bank should", "tax advice",
            "is it a good investment", "will i make money",
            "how much money should i", "should i open"
        ]
        return phrases.contains { lower.contains($0) }
    }

    /// Payments and banking vocabulary. A question with none of
    /// these words and no search match is treated as off-topic
    /// rather than as a course gap. The list is broad on purpose,
    /// so a genuine course question is not misread as off-topic.
    private func containsDomainKeyword(_ question: String) -> Bool {
        let lower = question.lowercased()
        let keywords = [
            "payment", "bank", "swift", "iso", "mt103", "mt202", "mt101",
            "mt940", "mt942", "pacs", "camt", "sepa", "nostro", "vostro",
            "clearing", "settlement", "liquidity", "treasury", "card",
            "visa", "mastercard", "upi", "rtgs", "neft", "imps", "ach",
            "wire", "transfer", "remittance", "correspondent", "fx",
            "foreign exchange", "currency", "account", "ledger",
            "reconciliation", "compliance", "aml", "kyc", "fraud", "risk",
            "api", "message", "mandate", "direct debit", "standing order",
            "salary", "payroll", "merchant", "acquirer", "issuer", "scheme",
            "interchange", "chargeback", "refund", "escrow", "cross-border",
            "cross border", "gpi", "fedwire", "chips", "target2",
            "faster payments", "bacs", "chaps", "eft", "pos", "atm",
            "token", "3ds", "sca", "psd2", "open banking", "cbdc",
            "stablecoin", "crypto", "blockchain", "wallet", "cheque",
            "check", "draft", "letter of credit", "guarantee",
            "trade finance", "sanction", "screening", "onboarding",
            "customer", "interest", "fee", "charges", "limit", "cut-off",
            "cutoff", "value date", "business day", "uetr", "tracker",
            "reference", "xml", "json", "webhook", "integration",
            "core banking", "branch", "teller", "qr", "nfc", "contactless",
            "pin", "otp", "authentication", "authorization", "dispute",
            "reversal", "return", "recall", "reject", "pending",
            "processing", "settled", "cleared", "booked", "posted",
            "amount", "conversion", "rate", "spread", "markup", "cost",
            "pricing", "tariff", "subscription", "invoice", "billing",
            "payout", "payin", "disbursement", "collection", "domestic",
            "international", "offshore", "onshore", "corridor", "beneficiary",
            "originator", "sender", "receiver", "payer", "payee", "debtor",
            "creditor", "agent", "intermediary", "respondent", "nostro",
            "vostro", "intraday", "overnight", "repo", "collateral",
            "margin", "sanction", "pep", "kyc", "aml", "cft", "fatf",
            "basel", "bis", "ecb", "federal reserve", "rbi", "bank of england",
            "lesson", "course", "chapter", "guide", "situation", "quiz",
            "exam", "certificate", "learn", "study", "training", "hub"
        ]
        return keywords.contains { lower.contains($0) }
    }
}
