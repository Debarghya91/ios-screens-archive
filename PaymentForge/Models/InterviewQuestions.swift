// InterviewQuestions.swift
// PaymentForge iOS - Interview questions bank.
//
// 500 situation-based interview questions for payments and BA roles,
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
    /// The bundled bank, loaded once. Nil only if the bundled JSON
    /// is missing or unreadable, which should never happen in a
    /// shipped build.
    static let shared: InterviewQuestionBank? = load()

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
