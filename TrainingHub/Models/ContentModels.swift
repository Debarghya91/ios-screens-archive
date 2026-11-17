// ContentModels.swift
// Payments Training Hub iOS - Data models for the learning content.
// Content is loaded from the live website so it stays current.
// No em dashes in any user-facing text.

import Foundation

// MARK: - Search index

/// One entry from the live search index
/// (https://www.paymentstraininghub.com/assets/search-index.json).
/// The compact index
/// (https://www.paymentstraininghub.com/assets/search-index-compact.json)
/// carries the same document shape but a slimmer entry: lessons
/// and situations carry tags and an excerpt instead of the full
/// text, plus the chapter name and domain label when known.
/// Decoding accepts both shapes: text defaults to empty, tags
/// default to empty, and the rest default to nil.
struct SearchEntry: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let type: SearchEntryType
    let text: String
    /// The agenda for this entry ("why take it"), when the website
    /// exposes one. Optional: entries without it show no agenda
    /// block, never a placeholder. Defaults to nil so existing
    /// memberwise construction in tests keeps compiling.
    let agenda: String? = nil
    /// The thumbnail path for this entry, relative to the site
    /// root (for example "assets/thumbs/ch1s1.svg"), when the
    /// website exposes one. Optional: entries without it show the
    /// standard icon tile, never a broken image. Resolve with
    /// PFThumbnailURL, which prepends the site base URL.
    let thumbnail: String? = nil
    /// Keywords for this entry, from the compact index. Empty for
    /// full-index entries and for types the compact index keeps
    /// whole (guides, labs, tests, FAQs).
    let tags: [String] = []
    /// A short excerpt of the entry text, from the compact index,
    /// for entries that carry no full text. Nil otherwise.
    let excerpt: String? = nil
    /// The chapter name, from the compact index, for lessons that
    /// carry it. Nil otherwise: the name is then parsed from the
    /// text, as before.
    let chapter: String? = nil
    /// The domain label, from the compact index, for lessons that
    /// carry it. Nil otherwise.
    let domain: String? = nil

    /// Explicit init: the memberwise form takes only the five
    /// properties without defaults on this toolchain, so the
    /// agenda join's eleven-argument construction failed. The
    /// six optional parameters default exactly as the stored
    /// properties do, so five-argument construction in tests
    /// keeps working unchanged.
    init(
        id: String,
        title: String,
        url: String,
        type: SearchEntryType,
        text: String,
        agenda: String? = nil,
        thumbnail: String? = nil,
        tags: [String] = [],
        excerpt: String? = nil,
        chapter: String? = nil,
        domain: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.type = type
        self.text = text
        self.agenda = agenda
        self.thumbnail = thumbnail
        self.tags = tags
        self.excerpt = excerpt
        self.chapter = chapter
        self.domain = domain
    }

    var isLesson: Bool { type == .lesson }
    var isGuide: Bool { type == .guide }
    var isSituation: Bool { type == .situation }
    var isLab: Bool { type == .lab }
    var isTest: Bool { type == .test }
    var isFAQ: Bool { type == .faq }

    /// A short preview of the entry text for search results.
    /// Compact-index entries carry no full text, so the excerpt
    /// stands in when the text is blank. Truncated at 140
    /// characters either way, so rows stay one height.
    var preview: String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = source.isEmpty
            ? (excerpt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            : source
        if trimmed.count <= 140 { return trimmed }
        return String(trimmed.prefix(140)) + "..."
    }

    /// The text search matches against: the full text when
    /// present, plus the tags and the excerpt, so compact-index
    /// entries (which carry no full text) still match on their
    /// tags and excerpt. SearchService uses this as the body
    /// haystack; title matching is separate and still outranks it.
    var searchText: String {
        var parts: [String] = []
        if !text.isEmpty { parts.append(text) }
        if !tags.isEmpty { parts.append(tags.joined(separator: " ")) }
        if let excerpt, !excerpt.isEmpty { parts.append(excerpt) }
        return parts.joined(separator: " ")
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

    /// The citation naming where an entry sits in the full course: the
    /// course chapter and lesson for lessons ("Chapter 26, Lesson 3:
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

    /// The chapter name: the compact index's chapter field when
    /// present, else the text between the lesson title and the
    /// section marker. Nil when neither carries a name.
    var chapterName: String? {
        if let chapter {
            let name = chapter.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
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

// MARK: - SearchEntry decoding

/// Custom decoding, in an extension so the memberwise initializer
/// keeps working for tests and for the agenda join. The full index
/// and the compact index decode through the same init: text is
/// optional (compact entries omit it), tags default to empty, and
/// excerpt, chapter and domain default to nil. A missing id, title,
/// url or type still fails the decode, as before.
extension SearchEntry {
    private enum CodingKeys: String, CodingKey {
        case id, title, url, type, text, agenda, thumbnail, tags, excerpt, chapter, domain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(String.self, forKey: .url)
        type = try container.decode(SearchEntryType.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        agenda = try container.decodeIfPresent(String.self, forKey: .agenda)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
        chapter = try container.decodeIfPresent(String.self, forKey: .chapter)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
    }
}

// MARK: - Thumbnails

/// Resolves a thumbnail path from website data into a loadable URL.
/// Relative paths ("assets/thumbs/ch1s1.svg", with or without a
/// leading slash) resolve against the site base URL passed by the
/// caller (ContentService.siteBase, the single source for the site
/// address). Absolute URLs pass through unchanged. Nil, blank, and
/// unparseable values resolve to nil: the caller shows the standard
/// icon tile instead, never a broken image. Pure logic, covered by
/// unit tests.
enum PFThumbnailURL {
    static func resolve(_ path: String?, base: URL) -> URL? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme == "http" || absolute.scheme == "https" {
            return absolute
        }
        let relative = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        return base.appendingPathComponent(relative)
    }

    /// True when the thumbnail at this URL is an SVG, which
    /// AsyncImage cannot render: SVG thumbnails render through the
    /// WebKit path in PFThumbnailView instead. The query string is
    /// ignored, so "thumb.svg?v=2" still counts as SVG.
    static func isSVG(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "svg"
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

// MARK: - Agendas and thumbnails

/// One agenda and thumbnail pair from the agendas document.
/// Both fields are optional: a missing or blank field means the
/// caller shows no agenda block or keeps its icon tile, never a
/// placeholder and never a broken image.
struct AgendaEntry: Decodable, Hashable {
    /// The agenda ("why take it") text.
    let agenda: String?
    /// The thumbnail path, relative to the site root (for example
    /// "assets/thumbs/ch1s1.svg"). Resolve with PFThumbnailURL.
    let thumbnail: String?
}

/// The agendas document
/// (https://www.paymentstraininghub.com/assets/agendas.json):
/// the agenda and thumbnail for every lesson, chapter, and course.
/// Key scheme, verified against the deployed file and the app's own
/// ids: lessons keyed by search-index lesson id ("ch1s1"), chapters
/// by chapter id ("ch1" to "ch100"), courses by catalogue bundle id
/// ("integrated", "part-1" to "part-10"). Each map defaults to
/// empty when the file omits it, so a partial document degrades to
/// missing agendas, never a failed decode. The file's `cases` map
/// is intentionally not decoded here: case agendas and thumbnails
/// flow through the situations data file, and that path is untouched.
struct AgendasDocument: Decodable {
    let lessons: [String: AgendaEntry] = [:]
    let chapters: [String: AgendaEntry] = [:]
    let courses: [String: AgendaEntry] = [:]
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
    /// The agenda for this case ("why this case matters"), when the
    /// website exposes one. Optional: cases without it show no
    /// agenda block, never a placeholder.
    let agenda: String?
    /// The thumbnail path for this case, relative to the site root,
    /// when the website exposes one. Resolve with PFThumbnailURL.
    /// Optional: cases without it show the standard case tile.
    let thumbnail: String?

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
        isStageAuthoritative: Bool = false,
        agenda: String? = nil,
        thumbnail: String? = nil
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
        self.agenda = agenda
        self.thumbnail = thumbnail
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
/// are present. `stage` and `seq` are decoded flexibly (integer,
/// or a string holding an integer): the chunked detail files carry
/// both as strings, while the full data file carries both as
/// integers, and either shape must decode. Where a field is absent,
/// ContentService falls back to the website stage map and then to
/// the level, and the result is marked derived, never authoritative.
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
    /// Agenda ("why this case matters") from the data file, when
    /// the website exposes it. Optional: absent means no agenda
    /// block, never a placeholder.
    let agenda: String?
    /// Thumbnail path, relative to the site root, from the data
    /// file, when the website exposes it. Optional: absent means
    /// the standard case tile.
    let thumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id, title, level, module, seq, explain, takeaway, visual
        case stage
        case stageName = "stage_name"
        case domain
        case messages
        case failureCategory = "failure_category"
        case resolution
        case agenda
        case thumbnail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        level = try container.decode(String.self, forKey: .level)
        module = try container.decodeIfPresent(String.self, forKey: .module)
        if let intSeq = try? container.decodeIfPresent(Int.self, forKey: .seq) {
            seq = intSeq
        } else if let stringSeq = try? container.decodeIfPresent(String.self, forKey: .seq),
                  let value = Int(stringSeq.trimmingCharacters(in: .whitespaces)) {
            seq = value
        } else {
            seq = nil
        }
        explain = try container.decode(String.self, forKey: .explain)
        takeaway = try container.decode(String.self, forKey: .takeaway)
        visual = try container.decodeIfPresent(SituationVisual.self, forKey: .visual)
        stageName = try container.decodeIfPresent(String.self, forKey: .stageName)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
        messages = try container.decodeIfPresent([String].self, forKey: .messages)
        failureCategory = try container.decodeIfPresent(String.self, forKey: .failureCategory)
        resolution = try container.decodeIfPresent(String.self, forKey: .resolution)
        agenda = try container.decodeIfPresent(String.self, forKey: .agenda)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
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

// MARK: - Situations index (paged list)

/// One row of the compact situations index
/// (https://www.paymentstraininghub.com/assets/situations-index.json).
/// The list renders from these rows alone, so the full situations
/// file is never downloaded just to show the list. `stage` is
/// decoded flexibly (integer, or a string holding an integer), the
/// same way FullSituationItem decodes it. `chunk` names the detail
/// chunk file holding the full item, or is nil when the row came
/// from a source without chunking.
struct SituationsIndexEntry: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let level: String
    let stage: Int?
    let stageName: String?
    let domain: String?
    let chunk: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, level, stage, domain, chunk
        case stageName = "stage_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        level = try container.decode(String.self, forKey: .level)
        stageName = try container.decodeIfPresent(String.self, forKey: .stageName)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
        chunk = try container.decodeIfPresent(Int.self, forKey: .chunk)
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

/// The compact situations index document: the total count, the
/// chunk size the detail files were split at, and one row per case.
/// The chunk size is informational: chunk file names come from
/// each row's `chunk` field, never from arithmetic on the row
/// position.
struct SituationsIndexDoc: Decodable {
    let total: Int
    let chunkSize: Int
    let items: [SituationsIndexEntry]

    enum CodingKeys: String, CodingKey {
        case total, items
        case chunkSize = "chunkSize"
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

// MARK: - Entry access rules

/// The access rules for search-index entries shown in full text:
/// the SearchEntrySheet in Search and the FAQ answers in Help and
/// Support. Titles stay visible everywhere (discovery); only the
/// full text locks. Pure logic, covered by unit tests.
///
/// FAQ answers belong to Interview Ready: the first 5 in catalogue
/// order are free samples. Labs belong to Practice Experiences:
/// the first 2 in catalogue order are free samples. Tests belong
/// to their chapter's part: a test locks when its chapter is
/// locked, and a test with no chapter number stays open
/// (diagnostic and placement tests are free). Lessons and
/// situations never reach the sheet: they open LessonView and the
/// situation detail, which carry their own gates. Guides are
/// intentionally ungated: their product home is undecided (only
/// the 5 Studio career guides map to a product), so no mapping is
/// invented here.
enum EntryAccessRules {

    /// True when this entry's full text is locked.
    /// - Parameters:
    ///   - entry: the entry being opened.
    ///   - indexInType: the entry's 0-based position among entries
    ///     of its type in catalogue order, or nil when it is not
    ///     in the loaded list (fail closed for FAQ and lab).
    ///   - isPracticeUnlocked: Practice Experiences entitlement.
    ///   - isInterviewUnlocked: Interview Ready entitlement.
    ///   - isChapterUnlocked: whether the entry's chapter is
    ///     unlocked; pass true for a test with no chapter number.
    static func isLocked(
        _ entry: SearchEntry,
        indexInType: Int?,
        isPracticeUnlocked: Bool,
        isInterviewUnlocked: Bool,
        isChapterUnlocked: Bool
    ) -> Bool {
        switch entry.type {
        case .faq:
            if isInterviewUnlocked { return false }
            guard let index = indexInType else { return true }
            return index >= FreeSampleRules.faqFreeCount
        case .lab:
            if isPracticeUnlocked { return false }
            guard let index = indexInType else { return true }
            return index >= FreeSampleRules.labFreeCount
        case .test:
            return !isChapterUnlocked
        case .lesson, .situation, .guide:
            return false
        }
    }

    /// The product that unlocks this entry, for lock copy. Nil for
    /// entry types that never lock. For a test, the caller passes
    /// the chapter's unlocking product ID, or nil when the chapter
    /// is unknown: the Integrated Course is the fallback, because
    /// it unlocks every chapter.
    static func unlockingProductID(for entry: SearchEntry, chapterUnlockingProductID: String?) -> String? {
        switch entry.type {
        case .faq:
            return ProductCatalogue.interviewProductID
        case .lab:
            return ProductCatalogue.practiceProductID
        case .test:
            return chapterUnlockingProductID ?? ProductCatalogue.integratedProductID
        case .lesson, .situation, .guide:
            return nil
        }
    }
}
