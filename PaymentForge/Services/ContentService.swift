// ContentService.swift
// PaymentForge iOS - Loads content from the live website so it stays current.
// No backend of its own. If a live fetch fails, the caller shows a clear
// error with Retry, never a silent failure.

import Foundation
import Combine

/// Fetches the catalogue and lesson content from paymentstraininghub.com.
final class ContentService: ObservableObject {
    static let shared = ContentService()

    // MARK: - Endpoints

    static let siteBase = URL(string: "https://www.paymentstraininghub.com")!
    static let searchIndexURL = URL(string: "https://www.paymentstraininghub.com/assets/search-index.json")!
    static let situationsDataURL = URL(string: "https://www.paymentstraininghub.com/assets/situations-data.js")!
    static let primaryAudioBase = "https://paymentforge-audio.pages.dev/audio/"
    static let fallbackAudioBase = "https://paymentforge-audio-backup.pages.dev/audio/"

    /// The 10 free Payment Situations samples, ungated on the website.
    static let freeSampleIDs: [String] = [
        "ABH-01", "ABH-04", "JEB-C01", "ABH-10", "INS-086",
        "ABH-03", "INS-033", "INS-135", "SCN-26", "SCN-28"
    ]

    /// The 8-session guided path. Session titles and descriptions are the
    /// site's own guided path, chapters are resolved from the search index.
    static let guidedSessions: [GuidedSession] = [
        GuidedSession(id: 1, title: "What a payment is", description: "Foundations, parties, accounts and the payment lifecycle.", chapterIDs: ["ch1", "ch2"]),
        GuidedSession(id: 2, title: "How money moves", description: "Rails, clearing and settlement, correspondent banking.", chapterIDs: ["ch3", "ch4"]),
        GuidedSession(id: 3, title: "SWIFT and messages", description: "MT and MX messages, field-level reading, UETR tracking.", chapterIDs: ["ch5", "ch6"]),
        GuidedSession(id: 4, title: "ISO 20022 in depth", description: "pain, pacs and camt messages, migration and mapping.", chapterIDs: ["ch7", "ch8"]),
        GuidedSession(id: 5, title: "Schemes and rails", description: "SEPA, Faster Payments, CHAPS, BACS, Fedwire and CHIPS.", chapterIDs: ["ch9", "ch10"]),
        GuidedSession(id: 6, title: "Exceptions and repair", description: "Returns, recalls, investigations and payment repair.", chapterIDs: ["ch11", "ch12"]),
        GuidedSession(id: 7, title: "Cards and clearing", description: "Card payments, authorisation, clearing and chargebacks.", chapterIDs: ["ch13", "ch14"]),
        GuidedSession(id: 8, title: "Practice and interview", description: "Scenarios, interview questions and the placement test.", chapterIDs: ["ch15", "ch16"])
    ]

    // MARK: - Published state

    @Published private(set) var searchIndex: SearchIndex? = nil
    @Published private(set) var isLoadingIndex = false
    @Published private(set) var indexError: String? = nil

    /// True when the catalogue or situations on screen came from the
    /// local cache because the live fetch failed. Views show the
    /// PFOfflineBanner when this is true, so cached content is never
    /// presented as if it were live. False after a successful fetch.
    @Published private(set) var isShowingCachedContent = false

    /// Disk-cache file names in the caches directory. Content only:
    /// no downloads, no audio, no user data.
    static let searchIndexCacheFile = "pf-search-index.json"
    static let situationsCacheFile = "pf-situations-data.js"

    /// The caches-directory URL for one cache file.
    static func cacheFileURL(fileName: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(fileName)
    }

    /// Save raw fetched bytes to the disk cache. Best effort: a
    /// failed write never fails the load that just succeeded.
    static func saveCache(_ data: Data, fileName: String) {
        try? data.write(to: cacheFileURL(fileName: fileName), options: [.atomic])
    }

    /// The cached bytes for one file, nil when nothing was cached.
    static func loadCache(fileName: String) -> Data? {
        try? Data(contentsOf: cacheFileURL(fileName: fileName))
    }

    /// The full situations data (564 items), when it has loaded.
    /// Nil until the fetch succeeds; the list falls back to the
    /// search index entries so it never goes empty.
    @Published private(set) var fullSituations: [FullSituationItem]? = nil
    @Published private(set) var isLoadingSituations = false

    private init() {}

    // MARK: - Search index

    /// Load the search index (1,625 entries). Call once at launch.
    /// Bounded retry (3 attempts, exponential backoff). When every
    /// attempt fails, the last cached catalogue is used instead, so
    /// the app shows saved content with an offline note rather than
    /// a blank screen; only when there is no cache at all does the
    /// caller see indexError with a Retry action.
    @MainActor
    func loadSearchIndex() async {
        if searchIndex != nil || isLoadingIndex { return }
        isLoadingIndex = true
        indexError = nil
        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(from: Self.searchIndexURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw ContentError.badResponse
                }
                let decoded = try JSONDecoder().decode(SearchIndex.self, from: data)
                searchIndex = decoded
                Self.saveCache(data, fileName: Self.searchIndexCacheFile)
                isShowingCachedContent = false
                isLoadingIndex = false
                return
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
                }
            }
        }
        if let cached = Self.loadCache(fileName: Self.searchIndexCacheFile),
           let decoded = try? JSONDecoder().decode(SearchIndex.self, from: cached) {
            searchIndex = decoded
            isShowingCachedContent = true
            indexError = nil
        } else {
            indexError = "Could not load the course catalogue. Check your connection and try again."
            isShowingCachedContent = false
        }
        isLoadingIndex = false
    }

    /// Search the loaded index by title and text, title matches first.
    /// Single pass over the entries (the old version scanned the whole
    /// index twice and re-lowercased every title and body twice).
    func search(query: String, limit: Int = 30) -> [SearchEntry] {
        guard let index = searchIndex else { return [] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        var titleMatches: [SearchEntry] = []
        var textMatches: [SearchEntry] = []
        titleMatches.reserveCapacity(32)
        textMatches.reserveCapacity(32)
        for entry in index.entries {
            let title = entry.title.lowercased()
            if title.contains(needle) {
                titleMatches.append(entry)
            } else if entry.text.lowercased().contains(needle) {
                textMatches.append(entry)
            }
        }
        return Array((titleMatches + textMatches).prefix(limit))
    }

    /// All lessons, in catalogue order.
    var allLessons: [SearchEntry] {
        searchIndex?.entries.filter { $0.type == .lesson } ?? []
    }

    /// All guides, in catalogue order.
    var allGuides: [SearchEntry] {
        searchIndex?.entries.filter { $0.type == .guide } ?? []
    }

    /// All situations, in catalogue order.
    var allSituations: [SearchEntry] {
        searchIndex?.entries.filter { $0.type == .situation } ?? []
    }

    // MARK: - Full situations data

    /// Load the full situations data file (564 items with the full
    /// explain text and visual). The file is a JS assignment
    /// (window.PA_SITUATIONS = [...];) so the prefix and trailing
    /// semicolon are stripped before JSON decoding. Bounded retry
    /// (3 attempts, exponential backoff); on failure the cached
    /// file is used when one exists, and fullSituations stays nil
    /// otherwise so callers fall back to the search index entries
    /// and the list never goes empty.
    @MainActor
    func loadFullSituations() async {
        if fullSituations != nil || isLoadingSituations { return }
        isLoadingSituations = true
        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(from: Self.situationsDataURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      var text = String(data: data, encoding: .utf8) else {
                    throw ContentError.badResponse
                }
                let prefix = "window.PA_SITUATIONS = "
                guard text.hasPrefix(prefix) else { throw ContentError.badResponse }
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasSuffix(";") { text = String(text.dropLast()) }
                guard let jsonData = text.data(using: .utf8) else { throw ContentError.badResponse }
                let decoded = try JSONDecoder().decode([FullSituationItem].self, from: jsonData)
                fullSituations = decoded
                Self.saveCache(data, fileName: Self.situationsCacheFile)
                // Do not clear isShowingCachedContent here: the flag
                // belongs to the catalogue load, which may have fallen
                // back to cache even when this file loads live.
                isLoadingSituations = false
                return
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
                }
            }
        }
        if let cached = Self.loadCache(fileName: Self.situationsCacheFile),
           var text = String(data: cached, encoding: .utf8) {
            let prefix = "window.PA_SITUATIONS = "
            if text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasSuffix(";") { text = String(text.dropLast()) }
                if let jsonData = text.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([FullSituationItem].self, from: jsonData) {
                    fullSituations = decoded
                    isShowingCachedContent = true
                }
            }
        }
        isLoadingSituations = false
    }

    /// Stage names, the same six learning stages as the website.
    static let situationStageNames: [Int: String] = [
        1: "Payment mechanics",
        2: "Processing decisions",
        3: "Operational exceptions",
        4: "Cross-system consequences",
        5: "Complex banking scenarios",
        6: "Senior SME judgement"
    ]

    /// Where a situation's stage came from. `authoritative` means
    /// the live data file's own `stage` field; `stageMap` means the
    /// website per-item stage map; `levelFallback` means the level
    /// fallback (foundation to 1, advanced to 6, anything else to 3).
    /// Only `authoritative` is presented as the item's stage; the
    /// other two are derived and are labelled as such.
    enum SituationStageSource: Equatable {
        case authoritative
        case stageMap
        case levelFallback
    }

    /// The stage source for one full situation item.
    static func stageSource(forFullItem item: FullSituationItem) -> SituationStageSource {
        if let stage = item.stage, (1...6).contains(stage) {
            return .authoritative
        }
        if situationStageMap[item.id] != nil {
            return .stageMap
        }
        return .levelFallback
    }

    /// The stage for one full situation item. Priority: the data
    /// file's own `stage` field when it is present and in range
    /// (authoritative, verified for all 564 items on 11 Nov 2026),
    /// then the website per-item stage map, then the level fallback.
    /// No stage numbers are invented beyond that map and fallback.
    static func stage(forFullItem item: FullSituationItem) -> Int {
        if let stage = item.stage, (1...6).contains(stage) {
            return stage
        }
        if let mapped = situationStageMap[item.id], (1...6).contains(mapped) {
            return mapped
        }
        switch item.level.lowercased() {
        case "foundation": return 1
        case "advanced": return 6
        default: return 3
        }
    }

    /// The stage name for one full situation item: the data file's
    /// own `stage_name` when it is present and matches the resolved
    /// stage (verified for all 564 items on 11 Nov 2026), otherwise
    /// the standard name for the resolved stage.
    static func stageName(forFullItem item: FullSituationItem) -> String {
        let stage = stage(forFullItem: item)
        if stageSource(forFullItem: item) == .authoritative,
           let name = item.stageName, !name.isEmpty {
            return name
        }
        return stageName(for: stage)
    }

    /// The stage name for a stage number.
    static func stageName(for stage: Int) -> String {
        situationStageNames[stage] ?? "Stage \(stage)"
    }

    /// The per-item stage map from the website
    /// (content/premium-500/situation-stage-map.json). The 35 items
    /// added after the map was written are not in it and fall back
    /// by level. Generated from the map file; do not hand-edit.
    private static let situationStageMap: [String: Int] = [
        "ABH-01": 1, "ABH-02": 1, "ABH-03": 3, "ABH-04": 1,
        "ABH-05": 1, "ABH-06": 1, "ABH-07": 1, "ABH-08": 1,
        "ABH-09": 1, "ABH-10": 2, "ABH-11": 1, "ABH-12": 2,
        "ABH-13": 1, "ABH-14": 2, "ABH-15": 2, "ABH-16": 2,
        "ABH-17": 2, "ABH-18": 6, "ABH-19": 1, "ABH-20": 1,
        "ABH-21": 1, "ABH-22": 1, "ABH-23": 1, "ABH-24": 2,
        "ABH-25": 6, "ABH-26": 6, "ABH-27": 1, "ABH-28": 1,
        "ABH-29": 1, "ABH-30": 1, "ABH-31": 6, "ABH-32": 6,
        "ABH-33": 6, "ABH-34": 6, "ABH-35": 6, "ABH-36": 6,
        "ABH-37": 6, "ABH-38": 6, "ABH-39": 6, "ABH-40": 6,
        "ABH-41": 6, "ABH-42": 6, "ABH-43": 6, "ABH-44": 6,
        "ABH-45": 6, "ABH-46": 6, "ABH-47": 6, "ABH-48": 6,
        "ABH-49": 6, "ABH-50": 6, "INS-001": 1, "INS-002": 1,
        "INS-003": 2, "INS-004": 4, "INS-005": 3, "INS-006": 4,
        "INS-007": 6, "INS-008": 6, "INS-009": 6, "INS-010": 6,
        "INS-011": 6, "INS-012": 1, "INS-013": 6, "INS-014": 6,
        "INS-015": 6, "INS-016": 6, "INS-017": 6, "INS-018": 6,
        "INS-019": 6, "INS-020": 6, "INS-021": 6, "INS-022": 6,
        "INS-023": 6, "INS-024": 2, "INS-025": 6, "INS-026": 6,
        "INS-027": 1, "INS-028": 1, "INS-029": 1, "INS-030": 6,
        "INS-031": 1, "INS-032": 4, "INS-033": 4, "INS-034": 4,
        "INS-035": 4, "INS-036": 4, "INS-037": 6, "INS-038": 6,
        "INS-039": 6, "INS-040": 6, "INS-041": 6, "INS-042": 6,
        "INS-043": 6, "INS-044": 6, "INS-045": 6, "INS-046": 6,
        "INS-047": 6, "INS-048": 6, "INS-049": 6, "INS-050": 3,
        "INS-051": 6, "INS-052": 6, "INS-053": 6, "INS-054": 6,
        "INS-055": 6, "INS-056": 6, "INS-057": 4, "INS-058": 6,
        "INS-059": 6, "INS-060": 6, "INS-061": 6, "INS-062": 4,
        "INS-063": 6, "INS-064": 4, "INS-065": 6, "INS-066": 5,
        "INS-067": 6, "INS-068": 6, "INS-069": 1, "INS-070": 1,
        "INS-071": 4, "INS-072": 6, "INS-073": 6, "INS-074": 6,
        "INS-075": 6, "INS-076": 6, "INS-077": 6, "INS-078": 6,
        "INS-079": 6, "INS-080": 6, "INS-081": 6, "INS-082": 6,
        "INS-083": 6, "INS-084": 6, "INS-085": 6, "INS-086": 3,
        "INS-087": 3, "INS-088": 1, "INS-089": 6, "INS-090": 1,
        "INS-091": 6, "INS-092": 6, "INS-093": 6, "INS-094": 6,
        "INS-095": 6, "INS-096": 6, "INS-097": 6, "INS-098": 6,
        "INS-099": 6, "INS-100": 6, "INS-101": 1, "INS-102": 1,
        "INS-103": 4, "INS-104": 1, "INS-105": 1, "INS-106": 2,
        "INS-107": 2, "INS-108": 3, "INS-109": 3, "INS-110": 2,
        "INS-111": 2, "INS-112": 3, "INS-113": 2, "INS-114": 6,
        "INS-115": 6, "INS-116": 3, "INS-117": 2, "INS-118": 3,
        "INS-119": 6, "INS-120": 6, "INS-121": 1, "INS-122": 1,
        "INS-123": 1, "INS-124": 1, "INS-125": 1, "INS-126": 1,
        "INS-127": 5, "INS-128": 1, "INS-129": 3, "INS-130": 3,
        "INS-131": 3, "INS-132": 3, "INS-133": 3, "INS-134": 3,
        "INS-135": 5, "INS-136": 4, "INS-137": 5, "INS-138": 2,
        "INS-139": 1, "INS-140": 2, "INS-141": 5, "INS-142": 5,
        "INS-143": 5, "INS-144": 5, "INS-145": 2, "INS-146": 2,
        "INS-147": 4, "INS-148": 6, "INS-149": 2, "INS-150": 5,
        "INS-151": 4, "INS-152": 1, "INS-153": 5, "INS-154": 1,
        "INS-155": 1, "INS-156": 1, "INS-157": 1, "INS-158": 3,
        "INS-159": 3, "INS-160": 3, "INS-161": 3, "INS-162": 3,
        "INS-163": 1, "INS-164": 5, "INS-165": 1, "INS-166": 5,
        "INS-167": 5, "INS-168": 1, "INS-169": 2, "INS-170": 4,
        "JEB-A01": 6, "JEB-A02": 3, "JEB-A03": 3, "JEB-A04": 4,
        "JEB-A05": 3, "JEB-A06": 2, "JEB-A07": 2, "JEB-A08": 1,
        "JEB-A09": 2, "JEB-A10": 4, "JEB-A11": 1, "JEB-A12": 3,
        "JEB-A13": 1, "JEB-A14": 3, "JEB-A15": 4, "JEB-B01": 1,
        "JEB-B02": 2, "JEB-B03": 6, "JEB-B04": 1, "JEB-B05": 5,
        "JEB-B06": 6, "JEB-B07": 4, "JEB-B08": 2, "JEB-B09": 2,
        "JEB-B10": 6, "JEB-B11": 1, "JEB-B12": 2, "JEB-B13": 3,
        "JEB-B14": 1, "JEB-C01": 2, "JEB-C02": 4, "JEB-C03": 2,
        "JEB-C04": 1, "JEB-C05": 2, "JEB-C06": 2, "JEB-C07": 6,
        "JEB-C08": 1, "JEB-C09": 6, "JEB-C10": 6, "JEB-C11": 1,
        "JEB-C12": 3, "JEB-C13": 1, "JEB-C14": 6, "JEB-C15": 1,
        "JEB-D01": 1, "JEB-D02": 2, "JEB-D03": 1, "JEB-D04": 3,
        "JEB-D05": 3, "JEB-D06": 2, "JEB-D07": 5, "JEB-D08": 1,
        "JEB-D09": 5, "JEB-D10": 1, "JEB-D11": 1, "JEB-D12": 1,
        "JEB-D13": 5, "JEB-D14": 1, "JEB-D15": 5, "JEB-E01": 6,
        "JEB-E02": 3, "JEB-E03": 6, "JEB-E04": 3, "JEB-E05": 5,
        "JEB-E06": 4, "JEB-E07": 6, "JEB-E08": 2, "JEB-E09": 2,
        "JEB-E10": 1, "JEB-E11": 1, "JEB-E12": 1, "JEB-E13": 1,
        "JEB-E14": 1, "JEB-E15": 2, "JEB-F01": 6, "JEB-F02": 2,
        "JEB-F03": 6, "JEB-F04": 5, "JEB-F05": 6, "JEB-F06": 6,
        "JEB-F07": 2, "JEB-F08": 6, "JEB-F09": 6, "JEB-F10": 1,
        "JEB-F11": 2, "JEB-F12": 1, "JEB-F13": 5, "JEB-F14": 3,
        "PAI-C001": 1, "PAI-C002": 1, "PAI-C003": 2, "PAI-C004": 1,
        "PAI-C005": 1, "PAI-C006": 1, "PAI-C007": 1, "PAI-C008": 1,
        "PAI-C009": 3, "PAI-C010": 3, "PAI-C011": 3, "PAI-C012": 3,
        "PAI-C013": 3, "PAI-C014": 3, "PAI-C015": 3, "PAI-C016": 3,
        "PAI-C017": 3, "PAI-C018": 4, "PAI-C019": 4, "PAI-C020": 2,
        "PAI-C021": 3, "PAI-C022": 1, "PAI-C023": 1, "PAI-C024": 1,
        "PAI-C025": 4, "PAI-C026": 1, "PAI-C027": 3, "PAI-C028": 3,
        "PAI-C029": 3, "PAI-C030": 3, "PAI-C031": 3, "PAI-C032": 3,
        "PAI-C033": 1, "PAI-C034": 3, "PAI-C035": 2, "PAI-C036": 4,
        "PAI-C037": 3, "PAI-C038": 5, "PAI-C039": 1, "PAI-C040": 1,
        "PAI-C041": 1, "PAI-C042": 3, "PAI-C043": 1, "PAI-C044": 5,
        "PAI-C045": 2, "PAI-C046": 3, "PAI-C047": 4, "PAI-C048": 1,
        "PAI-C049": 5, "PAI-C050": 1, "PAI-C051": 5, "PAI-C052": 1,
        "PAI-C053": 3, "PAI-C054": 2, "PAI-C055": 1, "PAI-C056": 1,
        "PAI-C057": 1, "PAI-C058": 2, "PAI-C059": 1, "PAI-C060": 3,
        "PAI-C061": 2, "PAI-C062": 4, "PAI-C063": 1, "PAI-C064": 2,
        "PAI-C065": 1, "PAI-C066": 1, "PAI-C067": 5, "PAI-C068": 1,
        "PAI-C069": 1, "PAI-C070": 1, "PAI-C071": 5, "PAI-C072": 3,
        "PAI-C073": 3, "PAI-C074": 1, "PAI-C075": 4, "PAI-C076": 4,
        "PAI-C077": 1, "PAI-C078": 1, "PAI-C079": 1, "PAI-C080": 1,
        "PAI-C081": 1, "PAI-C082": 1, "PAI-C083": 1, "PAI-C084": 1,
        "PAI-C085": 1, "PAI-C086": 1, "PAI-C087": 1, "PAI-C088": 1,
        "PAI-C089": 4, "PAI-C090": 3, "PAI-C091": 1, "PAI-C092": 1,
        "PAI-C093": 1, "PAI-C094": 2, "PAI-C095": 1, "PAI-C096": 1,
        "PAI-C097": 1, "PAI-C098": 1, "PAI-C099": 4, "PAI-C100": 1,
        "PAI-C101": 1, "PAI-C102": 1, "RUN3-001": 3, "RUN3-002": 4,
        "RUN3-003": 1, "RUN3-004": 3, "RUN3-005": 3, "RUN3-006": 3,
        "RUN3-007": 1, "RUN3-008": 1, "RUN3-009": 1, "RUN3-010": 1,
        "RUN3-011": 1, "RUN3-012": 1, "RUN3-013": 1, "RUN4-001": 1,
        "RUN4-002": 5, "RUN4-003": 5, "RUN4-004": 1, "RUN4-005": 1,
        "RUN4-006": 1, "RUN4-007": 1, "RUN4-008": 5, "RUN4-009": 1,
        "RUN4-010": 4, "RUN4-011": 4, "RUN4-012": 2, "RUN4-013": 5,
        "RUN4-014": 5, "RUN4-015": 5, "RUN4-016": 5, "RUN4-017": 5,
        "RUN4-018": 1, "RUN4-019": 5, "RUN4-020": 1, "RUN5-001": 1,
        "RUN5-002": 1, "RUN5-003": 1, "RUN5-004": 1, "RUN5-005": 1,
        "RUN5-006": 1, "RUN5-007": 1, "RUN5-008": 1, "RUN6-001": 1,
        "RUN6-002": 1, "RUN6-003": 1, "RUN6-004": 1, "RUN6-005": 6,
        "RUN6-006": 1, "RUN6-007": 1, "RUN6-008": 1, "RUN6-009": 1,
        "RUN6-010": 1, "RUN6-011": 1, "RUN6-012": 2, "RUN6-013": 2,
        "RUN6-014": 5, "RUN6-015": 1, "RUN6-016": 1, "RUN6-017": 1,
        "RUN6-018": 1, "RUN6-019": 1, "RUN6-020": 1, "RUN6-021": 1,
        "RUN6-022": 1, "RUN6-023": 1, "RUN6-024": 1, "RUN6-025": 1,
        "RUN6-026": 1, "RUN6-027": 2, "RUN6-028": 1, "RUN6-029": 1,
        "RUN6-030": 1, "RUN6-031": 1, "RUN6-032": 1, "RUN7-001": 1,
        "RUN7-002": 1, "RUN7-003": 1, "RUN7-004": 1, "RUN7-005": 1,
        "RUN7-006": 3, "RUN7-007": 1, "RUN7-008": 1, "RUN7-009": 1,
        "RUN7-010": 6, "SCN-01": 4, "SCN-02": 4, "SCN-03": 5,
        "SCN-04": 3, "SCN-05": 3, "SCN-06": 3, "SCN-07": 4,
        "SCN-08": 3, "SCN-09": 2, "SCN-10": 4, "SCN-11": 3,
        "SCN-12": 2, "SCN-13": 3, "SCN-14": 3, "SCN-15": 1,
        "SCN-16": 3, "SCN-17": 1, "SCN-18": 2, "SCN-19": 3,
        "SCN-20": 1, "SCN-21": 4, "SCN-22": 3, "SCN-23": 2,
        "SCN-24": 2, "SCN-25": 2, "SCN-26": 6, "SCN-27": 4,
        "SCN-28": 6, "SCN-29": 4, "SCN-30": 3, "SCN-31": 2,
        "SCN-32": 3, "SCN-33": 6, "SCN-34": 4, "SCN-35": 4,
        "SCN-36": 4,
    ]

    /// Lessons for one chapter id prefix, for example "ch1".
    func lessons(forChapterPrefix prefix: String) -> [SearchEntry] {
        allLessons.filter { $0.id.hasPrefix(prefix) }
    }

    // MARK: - Lesson detail

    /// Fetch a lesson page and extract its content.
    /// Falls back to the search index entry if the page cannot be parsed.
    /// Bounded retry (3 attempts, exponential backoff) so a single
    /// transient network failure does not surface as a lesson error.
    func loadLessonDetail(entry: SearchEntry) async throws -> LessonDetail {
        let pageURL = Self.siteBase.appendingPathComponent(entry.url)
        var lastError: Error = ContentError.badResponse
        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(from: pageURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let html = String(data: data, encoding: .utf8) else {
                    throw ContentError.badResponse
                }
                return parseLessonHTML(html, entry: entry)
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
                }
            }
        }
        throw lastError
    }

    /// Extract the lesson from its page. The page embeds the full lesson
    /// as a JSON blob (window.__PA_STUDIO_QUEUE), which is the primary
    /// source for transcript, takeaways, beats, quiz, next lesson,
    /// chapter title and duration. The diagram SVG comes from the
    /// studio-canvas div, and the quiz intro from the quiz score note.
    /// Every <svg> and <script> block is stripped before any HTML text
    /// extraction, so markup can never leak into lesson text. When the
    /// JSON blob is missing, the static HTML sections are used and the
    /// search index entry text is the fallback.
    private func parseLessonHTML(_ html: String, entry: SearchEntry) -> LessonDetail {
        let diagramSVG = extractDiagramSVG(html)
        let quizIntro = extractQuizIntro(html)
        let cleaned = stripSVGAndScriptBlocks(html)

        if let studio = extractStudioJSON(html) {
            let sampleID = studio.sampleID ?? entry.id
            var transcripts: [String] = []
            var takeaways: [String] = []
            var beats: [LessonBeat] = []
            var totalDuration: Double = 0
            var sceneOffset: Double = 0
            for (sceneIndex, scene) in (studio.scenes ?? []).enumerated() {
                var transcript = (scene.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if transcript.isEmpty {
                    let paragraphs = (scene.paragraphs ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    transcript = paragraphs.joined(separator: "\n\n")
                }
                if !transcript.isEmpty { transcripts.append(transcript) }
                takeaways.append(contentsOf: scene.points ?? [])
                for (beatIndex, beat) in (scene.beats ?? []).enumerated() {
                    let title = (beat.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { continue }
                    beats.append(LessonBeat(
                        id: "\(sampleID)-beat-\(sceneIndex)-\(beatIndex)",
                        startTime: sceneOffset + (beat.t0 ?? 0),
                        endTime: sceneOffset + (beat.t1 ?? 0),
                        title: title,
                        note: (beat.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
                let duration = scene.durationSec ?? 0
                totalDuration += duration
                sceneOffset += duration
            }
            if takeaways.isEmpty {
                takeaways = extractListItems(cleaned, sectionMarker: "Key takeaways")
            }
            let transcript = transcripts.joined(separator: "\n\n")
            return LessonDetail(
                id: entry.id,
                title: studio.title ?? entry.title,
                chapterTitle: studio.chapterTitle ?? chapterTitle(for: entry),
                audioFileName: entry.audioFileName ?? (entry.id + ".mp3"),
                transcript: transcript.isEmpty ? entry.text : transcript,
                takeaways: takeaways.isEmpty ? defaultTakeaways(for: entry) : takeaways,
                doThisAtWork: extractListItems(cleaned, sectionMarker: "Do this at work"),
                sources: extractListItems(cleaned, sectionMarker: "Sources"),
                quiz: quizQuestions(from: studio.quiz, lessonID: sampleID),
                nextLessonID: studio.nextID ?? extractNextLessonID(html, currentID: entry.id),
                beats: beats,
                diagramSVG: diagramSVG,
                durationSec: totalDuration,
                nextLessonTitle: studio.nextTitle,
                quizIntro: quizIntro
            )
        }

        // No studio JSON on the page: read the static HTML sections.
        let transcript = extractTranscriptFromHTML(cleaned) ?? entry.text
        let takeaways = extractListItems(cleaned, sectionMarker: "Key takeaways")
        return LessonDetail(
            id: entry.id,
            title: entry.title,
            chapterTitle: chapterTitle(for: entry),
            audioFileName: entry.audioFileName ?? (entry.id + ".mp3"),
            transcript: transcript.isEmpty ? entry.text : transcript,
            takeaways: takeaways.isEmpty ? defaultTakeaways(for: entry) : takeaways,
            doThisAtWork: extractListItems(cleaned, sectionMarker: "Do this at work"),
            sources: extractListItems(cleaned, sectionMarker: "Sources"),
            quiz: [],
            nextLessonID: extractNextLessonID(html, currentID: entry.id),
            beats: [],
            diagramSVG: diagramSVG,
            durationSec: 0,
            nextLessonTitle: nil,
            quizIntro: quizIntro
        )
    }

    private func chapterTitle(for entry: SearchEntry) -> String {
        // The chapter name parsed from the single-line catalogue
        // text (`<lesson title> <chapter name> Part N: <domain> <body>`).
        // Falls back to "Chapter <number>", never to the app name.
        if let name = entry.chapterName { return name }
        if let number = entry.chapterNumber { return "Chapter \(number)" }
        return "Chapter"
    }

    private func defaultTakeaways(for entry: SearchEntry) -> [String] {
        [entry.title, "Listen to the full narration for the worked example.", "Try the quiz below to check your understanding."]
    }

    // MARK: - Studio JSON payload

    /// The lesson JSON blob embedded in each lesson page as
    /// window.__PA_STUDIO_QUEUE.push(["studio-<id>", {...}]).
    private struct StudioPayload: Decodable {
        let sampleID: String?
        let chapterID: String?
        let title: String?
        let chapterTitle: String?
        let nextID: String?
        let nextTitle: String?
        let scenes: [StudioScene]?
        let quiz: [StudioQuizItem]?

        enum CodingKeys: String, CodingKey {
            case sampleID = "sample_id"
            case chapterID = "chapter_id"
            case title
            case chapterTitle = "chapter_title"
            case nextID = "next_id"
            case nextTitle = "next_title"
            case scenes
            case quiz
        }
    }

    private struct StudioScene: Decodable {
        let id: String?
        let title: String?
        let durationSec: Double?
        let transcript: String?
        let paragraphs: [String]?
        let points: [String]?
        let beats: [StudioBeat]?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case durationSec = "duration_sec"
            case transcript
            case paragraphs
            case points
            case beats
        }
    }

    private struct StudioBeat: Decodable {
        let t0: Double?
        let t1: Double?
        let title: String?
        let note: String?
    }

    /// One quiz item from the studio JSON. The correct answer is an
    /// option index: answer_index wins, then answer when it is a number,
    /// then the option whose text matches answer or correct_answer.
    private struct StudioQuizItem: Decodable {
        let question: String?
        let options: [String]?
        let answerIndex: Int?
        let answerText: String?
        let explanation: String?

        enum CodingKeys: String, CodingKey {
            case question
            case options
            case answer
            case answerIndex = "answer_index"
            case correctAnswer = "correct_answer"
            case explanation
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            question = try container.decodeIfPresent(String.self, forKey: .question)
            options = try container.decodeIfPresent([String].self, forKey: .options)
            explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
            var resolvedIndex: Int? = nil
            if let raw = try? container.decodeIfPresent(Int.self, forKey: .answerIndex) {
                resolvedIndex = raw
            } else if let raw = try? container.decodeIfPresent(Int.self, forKey: .answer) {
                resolvedIndex = raw
            }
            answerIndex = resolvedIndex
            var resolvedText: String? = nil
            if let raw = try? container.decodeIfPresent(String.self, forKey: .answer) {
                resolvedText = raw
            }
            if resolvedText == nil {
                resolvedText = try container.decodeIfPresent(String.self, forKey: .correctAnswer)
            }
            answerText = resolvedText
        }
    }

    /// Find the studio JSON object inside
    /// window.__PA_STUDIO_QUEUE.push([...]) and decode it. The scan
    /// respects JSON strings and escapes, so braces inside quoted text
    /// cannot end the object early.
    private func extractStudioJSON(_ html: String) -> StudioPayload? {
        guard let marker = html.range(of: "window.__PA_STUDIO_QUEUE.push([\"studio-") else { return nil }
        guard let braceIndex = html[marker.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = braceIndex
        while index < html.endIndex {
            let ch = html[index]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else if ch == "\"" {
                inString = true
            } else if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let jsonText = String(html[braceIndex...index])
                    guard let data = jsonText.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode(StudioPayload.self, from: data)
                }
            }
            index = html.index(after: index)
        }
        return nil
    }

    /// The lesson diagram SVG from the studio-canvas div. The mobile flow
    /// fits phone widths better, so it is preferred; the desktop flow is
    /// the fallback. Returns the whole <svg>...</svg> string.
    private func extractDiagramSVG(_ html: String) -> String? {
        guard let canvasStart = html.range(of: "<div class=\"studio-canvas\"") else { return nil }
        for flowClass in ["flow-mobile", "flow-desktop"] {
            let marker = "<svg class=\"\(flowClass)\""
            guard let svgStart = html.range(of: marker, range: canvasStart.lowerBound..<html.endIndex),
                  let svgEnd = html.range(of: "</svg>", range: svgStart.upperBound..<html.endIndex) else { continue }
            return String(html[svgStart.lowerBound..<svgEnd.upperBound])
        }
        return nil
    }

    /// The quiz intro line from the page, for example "Answer all 3
    /// questions to see your score. ...". Empty when the page has none.
    private func extractQuizIntro(_ html: String) -> String {
        guard let pStart = html.range(of: "<p class=\"studio-note\" id=\"pf-quiz-score-"),
              let tagEnd = html.range(of: ">", range: pStart.upperBound..<html.endIndex),
              let pEnd = html.range(of: "</p>", range: tagEnd.upperBound..<html.endIndex) else { return "" }
        return stripTags(String(html[tagEnd.upperBound..<pEnd.lowerBound]))
    }

    /// Build real quiz questions from the studio JSON quiz items. Items
    /// with no question, no options, or no resolvable correct option are
    /// skipped instead of inventing True/False options.
    private func quizQuestions(from items: [StudioQuizItem]?, lessonID: String) -> [QuizQuestion] {
        guard let items = items else { return [] }
        var questions: [QuizQuestion] = []
        for (index, item) in items.enumerated() {
            guard let question = item.question?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !question.isEmpty,
                  let options = item.options, !options.isEmpty else { continue }
            var correct = item.answerIndex
            if correct == nil, let answerText = item.answerText,
               let found = options.firstIndex(of: answerText) {
                correct = found
            }
            guard let correctIndex = correct, correctIndex >= 0, correctIndex < options.count else { continue }
            let explanation = (item.explanation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            questions.append(QuizQuestion(
                id: "\(lessonID)-q\(index + 1)",
                question: question,
                options: options,
                correctOptionIndex: correctIndex,
                explanation: explanation.isEmpty ? "See the lesson transcript for the full explanation." : explanation
            ))
        }
        return questions
    }

    // MARK: - HTML helpers

    /// Remove every <script>...</script> and <svg>...</svg> block. This
    /// runs BEFORE any HTML text extraction, so SVG attribute text and
    /// script source can never leak into lesson text, lists or the
    /// transcript.
    private func stripSVGAndScriptBlocks(_ html: String) -> String {
        var result = html
        for pattern in ["<script\\b[^>]*>.*?</script>", "<svg\\b[^>]*>.*?</svg>"] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        return result
    }

    private func stripTags(_ html: String) -> String {
        var result = ""
        var inTag = false
        for ch in html {
            if ch == "<" { inTag = true; continue }
            if ch == ">" { inTag = false; continue }
            if !inTag { result.append(ch) }
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The static "Full lesson text" transcript div, used only when the
    /// studio JSON blob is missing. Paragraphs are kept apart with blank
    /// lines so the text reads as paragraphs, not one run-on block.
    private func extractTranscriptFromHTML(_ html: String) -> String? {
        guard let divStart = html.range(of: "<div id=\"studio-transcript-full-"),
              let tagEnd = html.range(of: ">", range: divStart.upperBound..<html.endIndex),
              let divEnd = html.range(of: "</div>", range: tagEnd.upperBound..<html.endIndex) else { return nil }
        let inner = String(html[tagEnd.upperBound..<divEnd.lowerBound])
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "</h4>", with: "\n\n")
        let cleaned = stripTags(inner)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func extractListItems(_ html: String, sectionMarker: String) -> [String] {
        // Anchor on the real <h2> heading. The page <style> block holds a
        // CSS comment that mentions "Do this at work", so bare text would
        // match the stylesheet instead of the section.
        let heading = "<h2>" + sectionMarker + "</h2>"
        guard let headingRange = html.range(of: heading) else { return [] }
        let afterHeading = html[headingRange.upperBound...]
        var sectionEnd = afterHeading.endIndex
        if let end = afterHeading.range(of: "</section>") {
            sectionEnd = end.lowerBound
        }
        if let endDiv = afterHeading.range(of: "</div>"), endDiv.lowerBound < sectionEnd {
            sectionEnd = endDiv.lowerBound
        }
        let section = String(afterHeading[..<sectionEnd])
        // Match only real list items: "<li>" or "<li " with attributes.
        // Never "<line", "<link" or "<linearGradient".
        guard let liRegex = try? NSRegularExpression(pattern: "<li(?:\\s[^>]*)?>", options: [.caseInsensitive]) else { return [] }
        let nsSection = section as NSString
        let matches = liRegex.matches(in: section, options: [], range: NSRange(location: 0, length: nsSection.length))
        var items: [String] = []
        for match in matches {
            let itemStart = match.range.upperBound
            let closeRange = nsSection.range(of: "</li>", options: [.caseInsensitive], range: NSRange(location: itemStart, length: nsSection.length - itemStart))
            guard closeRange.location != NSNotFound else { continue }
            let raw = nsSection.substring(with: NSRange(location: itemStart, length: closeRange.location - itemStart))
            let cleaned = stripTags(raw)
            if !cleaned.isEmpty { items.append(cleaned) }
        }
        return items
    }

    private func extractNextLessonID(_ html: String, currentID: String) -> String? {
        // Next lesson links use the lessons/<id> path.
        let pattern = "lessons/(ch\\d+s\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        for match in matches {
            if let idRange = Range(match.range(at: 1), in: html) {
                let id = String(html[idRange])
                if id != currentID { return id }
            }
        }
        return nil
    }

    // MARK: - Audio URLs

    /// The primary audio URL for a lesson file.
    static func primaryAudioURL(fileName: String) -> URL {
        URL(string: primaryAudioBase + fileName)!
    }

    /// The fallback audio URL for a lesson file.
    static func fallbackAudioURL(fileName: String) -> URL {
        URL(string: fallbackAudioBase + fileName)!
    }
}

// MARK: - Errors

enum ContentError: Error, LocalizedError {
    case badResponse
    case notFound

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "The website did not respond. Check your connection and try again."
        case .notFound:
            return "That content could not be found."
        }
    }
}
