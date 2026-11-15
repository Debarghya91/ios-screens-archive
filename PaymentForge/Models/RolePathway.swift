// RolePathway.swift
// Payments Training Hub iOS - Role-based pathway engine: one route per learner
// role, resolved live from the guided paths and guided sessions, plus
// the learner's active path selection.
//
// A route never hardcodes lessons. Its path lessons come from
// LearningPath.lessons(in:) and its session lessons from
// PFChapterHelper.lessons(forSession:in:), so every lesson shown is
// a real catalogue entry and every count is the real count.
//
// Eight roles, six guided paths: four roles have no dedicated path.
// Those routes follow guided sessions directly, or pair sessions
// with the nearest existing path, and say so in their description.
// See the route catalogue below and the discrepancy report.
// No em dashes in any user-facing text.

import Foundation
import Combine

// MARK: - Role route

/// One role's route through the course: a guided path when one fits,
/// plus the guided sessions that cover the role's work. Chapters and
/// lessons are always resolved live from the catalogue, never listed
/// here: only path ids and session ids are stored.
struct RoleRoute: Identifiable, Hashable {
    let id: String
    let role: LearnerRole
    let title: String
    let description: String
    let entryExpectations: String
    /// The guided path this route follows, nil when no existing path
    /// fits the role and the route follows sessions only.
    let pathID: String?
    /// Guided session ids, in the order the route follows them.
    let sessionIDs: [Int]

    var displayTitle: String { title }

    /// The guided path this route names, resolved live. Nil when the
    /// route names no path, or when the named path no longer exists.
    func learningPath() -> LearningPath? {
        guard let pathID else { return nil }
        return LearningPath.all.first { $0.id == pathID }
    }

    /// The guided sessions this route names, in route order. Session
    /// ids that do not exist in the catalogue are dropped, never
    /// invented.
    func sessions() -> [GuidedSession] {
        sessionIDs.compactMap { id in
            ContentService.guidedSessions.first { $0.id == id }
        }
    }

    /// Every lesson this route covers, in route order: the guided
    /// path's lessons first, then the named sessions' lessons in
    /// session order, deduped by lesson id. Resolved live from the
    /// catalogue; empty while the catalogue is loading.
    func lessons(in service: ContentService) -> [SearchEntry] {
        var seen: Set<String> = []
        var result: [SearchEntry] = []
        if let path = learningPath() {
            for lesson in path.lessons(in: service) {
                if seen.insert(lesson.id).inserted {
                    result.append(lesson)
                }
            }
        }
        for session in sessions() {
            for lesson in PFChapterHelper.lessons(forSession: session, in: service) {
                if seen.insert(lesson.id).inserted {
                    result.append(lesson)
                }
            }
        }
        return result
    }
}

// MARK: - Route catalogue

/// The eight role routes. Every LearnerRole maps to exactly one
/// route. pathID references an existing LearningPath id when one
/// fits, else nil. sessionIDs reference existing
/// ContentService.guidedSessions ids (1 through 8).
enum RoleRouteCatalogue {
    static let routes: [RoleRoute] = [
        RoleRoute(
            id: "route-new-to-payments",
            role: .newToPayments,
            title: "New to payments",
            description: "The Payments Fundamentals guided path, followed by guided sessions 1 and 2: what a payment is, and how money moves.",
            entryExpectations: "No prior payments knowledge is assumed. Nothing is enforced: any lesson can be opened at any time.",
            pathID: "fundamentals",
            sessionIDs: [1, 2]
        ),
        RoleRoute(
            id: "route-business-analyst",
            role: .businessAnalyst,
            title: "Business analyst",
            description: "The Payments Business Analyst guided path, plus guided session 8 for practice and interview preparation.",
            entryExpectations: "It helps to be comfortable with payments fundamentals. No prior business analysis experience is assumed. Nothing is enforced: any lesson can be opened at any time.",
            pathID: "business-analyst",
            sessionIDs: [8]
        ),
        RoleRoute(
            id: "route-technical-analyst",
            role: .technicalAnalyst,
            title: "Technical analyst",
            description: "There is no dedicated guided path for this role, so the route follows guided sessions directly: foundations, rails, ISO 20022 in depth, and exceptions, risk and compliance.",
            entryExpectations: "It helps to be comfortable with payments fundamentals. The route starts with foundations before moving to messaging and exceptions. Nothing is enforced: any lesson can be opened at any time.",
            pathID: nil,
            sessionIDs: [1, 2, 4, 6]
        ),
        RoleRoute(
            id: "route-product-owner",
            role: .productOwner,
            title: "Product owner",
            description: "The Payments Business Analyst guided path, plus guided sessions 1 and 5: what a payment is, and schemes and rails.",
            entryExpectations: "It helps to be comfortable with payments fundamentals. No prior product ownership experience is assumed. Nothing is enforced: any lesson can be opened at any time.",
            pathID: "business-analyst",
            sessionIDs: [1, 5]
        ),
        RoleRoute(
            id: "route-tester",
            role: .tester,
            title: "Tester",
            description: "There is no dedicated guided path for this role, so the route pairs guided sessions 1, 6 and 8 with the Payment Operations and Reconciliation guided path: foundations, exceptions, and practice.",
            entryExpectations: "It helps to be comfortable with payments fundamentals. No prior payments testing experience is assumed. Nothing is enforced: any lesson can be opened at any time.",
            pathID: "operations-reconciliation",
            sessionIDs: [1, 6, 8]
        ),
        RoleRoute(
            id: "route-cross-border-specialist",
            role: .crossBorderSpecialist,
            title: "Cross-border specialist",
            description: "There is no dedicated guided path for this role, so the route pairs guided sessions 2, 3 and 4 with the Payments Interview Preparation guided path: rails, SWIFT and messages, and ISO 20022 in depth.",
            entryExpectations: "It helps to be comfortable with payments fundamentals and with how money moves across borders. The route starts with the rails sessions before messaging. Nothing is enforced: any lesson can be opened at any time.",
            pathID: "interview-preparation",
            sessionIDs: [2, 3, 4]
        ),
        RoleRoute(
            id: "route-sme",
            role: .sme,
            title: "Subject matter expert",
            description: "The Payments Interview Preparation guided path, plus every guided session, 1 through 8, for depth across the whole course.",
            entryExpectations: "This route covers every guided session. It helps to already be comfortable with payments fundamentals and the main rails and message types. Nothing is enforced: any lesson can be opened at any time.",
            pathID: "interview-preparation",
            sessionIDs: [1, 2, 3, 4, 5, 6, 7, 8]
        ),
        RoleRoute(
            id: "route-solution-architect",
            role: .solutionArchitect,
            title: "Solution architect",
            description: "There is no dedicated guided path for this role, so the route pairs guided sessions 2, 4 and 6 with the Payment Operations and Reconciliation guided path: rails, ISO 20022 in depth, and exceptions, risk and compliance.",
            entryExpectations: "An advanced route. It helps to be comfortable with payments fundamentals, rails, and messaging before starting. Nothing is enforced: any lesson can be opened at any time.",
            pathID: "operations-reconciliation",
            sessionIDs: [2, 4, 6]
        )
    ]

    /// The route for one role. Every role has exactly one route, so
    /// the fallback to the first route is unreachable for known
    /// roles; it exists only so this function stays total if a role
    /// is ever added without a route.
    static func route(for role: LearnerRole) -> RoleRoute {
        routes.first { $0.role == role } ?? routes[0]
    }

    /// The first route that names a guided path id, or nil when no
    /// route names it. Several routes share one path, so this is a
    /// lookup, not a one to one mapping: the first route in
    /// catalogue order wins.
    static func route(forPathID pathID: String) -> RoleRoute? {
        routes.first { $0.pathID == pathID }
    }
}

// MARK: - Active path

/// The learner's active guided path: the one they picked to work
/// through. Stored in UserDefaults, namespaced per account through
/// AccountScopedStorage, following the PathBookmarkStore pattern.
///
/// Switching the active path never clears progress: progress lives
/// per lesson in ProgressStore, which this store never touches.
/// Only the selected path id is recorded here, and clearing the
/// selection removes the stored id, nothing else.
final class ActivePathStore: ObservableObject {
    static let shared = ActivePathStore()

    private enum Keys {
        static let activePath = "pf.activePath.v1"
    }

    @Published private(set) var activePathID: String? = nil {
        didSet { save() }
    }

    /// Suppresses save() while loading, so a reload into an account
    /// with no stored active path does not write into that namespace
    /// (which would block guest migration for it).
    private var suppressSave = false

    private func withoutSaving(_ work: () -> Void) {
        let previous = suppressSave
        suppressSave = true
        defer { suppressSave = previous }
        work()
    }

    /// Select a guided path as the active path, or pass nil to clear
    /// the selection. The id is stored as given; whether it names a
    /// path that exists is resolved live by `activePath`, so a
    /// stored id for a removed path simply resolves to nil.
    func select(_ pathID: String?) {
        activePathID = pathID
    }

    /// The active guided path, resolved live. Nil when no path is
    /// selected, or when the stored id names no existing path.
    var activePath: LearningPath? {
        guard let activePathID else { return nil }
        return LearningPath.all.first { $0.id == activePathID }
    }

    init() {
        load()
    }

    /// Reload for the current account namespace, clearing the
    /// previous account's active path first.
    func reloadForCurrentAccount() {
        withoutSaving { activePathID = nil }
        load()
    }

    private func load() {
        withoutSaving {
            AccountScopedStorage.adoptLegacyKey(Keys.activePath)
            activePathID = UserDefaults.standard.string(forKey: AccountScopedStorage.currentKey(Keys.activePath))
        }
    }

    private func save() {
        guard !suppressSave else { return }
        let key = AccountScopedStorage.currentKey(Keys.activePath)
        if let activePathID {
            UserDefaults.standard.set(activePathID, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
