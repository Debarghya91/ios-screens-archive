// ContentModels.swift
// PaymentForge iOS - Data models for the learning content.
// Content is loaded from the live website so it stays current.
// No em dashes in any user-facing text.

import Foundation

// MARK: - Search index

/// One entry from the live search index
/// (https://www.paymentstraininghub.com/assets/search-index.json).
struct SearchEntry: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let type: SearchEntryType
    let text: String

    var isLesson: Bool { type == .lesson }
    var isGuide: Bool { type == .guide }
    var isSituation: Bool { type == .situation }
    var isLab: Bool { type == .lab }
    var isTest: Bool { type == .test }
    var isFAQ: Bool { type == .faq }

    /// A short preview of the entry text for search results.
    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 140 { return trimmed }
        return String(trimmed.prefix(140)) + "..."
    }

    /// True when this entry is a supplemental lesson written for v34
    /// to cover a CIPSP or Payment Guru syllabus topic that the
    /// website catalogue does not teach in depth. Supplemental lessons
    /// are bundled with the app, carry recorded narration, and their
    /// detail is built locally instead of fetched from the website.
    var isSupplemental: Bool {
        id.hasSuffix("-supp")
    }

    /// The audio file name for a lesson, for example "ch1s1.mp3".
    /// Supplemental lessons return their own file too: all 72 have
    /// recorded narration on the audio hosts.
    var audioFileName: String? {
        guard type == .lesson else { return nil }
        return id + ".mp3"
    }

    /// The chapter number from a lesson id (ch<N>s<M>), or nil.
    var chapterNumber: Int? {
        guard id.hasPrefix("ch") else { return nil }
        let digits = id.dropFirst(2).prefix(while: { $0.isNumber })
        return Int(digits)
    }

    /// The lesson number from a lesson id (ch<N>s<M>), or nil.
    var lessonNumber: Int? {
        guard id.hasPrefix("ch"), let sIndex = id.lastIndex(of: "s") else { return nil }
        let digits = id[id.index(after: sIndex)...].prefix(while: { $0.isNumber })
        guard !digits.isEmpty, Int(digits) != nil else { return nil }
        return Int(digits)
    }

    /// The citation naming where an entry sits in the book: the
    /// book chapter and lesson for lessons ("Chapter 26, Lesson 3:
    /// pacs.002 Explained"), the type and title for anything else
    /// ("Guide: camt.029 Explained", "Situation: ..."). Chapter
    /// numbers are always book numbers from
    /// PFBookModeReadingOrder, never internal chapter numbers. A
    /// held-out chapter has no book number, so its lessons cite
    /// the chapter name instead. Supplemental lessons (ids like
    /// ch54s901-supp) have no lesson number in the catalogue:
    /// their 901-style sequence is an authoring sequence, not a
    /// position in the chapter, so the citation names the chapter
    /// only ("Chapter 27: <title>") and never shows the 901 form.
    /// Callers with a ContentService should use its citation(for:),
    /// which numbers regular lessons by sequential position
    /// within the chapter in catalogue order; for the current
    /// catalogue the two agree, because every chapter's lesson
    /// numbers are sequential.
    var citation: String {
        if type == .lesson, let chapter = chapterNumber {
            if let book = PFBookModeReadingOrder.bookNumber(forInternalNumber: chapter) {
                if isSupplemental {
                    return "Chapter \(book): \(title)"
                }
                if let lesson = lessonNumber {
                    return "Chapter \(book), Lesson \(lesson): \(title)"
                }
            } else if let name = chapterName {
                return "\(name): \(title)"
            }
        }
        return "\(type.displayName): \(title)"
    }

    /// The catalogue text after the lesson title prefix, when the
    /// text starts with it.
    private var textAfterTitle: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, trimmed.hasPrefix(title) {
            return String(trimmed.dropFirst(title.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// The range of the section marker in the given text, or nil.
    /// The index text is a single line:
    /// `<lesson title> <chapter name> Part N: <domain> <body>`,
    /// with `Domain NN:` or `Stage N:` for newer lessons and a
    /// domain code (`D12`) for the ch86-95 block. The marker is the
    /// divider between the chapter name and the domain label.
    private static func sectionMarkerRange(in text: String) -> Range<String.Index>? {
        var best: Range<String.Index>? = nil
        let wordMarkers = [" Part ", " Domain ", " Stage "]
        for marker in wordMarkers {
            var from = text.startIndex
            while let r = text.range(of: marker, range: from..<text.endIndex) {
                let after = text[r.upperBound...]
                let digits = after.prefix(while: { $0.isNumber })
                if !digits.isEmpty, after.dropFirst(digits.count).hasPrefix(":") {
                    let end = text.index(after.startIndex, offsetBy: digits.count + 1)
                    let full = r.lowerBound..<end
                    if best == nil || full.lowerBound < best!.lowerBound { best = full }
                    break
                }
                from = r.upperBound
            }
        }
        // Domain-code marker: a space, "D", digits, a space.
        var from = text.startIndex
        while let r = text.range(of: " D", range: from..<text.endIndex) {
            let after = text[r.upperBound...]
            let digits = after.prefix(while: { $0.isNumber })
            if !digits.isEmpty, after.dropFirst(digits.count).hasPrefix(" ") {
                let end = text.index(after.startIndex, offsetBy: digits.count + 1)
                let full = r.lowerBound..<end
                if best == nil || full.lowerBound < best!.lowerBound { best = full }
                break
            }
            from = r.upperBound
        }
        return best
    }

    /// The chapter name: the text between the lesson title and the
    /// section marker. Nil when the text carries no marker.
    var chapterName: String? {
        let rest = textAfterTitle
        guard let marker = Self.sectionMarkerRange(in: rest) else { return nil }
        let name = String(rest[..<marker.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Domain labels used by the site, longest first, so the body
    /// strip matches the full label before a shorter prefix.
    private static let domainLabels: [String] = [
        "AI Product Owner and Product Manager for Payments",
        "System Design and Real Banks",
        "Domestic Payment Systems",
        "Compliance, Risk and Fraud",
        "BA Workshop and Capstone",
        "Cross-Border Payments",
        "Clearing and Settlement",
        "Technology and APIs",
        "Payments in Practice",
        "Payment Architecture",
        "Payment Operations",
        "Professional Masterclass",
        "Emerging Technologies",
        "APIs and Integration",
        "Global Payment Rails",
        "Card and Paper Payments",
        "Compliance and Risk",
        "Messaging Standards",
        "Messaging and rails",
        "Clearing, cards and liquidity",
        "Architecture, APIs and operations",
        "Risk, product, practice and emerging",
        "Risk, compliance and regulation",
        "Accounts, ledger and accounting",
        "Emerging Topics",
        "Foundations",
        "Cards"
    ]

    /// The lesson body: the entry text with the lesson title
    /// (stripped as many times as it leads the text, because some
    /// guide entries carry it twice), the chapter name, the section
    /// marker and the domain label removed, so the text starts with
    /// the actual lesson content.
    var bodyText: String {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            while rest.hasPrefix(title) {
                rest = String(rest.dropFirst(title.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let marker = Self.sectionMarkerRange(in: rest) {
            rest = String(rest[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for domain in Self.domainLabels {
            if rest.hasPrefix(domain) {
                rest = String(rest.dropFirst(domain.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return rest
    }
}

enum SearchEntryType: String, Codable, Hashable {
    case lesson
    case guide
    case situation
    case lab
    case test
    case faq

    var displayName: String {
        switch self {
        case .lesson: return "Lesson"
        case .guide: return "Guide"
        case .situation: return "Situation"
        case .lab: return "Lab"
        case .test: return "Test"
        case .faq: return "FAQ"
        }
    }
}

/// The search index document, with per-type counts and all entries.
struct SearchIndex: Codable {
    let counts: SearchCounts
    let entries: [SearchEntry]
}

struct SearchCounts: Codable {
    let lesson: Int
    let guide: Int
    let situation: Int
    let lab: Int
    let test: Int
    let faq: Int
    let total: Int
}

// MARK: - Chapters and domains

/// A chapter in the curriculum. Chapters are grouped into domains.
/// The site has ContentManifest.chapterCount chapters across ContentManifest.domainCount domains.
struct Chapter: Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let domain: String
    let lessonCount: Int
    let lessonIDs: [String]
}

/// A domain grouping chapters. The site has ContentManifest.domainCount domains.
struct Domain: Identifiable, Hashable {
    let id: String
    let name: String
    let chapters: [Chapter]

    var lessonCount: Int {
        chapters.reduce(0) { $0 + $1.lessonCount }
    }
}

// MARK: - Lesson detail

/// One timed beat of a lesson: a section of the narration with a title
/// and a short note. Times are seconds into the lesson narration audio.
/// The lesson diagram highlights the beat that matches the current
/// playback time.
struct LessonBeat: Identifiable, Hashable {
    let id: String
    let startTime: Double
    let endTime: Double
    let title: String
    let note: String
}

/// The full content of one lesson, loaded from the live lesson page.
struct LessonDetail: Identifiable {
    let id: String
    let title: String
    let chapterTitle: String
    let audioFileName: String
    /// The full narration text (transcript).
    let transcript: String
    /// Exactly three key takeaways shown on the lesson page.
    let takeaways: [String]
    /// The "Do this at work" checklist items.
    let doThisAtWork: [String]
    /// Source footnotes, official sources only.
    let sources: [String]
    /// The three auto-graded quiz questions for this lesson.
    let quiz: [QuizQuestion]
    /// The next lesson in the chapter, if any.
    let nextLessonID: String?
    /// The timed beats of the lesson narration, in playback order.
    /// Beat times are seconds into the narration audio, with later
    /// scenes offset by the duration of the earlier scenes.
    let beats: [LessonBeat]
    /// The lesson diagram SVG from the lesson page, if the lesson has one.
    let diagramSVG: String?
    /// Total narration length in seconds, summed across scenes.
    let durationSec: Double
    /// The title of the next lesson, if the page names one.
    let nextLessonTitle: String?
    /// The quiz intro line from the lesson page.
    let quizIntro: String
}

/// One auto-graded quiz question.
struct QuizQuestion: Identifiable, Hashable {
    let id: String
    let question: String
    let options: [String]
    let correctOptionIndex: Int
    let explanation: String
}

// MARK: - Situations

/// A Payment Situation. The site has ContentManifest.situationCount, across 6 learning stages
/// and 3 levels (foundation, core, advanced). The full case (full
/// explain text and visual) comes from the live situations data file;
/// the search index carries only a short excerpt, so a Situation built
/// from the index has no visual.
struct Situation: Identifiable, Hashable {
    let id: String
    let title: String
    let stage: Int
    let stageName: String
    let level: SituationLevel
    let explain: String
    let takeaway: String
    let isFreeSample: Bool
    /// The situation visual (flow, diagram or stacked), when the full
    /// data file supplied one. Nil for index-only situations.
    let visual: SituationVisual?
    /// True when `stage` and `stageName` came from the live situations
    /// data file itself (its `stage` and `stage_name` fields), which
    /// is authoritative. False when the stage was derived (from the
    /// website stage map, from the level fallback, or from a text
    /// hint in the search index entry). Derived stages are never
    /// presented as authoritative.
    let isStageAuthoritative: Bool

    init(
        id: String,
        title: String,
        stage: Int,
        stageName: String,
        level: SituationLevel,
        explain: String,
        takeaway: String,
        isFreeSample: Bool,
        visual: SituationVisual?,
        isStageAuthoritative: Bool = false
    ) {
        self.id = id
        self.title = title
        self.stage = stage
        self.stageName = stageName
        self.level = level
        self.explain = explain
        self.takeaway = takeaway
        self.isFreeSample = isFreeSample
        self.visual = visual
        self.isStageAuthoritative = isStageAuthoritative
    }
}

/// The visual for one situation, as shipped in the live situations
/// data file. Only the branch matching `type` is present.
struct SituationVisual: Codable, Hashable {
    let type: String
    let flow: SituationFlow?
    let diagram: SituationDiagram?
    let stacked: SituationStacked?

    enum CodingKeys: String, CodingKey {
        case type, flow, diagram, stacked
    }
}

/// A flow visual: ordered steps, each a step or a decision.
struct SituationFlow: Codable, Hashable {
    let stepSeconds: Double?
    let steps: [SituationFlowStep]

    enum CodingKeys: String, CodingKey {
        case stepSeconds, steps
    }
}

struct SituationFlowStep: Codable, Hashable {
    /// "step" or "decision". Anything else renders as a plain step.
    let kind: String?
    let title: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case kind, title, note
    }
}

/// A labelled diagram: one centre box with its parts below it.
struct SituationDiagram: Codable, Hashable {
    let centre: String
    let parts: [SituationDiagramPart]

    enum CodingKeys: String, CodingKey {
        case centre, parts
    }
}

struct SituationDiagramPart: Codable, Hashable {
    let label: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case label, note
    }
}

/// A stacked comparison: segments sized by value, normalised to 100.
struct SituationStacked: Codable, Hashable {
    let segments: [SituationStackedSegment]
    let unit: String?

    enum CodingKeys: String, CodingKey {
        case segments, unit
    }
}

struct SituationStackedSegment: Codable, Hashable {
    let label: String
    let note: String?
    let value: Double

    enum CodingKeys: String, CodingKey {
        case label, note, value
    }
}

/// One full situation as shipped in the live situations data file
/// (window.PA_SITUATIONS). The source name and source URL are
/// deliberately not decoded: they are never shown in learner UI.
///
/// AUTHORITATIVE METADATA (verified 11 Nov 2026 against the live
/// file, all ContentManifest.situationCount items): every item carries `stage` (an integer,
/// 1 to 6) and `stage_name` (the matching stage name), plus `level`,
/// `module` and `domain`. Those fields are read directly where they
/// are present. `stage` is decoded flexibly (integer, or a string
/// holding an integer) so a future format change cannot break the
/// whole decode. Where a field is absent, ContentService falls back
/// to the website stage map and then to the level, and the result is
/// marked derived, never authoritative.
struct FullSituationItem: Decodable {
    let id: String
    let title: String
    let level: String
    let module: String?
    let seq: Int?
    let explain: String
    let takeaway: String
    let visual: SituationVisual?
    /// Authoritative stage from the data file, 1 to 6. Nil when the
    /// item carries no usable stage field.
    let stage: Int?
    /// Authoritative stage name from the data file. Nil when absent.
    let stageName: String?
    /// Curriculum domain string from the data file, when present.
    /// Informational only; no chapter mapping is derived from it.
    let domain: String?
    /// Message codes named in the data file for this item, when the
    /// stage-map join supplied them. Read by the investigation
    /// engine; absent items fall back to codes found in the text.
    let messages: [String]?
    /// Failure category from the data file, when present. Read by
    /// the investigation engine for severity, impact, and
    /// hypothesis templates.
    let failureCategory: String?
    /// Resolution path from the data file, when present. Read by
    /// the investigation engine for the closing decision note.
    let resolution: String?

    enum CodingKeys: String, CodingKey {
        case id, title, level, module, seq, explain, takeaway, visual
        case stage
        case stageName = "stage_name"
        case domain
        case messages
        case failureCategory = "failure_category"
        case resolution
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        level = try container.decode(String.self, forKey: .level)
        module = try container.decodeIfPresent(String.self, forKey: .module)
        seq = try container.decodeIfPresent(Int.self, forKey: .seq)
        explain = try container.decode(String.self, forKey: .explain)
        takeaway = try container.decode(String.self, forKey: .takeaway)
        visual = try container.decodeIfPresent(SituationVisual.self, forKey: .visual)
        stageName = try container.decodeIfPresent(String.self, forKey: .stageName)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
        messages = try container.decodeIfPresent([String].self, forKey: .messages)
        failureCategory = try container.decodeIfPresent(String.self, forKey: .failureCategory)
        resolution = try container.decodeIfPresent(String.self, forKey: .resolution)
        if let intStage = try? container.decodeIfPresent(Int.self, forKey: .stage) {
            stage = intStage
        } else if let stringStage = try? container.decodeIfPresent(String.self, forKey: .stage),
                  let value = Int(stringStage.trimmingCharacters(in: .whitespaces)) {
            stage = value
        } else {
            stage = nil
        }
    }
}

enum SituationLevel: String, Codable, Hashable {
    case foundation
    case core
    case advanced

    var displayName: String {
        switch self {
        case .foundation: return "Foundation"
        case .core: return "Core"
        case .advanced: return "Advanced"
        }
    }
}

// MARK: - Guided path

/// One session of the 8-session guided path.
struct GuidedSession: Identifiable, Hashable {
    let id: Int
    let title: String
    let description: String
    let chapterIDs: [String]
}

// MARK: - Dashboard

/// A learner's weekly goal.
struct WeeklyGoal: Codable, Hashable {
    var targetLessonsPerWeek: Int = 5
}
