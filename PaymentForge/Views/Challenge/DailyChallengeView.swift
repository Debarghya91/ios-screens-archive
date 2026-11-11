// DailyChallengeView.swift
// PaymentForge iOS - Daily Challenge: one real situation per day.
// The situation is picked deterministically from the 564 by the
// calendar day, so every learner gets the same challenge each day and
// it changes daily. The question is "What is the key lesson here?":
// the correct option is the situation's own takeaway, and the wrong
// options are the takeaways of three other real situations, so every
// option is real text and none is an invented technical fact. The
// explanation is the situation's own takeaway. Completion is tracked
// locally, one per day.
// No em dashes in any user-facing text.

import SwiftUI

struct DailyChallengeView: View {
    @EnvironmentObject private var contentService: ContentService

    @State private var selectedOption: Int? = nil
    @State private var answered = false

    private enum Keys {
        static func completed(for dayKey: String) -> String {
            "pf.dailyChallenge.completed.\(dayKey).v1"
        }
        static func correct(for dayKey: String) -> String {
            "pf.dailyChallenge.correct.\(dayKey).v1"
        }
    }

    /// Calendar day key, local time, for example 2026-11-11.
    private var dayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Days since the epoch, local calendar: the deterministic seed.
    private var dayNumber: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let epoch = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 0))
        return Calendar.current.dateComponents([.day], from: epoch, to: start).day ?? 0
    }

    /// All real situations, full data first, search index fallback.
    private var situations: [Situation] {
        if let full = contentService.fullSituations, !full.isEmpty {
            return full.map { situation(fromFull: $0) }
        }
        return contentService.allSituations.map { situation(from: $0) }
    }

    /// Today's situation, deterministic by day.
    private var todaysSituation: Situation? {
        guard !situations.isEmpty else { return nil }
        return situations[dayNumber % situations.count]
    }

    /// The four answer options: today's takeaway plus three other real
    /// takeaways, shuffled deterministically by the day number.
    private var options: [(text: String, isCorrect: Bool)] {
        guard let today = todaysSituation else { return [] }
        var pool: [(String, Bool)] = [(firstSentence(of: today.takeaway), true)]
        let offsets = [97, 211, 331]
        for offset in offsets {
            let other = situations[(dayNumber + offset) % situations.count]
            guard other.id != today.id else { continue }
            let text = firstSentence(of: other.takeaway)
            if !pool.contains(where: { $0.0 == text }) {
                pool.append((text, false))
            }
        }
        var shuffled = pool
        var seed = UInt64(bitPattern: Int64(dayNumber &+ 1))
        for index in stride(from: shuffled.count - 1, through: 1, by: -1) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let swap = Int(seed % UInt64(index + 1))
            shuffled.swapAt(index, swap)
        }
        return shuffled
    }

    /// First sentence of a takeaway, capped so an option stays readable.
    private func firstSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "See the situation takeaway." }
        if let range = trimmed.range(of: ". ") {
            let first = String(trimmed[..<range.lowerBound])
            if first.count >= 20 { return first + "." }
        }
        if trimmed.count > 200 {
            return String(trimmed.prefix(200)) + "..."
        }
        return trimmed
    }

    /// The scenario text: the opening of the explain, before the
    /// structured breakdown, so the question does not give the answer away.
    private var scenarioText: String {
        guard let today = todaysSituation else { return "" }
        let paragraphs = today.explain
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let opening = paragraphs.prefix(2).joined(separator: "\n\n")
        return opening.isEmpty ? today.explain : opening
    }

    private var alreadyCompletedToday: Bool {
        UserDefaults.standard.bool(forKey: Keys.completed(for: dayKey))
    }

    private var wasCorrectToday: Bool {
        UserDefaults.standard.bool(forKey: Keys.correct(for: dayKey))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                headerSection
                if contentService.searchIndex == nil && situations.isEmpty {
                    HStack(spacing: PFSpacing.sm) {
                        ProgressView()
                        Text("Loading today's challenge...")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    }
                } else if let today = todaysSituation {
                    challengeCard(situation: today)
                } else {
                    Text("Today's challenge is not available yet. Check your connection and try again.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
            }
            .padding(PFSpacing.lg)
        }
        // Copy protection: the challenge case cannot be selected, a
        // faint identity watermark sits over it, and recording blurs
        // it out.
        .pfProtectedContent()
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Daily Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if alreadyCompletedToday {
                answered = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("One real case, 3 to 5 minutes")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text("A new situation every day, the same one for every learner. Read the case, pick the key lesson, then check yourself against the situation's own takeaway.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if alreadyCompletedToday {
                PFPill(
                    text: wasCorrectToday ? "Completed today, correct" : "Completed today",
                    background: Color.pfSuccess.opacity(0.12),
                    foreground: .pfSuccess
                )
            }
        }
    }

    // MARK: - Challenge

    private func challengeCard(situation: Situation) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: situation.stageName)
                        PFPill(
                            text: situation.level.displayName,
                            background: Color.pfGoldSoft,
                            foreground: Color(red: 0.55, green: 0.44, blue: 0.08)
                        )
                        if let schemeName = scheme(for: situation) {
                            PFPill(text: schemeName)
                        }
                    }
                    Text(situation.title)
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(scenarioText)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("What is the key lesson here?")
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let isSelected = selectedOption == index
                let showResult = answered
                let border: Color = {
                    if showResult && option.isCorrect { return .pfSuccess }
                    if showResult && isSelected { return .pfError }
                    if isSelected { return .pfRoyal }
                    return .pfBorder
                }()
                Button {
                    guard !answered else { return }
                    selectedOption = index
                } label: {
                    HStack(alignment: .top, spacing: PFSpacing.sm) {
                        Image(systemName: showResult && option.isCorrect
                            ? "checkmark.circle.fill"
                            : showResult && isSelected ? "xmark.circle.fill"
                            : isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(showResult && option.isCorrect ? .pfSuccess
                                : showResult && isSelected ? .pfError
                                : isSelected ? .pfRoyal : .pfSecondaryText)
                            .padding(.top, 2)
                        Text(option.text)
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(PFSpacing.md)
                    .background(Color.pfCard)
                    .cornerRadius(PFSpacing.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                            .stroke(border, lineWidth: isSelected || (showResult && option.isCorrect) ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(answered)
            }
            if !answered {
                PFPrimaryButton(title: "Check my answer") {
                    guard let selectedOption else { return }
                    answered = true
                    let correct = options[selectedOption].isCorrect
                    UserDefaults.standard.set(true, forKey: Keys.completed(for: dayKey))
                    UserDefaults.standard.set(correct, forKey: Keys.correct(for: dayKey))
                }
                .disabled(selectedOption == nil)
                .opacity(selectedOption == nil ? 0.5 : 1)
            }
            if answered {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text(selectedOption.map { options[$0].isCorrect } == true
                            ? "Correct. That is the key lesson of this situation."
                            : "Not this time. Here is the situation's own takeaway.")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(situation.takeaway)
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        NavigationLink(destination: SituationDetailView(situation: situation)) {
                            Text("Open the full situation")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.pfRoyal)
                        }
                    }
                }
            }
        }
    }
}
