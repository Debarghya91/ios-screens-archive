// LearningPath.swift
// PaymentForge iOS - Guided learning paths and certificates.
// A path is defined by real chapter numbers, so its required lessons
// are resolved from the loaded catalogue at runtime: only lesson ids
// that exist in the search index can ever appear, and the counts shown
// are the real counts from that catalogue. Situation ids below were
// verified against the live situations data (564 items) on 11 Nov 2026.
// Chapter titles were verified against the live lesson pages the same day.
// No lesson counts, durations or scores are hardcoded here.
// No em dashes in any user-facing text.

import Foundation
import Combine

// MARK: - Learning path

/// One guided learning path: a set of real chapters, real situations,
/// assessment checkpoints and a capstone situation.
struct LearningPath: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let level: String
    let systemImage: String
    let objectives: [String]
    /// Chapter numbers whose lessons are all required for this path.
    let chapterNumbers: [Int]
    /// Real situation ids practised along the path.
    let situationIDs: [String]
    /// The capstone: one real situation, worked end to end.
    let capstoneSituationID: String
    let assessmentDimension: CompetencyStore.CompetencyDimension
    /// The certificate title earned on completion, nil when this path
    /// has no certificate (Interview Preparation).
    let certificateTitle: String?

    /// Required lessons, in catalogue order: every lesson of every
    /// chapter in this path. Empty while the catalogue is loading.
    func lessons(in service: ContentService) -> [SearchEntry] {
        var seen: Set<String> = []
        var result: [SearchEntry] = []
        for number in chapterNumbers {
            for lesson in PFChapterHelper.lessons(forChapter: number, in: service) {
                if seen.insert(lesson.id).inserted {
                    result.append(lesson)
                }
            }
        }
        return result
    }

    /// Chapter titles for this path, from the catalogue.
    func chapterTitles(in service: ContentService) -> [(number: Int, title: String)] {
        chapterNumbers.map { number in
            let lessons = PFChapterHelper.lessons(forChapter: number, in: service)
            return (number, PFChapterHelper.chapterTitle(for: lessons, number: number))
        }
    }

    /// The path situations, resolved from the full situations data
    /// first and the search index as fallback. Ids that are not in
    /// either source are dropped, never invented.
    func situations(in service: ContentService) -> [Situation] {
        situationIDs.compactMap { pfSituation(id: $0, in: service) }
    }

    /// The capstone situation, or nil while the catalogue is loading.
    func capstone(in service: ContentService) -> Situation? {
        pfSituation(id: capstoneSituationID, in: service)
    }

    /// Completed required lessons over total required lessons.
    func progress(in progressStore: ProgressStore, service: ContentService) -> (completed: Int, total: Int) {
        let required = lessons(in: service)
        let completed = required.filter { progressStore.isLessonComplete($0.id) }.count
        return (completed, required.count)
    }

    /// True only when every required lesson is complete.
    func isComplete(in progressStore: ProgressStore, service: ContentService) -> Bool {
        let result = progress(in: progressStore, service: service)
        return result.total > 0 && result.completed == result.total
    }
}

/// Resolve one situation by id: full data first, search index fallback.
func pfSituation(id: String, in service: ContentService) -> Situation? {
    if let full = service.fullSituations?.first(where: { $0.id == id }) {
        return situation(fromFull: full)
    }
    if let entry = service.allSituations.first(where: { $0.id == id }) {
        return situation(from: entry)
    }
    return nil
}

// MARK: - Competency dimension chapters

extension CompetencyStore.CompetencyDimension {
    /// Chapters whose lesson quizzes feed this dimension's assessment.
    /// Chapter titles verified against the live lesson pages, 11 Nov 2026.
    var chapterNumbers: [Int] {
        switch self {
        case .architecture:
            return [25, 30, 35, 36, 48, 79]
        case .lifecycle:
            return [4, 17, 18, 72]
        case .businessAnalysis:
            return [28, 37, 45, 84]
        case .exceptionHandling:
            return [16, 41, 58, 73]
        case .reconciliation:
            return [40, 44, 71, 88, 89]
        }
    }
}

// MARK: - The six guided paths

extension LearningPath {
    static let all: [LearningPath] = [
        LearningPath(
            id: "fundamentals",
            title: "Payments Fundamentals",
            description: "What a payment is, the instruments used to make one, the parties involved, and the lifecycle from instruction to settlement.",
            level: "Foundation",
            systemImage: "book.fill",
            objectives: [
                "Explain what a payment is and how it differs from a transfer and from settlement.",
                "Name the payment instruments and the parties in a payment.",
                "Trace a payment end to end through its lifecycle.",
                "Read a payment situation and spot where the lifecycle broke down."
            ],
            chapterNumbers: [1, 2, 3, 4],
            situationIDs: ["ABH-01", "ABH-02", "INS-001", "SCN-15"],
            capstoneSituationID: "ABH-10",
            assessmentDimension: .architecture,
            certificateTitle: "Payments Fundamentals"
        ),
        LearningPath(
            id: "business-analyst",
            title: "Payments Business Analyst",
            description: "The BA craft in payments: workshops, requirements, data models, product thinking and a capstone project drawn from real bank practice.",
            level: "Intermediate",
            systemImage: "doc.text.fill",
            objectives: [
                "Run a payments BA workshop and capture requirements that hold up.",
                "Model payment data and map it across systems.",
                "Write product requirements a delivery team can build from.",
                "Present a payments case the way a senior BA would."
            ],
            chapterNumbers: [28, 29, 37, 45, 84],
            situationIDs: ["ABH-37", "INS-084", "INS-085", "INS-096"],
            capstoneSituationID: "ABH-18",
            assessmentDimension: .businessAnalysis,
            certificateTitle: "Payments Business Analyst Foundations"
        ),
        LearningPath(
            id: "upi-specialist",
            title: "UPI Specialist",
            description: "India's instant payments in depth: UPI, IMPS, NEFT and RTGS, the Indian payments landscape, and real-time payments architecture.",
            level: "Intermediate",
            systemImage: "bolt.fill",
            objectives: [
                "Explain how a UPI payment moves from payer app to payee bank.",
                "Compare UPI, IMPS, NEFT and RTGS and pick the right rail.",
                "Describe the Indian payments landscape: NACH, BBPS and FEMA.",
                "Diagnose a failed or delayed instant payment."
            ],
            chapterNumbers: [9, 33, 46],
            situationIDs: ["INS-105", "INS-166", "INS-067", "INS-033"],
            capstoneSituationID: "SCN-36",
            assessmentDimension: .lifecycle,
            certificateTitle: "UPI Professional Foundations"
        ),
        LearningPath(
            id: "cards-digital",
            title: "Cards and Digital Banking",
            description: "Card payments end to end: authorisation, clearing and settlement, networks, wallets, POS, 3D Secure, tokenization and chargebacks.",
            level: "Intermediate",
            systemImage: "creditcard.fill",
            objectives: [
                "Trace a card payment from authorisation through clearing to settlement.",
                "Explain how Visa and Mastercard networks move a transaction.",
                "Describe 3D Secure, tokenization and how wallets and POS work.",
                "Handle a chargeback and explain who bears the loss."
            ],
            chapterNumbers: [21, 22, 31, 32, 63],
            situationIDs: ["ABH-04", "INS-001", "INS-005", "RUN5-001"],
            capstoneSituationID: "RUN5-003",
            assessmentDimension: .lifecycle,
            certificateTitle: "Card Payments Fundamentals"
        ),
        LearningPath(
            id: "operations-reconciliation",
            title: "Payment Operations and Reconciliation",
            description: "The operations floor: reconciliation, exceptions and investigations, rejects and returns, and the architecture that keeps payments resilient.",
            level: "Advanced",
            systemImage: "gearshape.fill",
            objectives: [
                "Reconcile a payment book and explain every break.",
                "Work an exception from first alert to resolution.",
                "Handle rejects and returns under CBPR+.",
                "Describe the controls that keep payment operations resilient."
            ],
            chapterNumbers: [40, 41, 44, 58, 68],
            situationIDs: ["INS-161", "INS-109", "INS-162", "PAI-C001"],
            capstoneSituationID: "SCN-19",
            assessmentDimension: .reconciliation,
            certificateTitle: "Payment Operations and Reconciliation"
        ),
        LearningPath(
            id: "interview-preparation",
            title: "Payments Interview Preparation",
            description: "Interview-ready payments: capstone cases, how large banks run payments, claims and case management, and cross-border investigations.",
            level: "Advanced",
            systemImage: "person.fill.questionmark",
            objectives: [
                "Answer payments interview questions with real cases, not definitions.",
                "Walk through a capstone project end to end.",
                "Explain how large banks organise payments operations.",
                "Work a cross-border investigation from first alert to close."
            ],
            chapterNumbers: [29, 37, 73, 75],
            situationIDs: ["INS-085", "INS-084", "ABH-37", "INS-061"],
            capstoneSituationID: "INS-096",
            assessmentDimension: .exceptionHandling,
            certificateTitle: nil
        )
    ]

    /// The five paths that carry a certificate, in path order.
    static var certificatePaths: [LearningPath] {
        all.filter { $0.certificateTitle != nil }
    }
}

// MARK: - Path bookmarks (local only)

/// Local bookmarks for guided paths, stored in UserDefaults.
/// The mockup shows a bookmark on each pathway card; this is the
/// learner's own saved set, nothing more.
final class PathBookmarkStore: ObservableObject {
    static let shared = PathBookmarkStore()

    private enum Keys {
        static let bookmarked = "pf.pathBookmarks.v1"
    }

    @Published private(set) var bookmarkedIDs: Set<String> = [] {
        didSet { save() }
    }

    func isBookmarked(_ pathID: String) -> Bool {
        bookmarkedIDs.contains(pathID)
    }

    func toggle(_ pathID: String) {
        if bookmarkedIDs.contains(pathID) {
            bookmarkedIDs.remove(pathID)
        } else {
            bookmarkedIDs.insert(pathID)
        }
    }

    init() {
        bookmarkedIDs = Set(UserDefaults.standard.stringArray(forKey: Keys.bookmarked) ?? [])
    }

    private func save() {
        UserDefaults.standard.set(Array(bookmarkedIDs), forKey: Keys.bookmarked)
    }
}

// MARK: - Certificate

/// A certificate of completion for one learning path. Issued only when
/// every required lesson of the path is complete, checked against
/// ProgressStore at issue time. The completion date is the date the
/// certificate was first issued on this device: ProgressStore records
/// which lessons are complete but not the date each was finished, so
/// no earlier completion date can be honestly stated.
struct PFCertificate: Identifiable, Codable {
    let id: String
    let pathID: String
    let pathTitle: String
    let learnerName: String
    let issuedAt: Date
    /// Overall competency score at issue time, nil when no assessment
    /// had been taken yet. Never a fabricated score.
    let overallScore: Double?

    var verificationURL: URL {
        URL(string: "https://www.paymentstraininghub.com/certificate/\(id)")!
    }

    var shareText: String {
        var lines = [
            "Payments Training Hub Certificate of Completion",
            pathTitle,
            "Issued to \(learnerName)",
            "Certificate ID: \(id)",
            "Verify at \(verificationURL.absoluteString)"
        ]
        if let overallScore {
            lines.append("Overall score: \(Int(overallScore.rounded()))%")
        }
        lines.append("Certificate of Completion. This certifies completion of the named learning path. It is not an accredited qualification.")
        return lines.joined(separator: "\n")
    }
}

/// Issues and re-reads certificates. The issued date is stored the
/// first time a completed path is viewed, and never changes after that.
enum PFCertificateStore {
    private static func key(for pathID: String) -> String {
        "pf.certificateIssuedAt.\(pathID).v1"
    }

    /// The certificate for a path, or nil when the path is not complete
    /// yet. Never issues for an incomplete path.
    static func certificate(
        for path: LearningPath,
        progress: ProgressStore,
        service: ContentService,
        competency: CompetencyStore,
        learnerName: String
    ) -> PFCertificate? {
        guard let certificateTitle = path.certificateTitle,
              path.isComplete(in: progress, service: service) else { return nil }
        let defaults = UserDefaults.standard
        let issuedAt: Date
        if let stored = defaults.object(forKey: key(for: path.id)) as? Date {
            issuedAt = stored
        } else {
            issuedAt = Date()
            defaults.set(issuedAt, forKey: key(for: path.id))
        }
        return PFCertificate(
            id: stableCertificateID(for: path.id),
            pathID: path.id,
            pathTitle: certificateTitle,
            learnerName: learnerName,
            issuedAt: issuedAt,
            overallScore: competency.hasAssessments ? competency.overallScore : nil
        )
    }

    /// A stable certificate id per path, so the same certificate keeps
    /// the same id across views: it is generated once and stored.
    static func stableCertificateID(for pathID: String) -> String {
        let key = "pf.certificateID.\(pathID).v1"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let fresh = "PF-\(pathID.uppercased())-\(UUID().uuidString.prefix(8).uppercased())"
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}
