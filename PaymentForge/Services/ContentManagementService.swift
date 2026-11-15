// ContentManagementService.swift
// Payments Training Hub iOS - Local content-version registry.
//
// The website remains the operational source of truth: ContentService
// keeps loading the live search index and situations data, and this
// service never replaces, rewrites or re-hosts that content. It keeps
// a small local registry (UserDefaults) that records which version of
// each item the app has seen, plus local admin annotations (preview
// flag, publication status, access classification). Those annotations
// are the validation step for the future server-driven architecture:
// they prove the model works end to end on this device before any
// content is migrated. Publication status is recorded but not
// enforced: no learner view calls shouldShow yet, so marking an item
// Draft does not hide it from learners. Nothing here is synced to
// a server yet, and no content is downloaded by this service. The
// admin UI over this registry is an internal diagnostic tool,
// reachable only in DEBUG builds; it is not a central content
// management system.
// No em dashes in any user-facing text.

import Foundation
import Combine

/// Local content-version registry and admin annotations.
final class ContentManagementService: ObservableObject {
    static let shared = ContentManagementService()

    private enum Keys {
        static let registry = "pf.contentRegistry.v1"
    }

    /// All registry records, keyed by "<type>:<contentID>".
    @Published private(set) var records: [String: ContentVersion] = [:] {
        didSet { save() }
    }

    init() {
        load()
    }

    // MARK: - Registry

    /// Record that the app has seen one item at the current website
    /// version (1 until the website carries version numbers). An
    /// existing record is kept and only its seen time is refreshed,
    /// so admin annotations are never wiped by a re-seen item.
    func recordSeen(contentType: PFContentType, contentID: String) {
        let key = ContentVersion(contentType: contentType, contentID: contentID).id
        if var existing = records[key] {
            existing.updatedAt = Date()
            records[key] = existing
        } else {
            records[key] = ContentVersion(contentType: contentType, contentID: contentID)
        }
    }

    /// Record every item currently loaded from the website, so the
    /// registry reflects what the app has actually seen. Call after
    /// the search index (and situations data, when loaded) arrives.
    /// This only adds records; it never removes admin annotations.
    func recordLoadedCatalogue(from contentService: ContentService) {
        guard let index = contentService.searchIndex else { return }
        for entry in index.entries {
            let type: PFContentType?
            switch entry.type {
            case .lesson: type = .lesson
            case .guide: type = .guide
            case .situation: type = .situation
            case .lab: type = .lab
            case .test: type = .test
            case .faq: type = nil
            }
            if let type { recordSeen(contentType: type, contentID: entry.id) }
        }
        if let full = contentService.fullSituations {
            for item in full {
                recordSeen(contentType: .situation, contentID: item.id)
            }
        }
    }

    /// The registry record for one item, nil when the app has not
    /// seen it yet (or the admin has never annotated it).
    func record(for contentType: PFContentType, contentID: String) -> ContentVersion? {
        records[ContentVersion(contentType: contentType, contentID: contentID).id]
    }

    /// Remove every registry record. Admin annotations are local
    /// only, so this only affects this device.
    func resetRegistry() {
        records = [:]
    }

    // MARK: - Publication, preview and access

    /// Whether one item may be shown to a learner. Draft and
    /// archived items are never shown; only published items appear.
    /// Items with no registry record are published by default,
    /// because the website is the source of truth and serves them.
    /// No learner view calls this yet, so the status is recorded
    /// but not enforced: Draft does not currently hide an item.
    func shouldShow(contentType: PFContentType, contentID: String) -> Bool {
        guard let status = record(for: contentType, contentID: contentID)?.status else { return true }
        return status == .published
    }

    /// True when an admin has marked this item as a preview.
    func isPreview(contentType: PFContentType, contentID: String) -> Bool {
        record(for: contentType, contentID: contentID)?.isPreview ?? false
    }

    /// The effective access classification for one item. A local
    /// admin override wins; otherwise the item's existing metadata
    /// is read (free sample situations are free); otherwise the item
    /// is unclassified and nil is returned, never an invented value.
    func accessClassification(for contentType: PFContentType, contentID: String) -> ContentAccessClassification? {
        if let override = record(for: contentType, contentID: contentID)?.accessClassification {
            return override
        }
        if contentType == .situation, ContentService.freeSampleIDs.contains(contentID) {
            return .free
        }
        return nil
    }

    // MARK: - Admin mutations (local registry only)

    private func mutate(contentType: PFContentType, contentID: String, _ change: (inout ContentVersion) -> Void) {
        let key = ContentVersion(contentType: contentType, contentID: contentID).id
        var record = records[key] ?? ContentVersion(contentType: contentType, contentID: contentID)
        change(&record)
        record.updatedAt = Date()
        record.updatedBy = "admin"
        records[key] = record
    }

    /// Mark an item as a preview, or clear the preview flag.
    func setPreview(_ isPreview: Bool, contentType: PFContentType, contentID: String) {
        mutate(contentType: contentType, contentID: contentID) { $0.isPreview = isPreview }
    }

    /// Change an item's publication status. Draft records the item
    /// as hidden in the intended design (see shouldShow); no learner
    /// view reads this yet, so it does not hide the item today.
    func setStatus(_ status: ContentPublicationStatus, contentType: PFContentType, contentID: String) {
        mutate(contentType: contentType, contentID: contentID) { $0.status = status }
    }

    /// Change an item's access classification locally. Pass nil to
    /// clear the override and fall back to the item metadata.
    func setAccessClassification(_ classification: ContentAccessClassification?, contentType: PFContentType, contentID: String) {
        mutate(contentType: contentType, contentID: contentID) { $0.accessClassification = classification }
    }

    // MARK: - Summaries

    /// Live counts per type from the loaded data. Quizzes, Diagrams
    /// and Audio have no live count (nil): they live inside lesson
    /// pages or are one file per lesson, so no number is invented.
    func liveCount(for type: PFContentType, in contentService: ContentService) -> Int? {
        switch type {
        case .lesson:
            return contentService.searchIndex?.counts.lesson ?? contentService.allLessons.count
        case .situation:
            if let full = contentService.fullSituations { return full.count }
            return contentService.searchIndex?.counts.situation ?? contentService.allSituations.count
        case .guide:
            return contentService.searchIndex?.counts.guide ?? contentService.allGuides.count
        case .lab:
            return contentService.searchIndex?.entries.filter { $0.type == .lab }.count
        case .test:
            return contentService.searchIndex?.entries.filter { $0.type == .test }.count
        case .quiz, .diagram, .audio:
            return nil
        }
    }

    /// The admin summary for every content type.
    func summaries(in contentService: ContentService) -> [ContentTypeSummary] {
        PFContentType.allCases.map { type in
            let typed = records.values.filter { $0.contentType == type }
            return ContentTypeSummary(
                type: type,
                liveCount: liveCount(for: type, in: contentService),
                publishedCount: typed.filter { $0.status == .published }.count,
                draftCount: typed.filter { $0.status == .draft }.count,
                archivedCount: typed.filter { $0.status == .archived }.count,
                previewCount: typed.filter(\.isPreview).count
            )
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Keys.registry),
              let decoded = try? JSONDecoder().decode([String: ContentVersion].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Keys.registry)
        }
    }
}
