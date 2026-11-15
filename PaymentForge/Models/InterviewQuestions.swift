// InterviewQuestions.swift
// Payments Training Hub iOS - Interview questions bank.
//
// ContentManifest.interviewQuestionCount situation-based interview questions for payments and BA roles,
// bundled as interview-questions.json in Resources. Loaded from the
// app bundle only; no network, no backend. Each question carries a
// short model answer written in plain language. The questions are
// deliberately scenario and process based, not basic definitions.

import Foundation

/// One interview question with its model answer.
struct InterviewQuestion: Codable, Identifiable, Hashable {
    let id: String
    let question: String
    let answer: String
}

/// One category of interview questions.
struct InterviewCategory: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let questions: [InterviewQuestion]
}

/// The whole interview question bank as stored in the bundled JSON.
struct InterviewQuestionBank: Codable {
    let version: Int
    let total: Int
    let categories: [InterviewCategory]
}

/// Loads the bundled interview question bank and searches it.
enum InterviewQuestionStore {
    /// The bundled bank, loaded at first access. Nil only if the
    /// bundled JSON is missing or unreadable, which should never
    /// happen in a shipped build. `reload()` re-reads the file for
    /// the view's Try again action; readers always see the latest
    /// load attempt.
    static private(set) var shared: InterviewQuestionBank? = load()

    /// Re-read the bundled JSON, for the Try again action when the
    /// first load failed. The bank is bundled, so a retry only
    /// helps when the first read failed transiently; the view
    /// keeps showing the unavailable state when the file is
    /// genuinely missing or malformed.
    static func reload() {
        shared = load()
    }

    private static func load() -> InterviewQuestionBank? {
        guard let url = Bundle.main.url(forResource: "interview-questions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(InterviewQuestionBank.self, from: data)
    }

    /// All questions across categories, in file order.
    static var allQuestions: [InterviewQuestion] {
        shared?.categories.flatMap(\.questions) ?? []
    }

    /// Total questions in the bank, from the bundled data.
    static var totalCount: Int {
        shared?.total ?? allQuestions.count
    }

    /// The category a question belongs to, by question id.
    static func categoryTitle(for questionID: String) -> String? {
        shared?.categories.first { category in
            category.questions.contains { $0.id == questionID }
        }?.title
    }

    /// Questions whose question or answer contains the query text,
    /// case-insensitive. An empty query returns everything.
    static func search(_ query: String) -> [InterviewQuestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allQuestions }
        let needle = trimmed.lowercased()
        return allQuestions.filter {
            $0.question.lowercased().contains(needle) ||
            $0.answer.lowercased().contains(needle)
        }
    }
}

// MARK: - Interview Ready gating

/// The Interview Ready gate for model answers. Question text is
/// discovery and always stays visible; the model answer locks.
/// The first 5 questions of the bank, in bank order, are free
/// samples with their answers open. Every other answer needs
/// Interview Ready (or the Integrated Course, which includes it).
/// Pure logic over the bank, covered by unit tests through the
/// free-sample rules.
enum InterviewReadyGating {

    /// The free sample questions: the first 5 of the bank, in
    /// bank order.
    static var freeQuestions: [InterviewQuestion] {
        Array(InterviewQuestionStore.allQuestions.prefix(FreeSampleRules.interviewFreeQuestionCount))
    }

    /// True when this question is one of the 5 free samples.
    static func isFreeQuestion(_ question: InterviewQuestion) -> Bool {
        freeQuestions.contains(question)
    }

    /// True when this question's model answer is locked: the
    /// learner has no Interview Ready entitlement and the question
    /// is not a free sample.
    static func isAnswerLocked(_ question: InterviewQuestion, isInterviewUnlocked: Bool) -> Bool {
        !isInterviewUnlocked && !isFreeQuestion(question)
    }
}
