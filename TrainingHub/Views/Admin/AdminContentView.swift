// AdminContentView.swift
// Payments Training Hub iOS - Content management admin tool.
//
// An internal diagnostic tool, not a learner feature and not a
// central content management system: its only entry point is the
// Profile row, which is compiled in DEBUG builds only, so it is
// absent from Release builds. It works only with the local registry
// on this device. It lists every content type with its live count
// from the loaded website data, shows each type's version and status
// summary, and lets an admin mark an item as a preview or change its
// access classification locally. Publication status is recorded in
// the local registry only: no learner view reads it yet, so marking
// an item Draft here does not hide it from learners.
//
// The website remains the source of truth: nothing here migrates,
// copies or re-hosts content, and every change here is stored in the
// local registry only (UserDefaults). Quizzes, Diagrams and Audio
// have no item list here: quizzes and diagrams live inside lesson
// pages and audio is one file per lesson, so no item-level list
// exists for them yet, and none is invented.
// No em dashes in any user-facing text.

import SwiftUI

// MARK: - Admin content view

struct AdminContentView: View {
    @EnvironmentObject private var contentService: ContentService
    @ObservedObject private var management = ContentManagementService.shared

    @State private var showResetConfirmation = false

    private var summaries: [ContentTypeSummary] {
        management.summaries(in: contentService)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Internal diagnostic view")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("This screen shows local registry data stored on this device only. It is not a central content management system, and changes here do not affect the published content or what other learners see.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Local registry, website source")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("The website is still the source of truth for all content. This tool only records which version of each item this device has seen, and stores local admin notes: preview flags, publication status and access classification. Nothing here moves content or changes what the website serves.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(management.records.count) items recorded in the local registry.")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                }
                ForEach(summaries) { summary in
                    NavigationLink(destination: AdminContentTypeView(type: summary.type)) {
                        PFCard {
                            HStack(spacing: PFSpacing.md) {
                                PFIconTile(systemImage: summary.type.systemImage, size: 44)
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(summary.type.rawValue)
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                    Text(countText(for: summary))
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(statusText(for: summary))
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.pfSecondaryText)
                            }
                        }
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
                PFSecondaryButton(title: "Reset local registry") {
                    showResetConfirmation = true
                }
                Text("Resetting clears the local records and admin notes on this device only. It does not change the website or any lesson.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PFSpacing.lg)
            .id("adminTop")
        }
        .pfScrollToTopOnAppear("adminTop")
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Content management")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            management.recordLoadedCatalogue(from: contentService)
        }
        .confirmationDialog(
            "Reset the local registry?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset registry", role: .destructive) {
                management.resetRegistry()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This clears the local version records and admin notes on this device. The website content is not affected.")
        }
    }

    private func countText(for summary: ContentTypeSummary) -> String {
        if let liveCount = summary.liveCount {
            return "\(liveCount) \(liveCount == 1 ? "item" : "items") loaded from the website"
        }
        return "No live count: this type lives inside lesson pages"
    }

    private func statusText(for summary: ContentTypeSummary) -> String {
        "Published \(summary.publishedCount), Draft \(summary.draftCount), Archived \(summary.archivedCount), Preview \(summary.previewCount)"
    }
}

// MARK: - One content type

/// The items of one content type, from the loaded website data.
/// Quizzes, Diagrams and Audio have no item list: their items live
/// inside lesson pages (or are one file per lesson), so the view says
/// so instead of inventing a list.
struct AdminContentTypeView: View {
    @EnvironmentObject private var contentService: ContentService
    @ObservedObject private var management = ContentManagementService.shared
    let type: PFContentType

    @State private var currentPage = 1

    /// One listable item: its id and title from the loaded data.
    private struct AdminItem: Identifiable {
        var id: String { contentID }
        let contentID: String
        let title: String
    }

    private var items: [AdminItem] {
        switch type {
        case .lesson:
            return contentService.allLessons.map { AdminItem(contentID: $0.id, title: $0.title) }
        case .guide:
            return contentService.allGuides.map { AdminItem(contentID: $0.id, title: $0.title) }
        case .lab:
            return (contentService.searchIndex?.entries.filter { $0.type == .lab } ?? [])
                .map { AdminItem(contentID: $0.id, title: $0.title) }
        case .test:
            return (contentService.searchIndex?.entries.filter { $0.type == .test } ?? [])
                .map { AdminItem(contentID: $0.id, title: $0.title) }
        case .situation:
            if let full = contentService.fullSituations {
                return full.map { AdminItem(contentID: $0.id, title: $0.title) }
            }
            return contentService.allSituations.map { AdminItem(contentID: $0.id, title: $0.title) }
        case .quiz, .diagram, .audio:
            return []
        }
    }

    private var totalItemPages: Int {
        PFPagination.totalPages(totalCount: items.count)
    }

    private var effectiveItemPage: Int {
        PFPagination.clampedPage(currentPage, totalPages: totalItemPages)
    }

    private var visibleItems: [AdminItem] {
        PFPagination.slice(items, page: currentPage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                if !type.hasLiveCount {
                    PFCard {
                        Text(explanationText)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if items.isEmpty {
                    PFCard {
                        Text("No \(type.rawValue.lowercased()) are loaded yet. Check your connection and reload the catalogue.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("\(items.count) \(type.rawValue.lowercased()) loaded from the website. Tap one to change its preview flag, publication status or access classification in the local registry.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(visibleItems) { item in
                        NavigationLink(destination: AdminContentItemView(type: type, contentID: item.contentID, title: item.title)) {
                            AdminItemRow(type: type, contentID: item.contentID, title: item.title)
                        }
                        .buttonStyle(PFCardButtonStyle())
                    }
                    if totalItemPages > 1 {
                        let bounds = PFPagination.rangeBounds(page: effectiveItemPage, totalCount: items.count)
                        Text("Showing \(bounds.first)-\(bounds.last) of \(items.count) items")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PFPaginationBar(currentPage: effectiveItemPage, totalPages: totalItemPages) { page in
                            currentPage = page
                        }
                    }
                }
            }
            .padding(PFSpacing.lg)
            .id("adminTypeTop")
        }
        .pfScrollToTopOnAppear("adminTypeTop", resetWhen: currentPage)
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle(type.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var explanationText: String {
        switch type {
        case .quiz:
            return "Quizzes live inside lesson pages: each lesson carries its own quiz questions, so there is no separate quiz list to manage yet. Quiz counts will appear here once lesson pages are counted."
        case .diagram:
            return "Diagrams live inside lesson pages: each lesson may carry a diagram, so there is no separate diagram list to manage yet."
        case .audio:
            return "Audio is one file per lesson, streamed from the audio host. There is no separate audio list to manage; the lesson list is the audio list."
        default:
            return ""
        }
    }
}

// MARK: - One item row

/// One item row: title, id, publication status, access and preview.
/// Status and access come from the local registry (or the item
/// metadata for free samples); items with no record show as
/// Published with no access override.
struct AdminItemRow: View {
    @ObservedObject private var management = ContentManagementService.shared
    let type: PFContentType
    let contentID: String
    let title: String

    var body: some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(contentID)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: statusText)
                        if let access = management.accessClassification(for: type, contentID: contentID) {
                            PFPill(text: access.displayName)
                        } else {
                            PFPill(text: "Not classified")
                        }
                        if management.isPreview(contentType: type, contentID: contentID) {
                            PFPill(text: "Preview", background: Color.pfGold.opacity(0.20), foreground: .pfNavy)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
            }
        }
    }

    private var statusText: String {
        management.record(for: type, contentID: contentID)?.status.displayName ?? "Published"
    }
}

// MARK: - One item editor

/// Edit one item's preview flag, publication status and access
/// classification in the local registry. Every control writes
/// immediately to the registry; there is no separate save step and
/// no server call.
struct AdminContentItemView: View {
    @ObservedObject private var management = ContentManagementService.shared
    let type: PFContentType
    let contentID: String
    let title: String

    @State private var isPreview = false
    @State private var status: ContentPublicationStatus = .published
    @State private var access: String = "none"
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text(title)
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(type.rawValue) \(contentID)")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                        if let record = management.record(for: type, contentID: contentID) {
                            Text("Local version \(record.version), last updated \(record.updatedAt.formatted(date: .abbreviated, time: .shortened)) by \(record.updatedBy).")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("No local record yet: this item is served from the website as published.")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Toggle("Preview", isOn: $isPreview)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .onChange(of: isPreview) { _, value in
                                management.setPreview(value, contentType: type, contentID: contentID)
                            }
                        Text("A preview item is shown with a Preview badge in the admin list. It is not a separate copy of the content, and no learner view reads this flag yet.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("Publication status")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Picker("Publication status", selection: $status) {
                            ForEach(ContentPublicationStatus.allCases, id: \.self) { value in
                                Text(value.displayName).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: status) { _, value in
                            management.setStatus(value, contentType: type, contentID: contentID)
                        }
                        Text("Draft and Archived are recorded in the local registry only. No learner view reads this status yet, so changing it here does not hide the item from learners.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("Access classification")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Picker("Access classification", selection: $access) {
                            Text("Not classified").tag("none")
                            Text("Free").tag("free")
                            Text("Premium").tag("premium")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: access) { _, value in
                            let classification: ContentAccessClassification?
                            switch value {
                            case "free": classification = .free
                            case "premium": classification = .premium
                            default: classification = nil
                            }
                            management.setAccessClassification(classification, contentType: type, contentID: contentID)
                        }
                        Text("Free sample situations are Free from the website metadata. Anything else stays Not classified unless you set it here; no classification is invented.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Changes are stored in the local registry on this device only. They do not change the website.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Edit item")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didLoad {
                isPreview = management.isPreview(contentType: type, contentID: contentID)
                status = management.record(for: type, contentID: contentID)?.status ?? .published
                switch management.record(for: type, contentID: contentID)?.accessClassification {
                case .free: access = "free"
                case .premium: access = "premium"
                case .none: access = "none"
                }
                didLoad = true
            }
        }
    }
}
