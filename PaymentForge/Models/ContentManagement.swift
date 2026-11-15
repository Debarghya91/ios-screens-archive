// ContentManagement.swift
// PaymentForge iOS - Content management architecture (incremental).
//
// INCREMENTAL ARCHITECTURE, NOT A MIGRATION. The live website remains
// the source of truth for all content: ContentService keeps loading the
// search index and situations-data.js exactly as before, and no content
// has been copied, moved or re-hosted into the app. This file adds only
// the versioning, publication and access model plus a local registry
// (see ContentManagementService) that records which version of each
// item the app has seen, so a future server-driven update can be
// applied incrementally, one item at a time. Until that server side
// exists and is validated, the website is the operational source and
// this layer only annotates what the website already serves. The
// admin UI over this layer is an internal diagnostic tool, reachable
// only in DEBUG builds; it is not a central content management
// system, and a local preference is never proof of admin permission:
// there is no role check anywhere in this layer.
// No em dashes in any user-facing text.

import Foundation

// MARK: - Content types

/// The content types the app serves, matching the live catalogue.
/// Quizzes, Diagrams and Audio are not separate catalogue entries:
/// Quizzes live inside lesson pages, Diagrams inside lesson pages,
/// and Audio is one file per lesson. Their counts are therefore
/// reported as "not counted yet" in the admin view rather than
/// invented; only Lessons, Situations, Guides, Labs and Tests have
/// live counts from the loaded search index.
enum PFContentType: String, CaseIterable, Codable {
    case lesson = "Lessons"
    case situation = "Situations"
    case guide = "Guides"
    case lab = "Labs"
    case test = "Tests"
    case quiz = "Quizzes"
    case diagram = "Diagrams"
    case audio = "Audio"

    var systemImage: String {
        switch self {
        case .lesson: return "play.fill"
        case .situation: return "briefcase.fill"
        case .guide: return "book.fill"
        case .lab: return "flask.fill"
        case .test: return "checkmark.circle.fill"
        case .quiz: return "questionmark.circle.fill"
        case .diagram: return "flowchart.fill"
        case .audio: return "waveform"
        }
    }

    /// True when this type has a live count in the loaded data.
    /// Quizzes, Diagrams and Audio do not, for the reason above.
    var hasLiveCount: Bool {
        switch self {
        case .lesson, .situation, .guide, .lab, .test:
            return true
        case .quiz, .diagram, .audio:
            return false
        }
    }
}

// MARK: - Publication status

/// Whether a content item may be shown to learners, in the intended
/// design. No learner view reads this status yet (see shouldShow in
/// ContentManagementService), so Draft and Archived are recorded but
/// do not currently hide an item from learners. Archived items are
/// kept in the registry.
enum ContentPublicationStatus: String, Codable, CaseIterable {
    case draft
    case published
    case archived

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .published: return "Published"
        case .archived: return "Archived"
        }
    }
}

// MARK: - Access classification

/// Whether a content item is free or premium. The classification is
/// read from the item's existing metadata where present (the free
/// sample situation ids), and is never invented: when no metadata
/// and no local admin override exists, the item is unclassified.
/// Access enforcement is not part of this layer; this records the
/// classification so a future enforcement step can read it.
enum ContentAccessClassification: String, Codable, CaseIterable {
    case free
    case premium

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .premium: return "Premium"
        }
    }
}

// MARK: - Content version

/// One version record for one content item, in the local registry.
/// `version` is 1 for every website-sourced item today: the website
/// carries no version numbers yet, so 1 means "the version the app
/// first saw". A future server-driven feed will carry real version
/// numbers, and the registry will then record each new version as it
/// is seen, so updates apply incrementally instead of by full reload.
/// `updatedBy` is "website" for website-sourced records and "admin"
/// for local admin overrides. Nothing here is synced anywhere yet.
struct ContentVersion: Identifiable, Codable, Hashable {
    /// Stable id: "<type>:<contentID>", so the same content id in
    /// two types never collides.
    var id: String { "\(contentType.rawValue):\(contentID)" }
    let contentType: PFContentType
    let contentID: String
    var version: Int
    var status: ContentPublicationStatus
    /// Local admin override for access, nil when not set. The
    /// effective classification also considers the item metadata
    /// (see ContentManagementService).
    var accessClassification: ContentAccessClassification?
    /// True when an admin has marked this item as a preview. A
    /// preview item is shown with a Preview badge in the admin list;
    /// it is not a separate copy of the content, and no learner view
    /// reads this flag yet.
    var isPreview: Bool
    var updatedAt: Date
    var updatedBy: String

    init(
        contentType: PFContentType,
        contentID: String,
        version: Int = 1,
        status: ContentPublicationStatus = .published,
        accessClassification: ContentAccessClassification? = nil,
        isPreview: Bool = false,
        updatedAt: Date = Date(),
        updatedBy: String = "website"
    ) {
        self.contentType = contentType
        self.contentID = contentID
        self.version = version
        self.status = status
        self.accessClassification = accessClassification
        self.isPreview = isPreview
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }
}

// MARK: - Type summary

/// The admin summary for one content type: its live count from the
/// loaded data (nil when the type has no live count), and how many
/// registry records for that type are in each publication status.
struct ContentTypeSummary: Identifiable {
    var id: PFContentType { type }
    let type: PFContentType
    /// Live count from the loaded data, nil when not countable.
    let liveCount: Int?
    let publishedCount: Int
    let draftCount: Int
    let archivedCount: Int
    let previewCount: Int
}
