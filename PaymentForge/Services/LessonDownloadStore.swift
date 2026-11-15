// LessonDownloadStore.swift
// PaymentForge iOS - Explicit per-lesson audio downloads for offline listening.
//
// A lesson is downloaded only when the learner taps Download in the
// unlocked lesson view. Nothing downloads automatically, and locked
// lessons have no download control: the control lives in the unlocked
// lesson view only, under the same gating as playback. This store
// holds no entitlement check of its own; it must only be called from
// the unlocked lesson view.
//
// Files live in Application Support under Downloads, one file per
// lesson, named by the sanitised audio file name. The directory is
// shared across identities: files are not stored per account, and
// download state lives in memory plus file existence, rebuilt from
// disk on launch, never written to UserDefaults. What IS recorded
// per download is an ownership record holding the identity
// namespace at download time ("guest" or the account id), kept in
// UserDefaults under a global key, so sign-out can remove only the
// signing-out identity's files. Files downloaded before ownership
// recording existed have no record and are kept on sign-out:
// their owner is unknown, and deleting another identity's
// downloads is worse than keeping an unattributed file.
//
// Every downloaded file carries Data Protection completeUnlessOpen:
// encrypted at rest, closed to a new open while the device is
// locked, but still readable by playback that already opened the
// file before the lock. Complete would break background playback:
// the app declares the audio background mode and plays with the
// .playback category, so narration must keep playing after the
// device locks. Protection is applied to each new download and,
// on launch, to every file already on disk.
//
// Sandbox rule: downloaded audio stays inside this app's private
// sandbox, like Netflix or Hotstar downloads. It is never shown in
// the Files app, never shared or exported, and it is gone when the
// app is deleted. Every download path must stay in Application
// Support: never move audio to Documents, a shared container, or
// a share sheet.
//
// Downloads use a plain URLSession download task (primary audio host,
// then the fallback host once). A download does NOT continue if the
// app is killed: there is no background URLSession in this run. A
// killed download leaves no partial file, because the file is moved
// into place only after the download completes. The learner taps
// Download again to retry.
// No em dashes in any user-facing text.

import Foundation
import Combine

/// Download state for one lesson's audio.
enum LessonAudioDownloadState: Equatable {
    /// No downloaded file on this device, and no download running.
    case notDownloaded
    /// A download is running.
    case downloading
    /// A downloaded file is on this device.
    case downloaded
    /// The last download attempt failed, with the honest reason.
    case failed(message: String)
}

/// Owns explicit per-lesson audio downloads. One shared instance, so
/// the lesson view and the audio player see the same state.
final class LessonDownloadStore: ObservableObject {
    static let shared = LessonDownloadStore()

    /// Download state per lesson id. Published so the lesson view
    /// updates as a download starts, finishes or fails. Rebuilt from
    /// disk on init; lessons never touched read as .notDownloaded
    /// through state(for:) when no file exists for them.
    @Published private(set) var states: [String: LessonAudioDownloadState] = [:]

    private init() {
        refreshDownloadStatesFromDisk()
        applyProtectionToExistingDownloads()
    }

    /// The download state for one lesson. Lessons with a file on disk
    /// read as .downloaded even when they were never touched in this
    /// launch, because the state was rebuilt from disk on init.
    func state(for lessonID: String) -> LessonAudioDownloadState {
        states[lessonID] ?? .notDownloaded
    }

    /// The ids of lessons with a downloaded file on this device,
    /// derived from the files actually present, not from memory.
    /// Computed, not published: views observe `states` for updates.
    var downloadedLessonIDs: Set<String> {
        Set(downloadedFileStems())
    }

    /// Rebuild the in-memory states from the files on disk. Called on
    /// init; also safe to call after files change outside this store.
    /// A download in progress is never overwritten by a rescan.
    func refreshDownloadStatesFromDisk() {
        let onDisk = Set(downloadedFileStems())
        for lessonID in onDisk {
            if states[lessonID] != .downloading {
                states[lessonID] = .downloaded
            }
        }
        for lessonID in states.keys where !onDisk.contains(lessonID) && states[lessonID] != .downloading {
            states[lessonID] = .notDownloaded
        }
    }

    // MARK: - File protection

    /// The Data Protection class for downloaded audio files.
    /// completeUnlessOpen, not complete: complete makes a file
    /// unreadable the moment the device locks, even to playback
    /// that already opened it, which would kill the background and
    /// lock-screen playback this app declares (UIBackgroundModes
    /// audio in Info.plist, .playback category in
    /// AudioPlayerService). completeUnlessOpen keeps an
    /// already-open file readable after the lock, while the file
    /// stays encrypted at rest and cannot be newly opened while
    /// locked. Playback started while locked falls back to
    /// streaming through the existing failover in
    /// AudioPlayerService, which treats an unplayable downloaded
    /// copy as a cue to stream.
    static let downloadFileProtection: FileProtectionType = .completeUnlessOpen

    /// Apply the download protection class to one file or
    /// directory. Best effort: a failure leaves the file with
    /// whatever protection it already had and never fails the
    /// download or the launch scan that calls this.
    static func applyDownloadProtection(to url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: downloadFileProtection],
            ofItemAtPath: url.path
        )
    }

    /// Apply file protection to every downloaded file already on
    /// disk, plus the Downloads directory itself. Called once from
    /// init, so files downloaded before protection existed gain it
    /// on the next launch. Idempotent: re-applying the same class
    /// to an already protected file is a no-op in effect.
    private func applyProtectionToExistingDownloads() {
        let directory = Self.downloadsDirectoryURL()
        Self.applyDownloadProtection(to: directory)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in urls where url.pathExtension.lowercased() == "mp3" {
            Self.applyDownloadProtection(to: url)
        }
    }

    // MARK: - Download ownership

    /// UserDefaults key prefix for download ownership records. Each
    /// record maps one stored file stem to the identity namespace
    /// that downloaded it ("guest" or the account id). The keys are
    /// deliberately global, not namespaced through
    /// AccountScopedStorage: sign-out must read them across the
    /// namespace switch, and the lookup is by file, not by the
    /// identity reading it. A record holds only the namespace
    /// string, no other personal data. Ownership is per stored
    /// file stem, matching the one-file-per-stem storage: two
    /// lesson ids that sanitise to the same stem already share
    /// one file, so they share one record, owned by the latest
    /// downloader.
    private static let ownerKeyPrefix = "pf.download.owner.v1."

    /// The sanitised stem for a lesson id: only letters, numbers,
    /// hyphen and underscore survive. Shared by the stored file
    /// name and the ownership record, so the two can never drift.
    private static func sanitisedLessonStem(for lessonID: String) -> String {
        String(lessonID.map { char in
            (char.isLetter || char.isNumber || char == "-" || char == "_") ? char : "-"
        })
    }

    /// The ownership-record key for one lesson.
    private static func ownerKey(for lessonID: String) -> String {
        ownerKeyPrefix + sanitisedLessonStem(for: lessonID)
    }

    /// The identity namespace recorded as the downloader of one
    /// lesson's file, nil when no record exists (downloaded before
    /// ownership recording, or the record was cleared with the
    /// file). Nil means unknown owner, never guest.
    static func ownerNamespace(for lessonID: String) -> String? {
        UserDefaults.standard.string(forKey: ownerKey(for: lessonID))
    }

    /// Record the current identity as the downloader of one lesson.
    /// Called only after the file has been moved into place.
    private static func recordOwner(for lessonID: String) {
        UserDefaults.standard.set(AccountScopedStorage.currentNamespace, forKey: ownerKey(for: lessonID))
    }

    /// Clear the ownership record for one lesson. Called when its
    /// file is removed, so a later download by another identity
    /// starts from a clean record.
    private static func clearOwner(for lessonID: String) {
        UserDefaults.standard.removeObject(forKey: ownerKey(for: lessonID))
    }

    /// Clear every ownership record. Called only by
    /// removeAllDownloads, which removes every file with them.
    private static func clearAllOwnerRecords() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(ownerKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - File locations

    /// The Downloads directory in Application Support (persistent,
    /// not the purgeable Caches directory).
    static func downloadsDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    /// The stored file name for an audio file name. Only letters,
    /// numbers, hyphen, underscore and one dot survive; every other
    /// character becomes a hyphen, so a file name can never escape
    /// the Downloads directory. An empty result maps to "audio.mp3".
    static func sanitisedDownloadFileName(for fileName: String) -> String {
        let safe = fileName.map { char in
            (char.isLetter || char.isNumber || char == "-" || char == "_" || char == ".") ? char : "-"
        }
        let result = String(safe)
        return result.isEmpty ? "audio.mp3" : result
    }

    /// The stored file URL for one lesson, nil when the file name does
    /// not belong to the lesson id. Audio file names are always the
    /// lesson id plus ".mp3", so the stem must match the sanitised
    /// lesson id; a mismatch returns nil rather than the wrong file.
    /// Pure URL resolution, no disk access, so it is covered by
    /// unit tests.
    static func downloadFileURL(in directory: URL, lessonID: String, fileName: String) -> URL? {
        guard !fileName.isEmpty, !lessonID.isEmpty else { return nil }
        let sanitised = sanitisedDownloadFileName(for: fileName)
        let stem = (sanitised as NSString).deletingPathExtension
        let lessonStem = lessonID.map { char in
            (char.isLetter || char.isNumber || char == "-" || char == "_") ? char : "-"
        }
        guard stem == String(lessonStem) else { return nil }
        return directory.appendingPathComponent(sanitised)
    }

    /// The destination URL for one lesson's download, nil when the
    /// file name does not belong to the lesson id.
    func destinationURL(for lessonID: String, fileName: String) -> URL? {
        Self.downloadFileURL(in: Self.downloadsDirectoryURL(), lessonID: lessonID, fileName: fileName)
    }

    /// The local file URL for a lesson's downloaded audio, nil when
    /// no downloaded file exists for that lesson. File existence is
    /// the source of truth, so playback works even before the
    /// in-memory state is consulted.
    func downloadedAudioURL(for lessonID: String, fileName: String) -> URL? {
        guard let url = destinationURL(for: lessonID, fileName: fileName),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// The lesson ids implied by the files on disk: each ".mp3" file
    /// stem, in no particular order.
    private func downloadedFileStems() -> [String] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: Self.downloadsDirectoryURL(),
            includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "mp3" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    // MARK: - Download and remove

    /// Download one lesson's audio to this device. Primary host first,
    /// then the fallback host once. A lesson that is already
    /// downloaded, or already downloading, is left alone. State
    /// updates happen on the main actor, so the lesson view updates.
    /// The download does not continue if the app is killed.
    func downloadAudio(for entry: SearchEntry) async {
        guard let fileName = entry.audioFileName else {
            await MainActor.run { states[entry.id] = .failed(message: "This item has no audio to download.") }
            return
        }
        guard let destination = destinationURL(for: entry.id, fileName: fileName) else {
            await MainActor.run { states[entry.id] = .failed(message: "This lesson audio could not be saved on this device.") }
            return
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            await MainActor.run { states[entry.id] = .downloaded }
            return
        }
        if states[entry.id] == .downloading {
            return
        }
        await MainActor.run { states[entry.id] = .downloading }
        let hosts = [ContentService.primaryAudioURL(fileName: fileName), ContentService.fallbackAudioURL(fileName: fileName)]
        for url in hosts {
            do {
                let (tempURL, response) = try await URLSession.shared.download(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    continue
                }
                try FileManager.default.createDirectory(at: Self.downloadsDirectoryURL(), withIntermediateDirectories: true)
                Self.applyDownloadProtection(to: Self.downloadsDirectoryURL())
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                Self.applyDownloadProtection(to: destination)
                Self.recordOwner(for: entry.id)
                await MainActor.run { states[entry.id] = .downloaded }
                return
            } catch {
                continue
            }
        }
        await MainActor.run {
            states[entry.id] = .failed(message: "The download could not be completed. Check your connection and try again.")
        }
    }

    /// Remove a lesson's downloaded audio from this device. The lesson
    /// itself is untouched; streaming still works afterwards. The
    /// ownership record goes with the file.
    func removeDownload(for lessonID: String) {
        let directory = Self.downloadsDirectoryURL()
        let fileName = Self.sanitisedLessonStem(for: lessonID) + ".mp3"
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
        Self.clearOwner(for: lessonID)
        states[lessonID] = .notDownloaded
    }

    /// Remove a lesson's downloaded audio, by entry. Same as
    /// removeDownload(for:) with the entry id.
    func removeDownload(for entry: SearchEntry) {
        removeDownload(for: entry.id)
    }

    /// Remove only the downloads recorded as owned by the given
    /// identity namespace. Called from sign-out and account
    /// deletion with the departing account's id. Guest downloads
    /// (owner "guest"), downloads owned by another identity, and
    /// files with no ownership record are all kept: the record is
    /// the only proof of ownership, and an unknown owner must
    /// never be treated as the signing-out identity. A download
    /// still in progress is never removed: its file does not exist
    /// yet, and the rescan below leaves .downloading states alone.
    /// Call on the main thread: it updates published states.
    func removeDownloadsOwned(by namespace: String) {
        guard !namespace.isEmpty else { return }
        let directory = Self.downloadsDirectoryURL()
        for stem in downloadedFileStems() {
            guard Self.ownerNamespace(for: stem) == namespace else { continue }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(stem + ".mp3"))
            Self.clearOwner(for: stem)
        }
        refreshDownloadStatesFromDisk()
    }

    /// Remove every downloaded file on this device, whatever
    /// identity downloaded it, and clear every ownership record.
    /// This is the hook for the refund-revoke path (C3): when a
    /// purchase is refunded, the revoked content must not stay
    /// playable offline. Deliberately NOT called from sign-out:
    /// sign-out removes only the signing-out identity's files
    /// (see removeDownloadsOwned(by:)). A download still in
    /// progress is not stopped; if it completes afterwards it
    /// re-creates its file, and the revoke path must re-check.
    /// Call on the main thread: it updates published states.
    func removeAllDownloads() {
        let directory = Self.downloadsDirectoryURL()
        for stem in downloadedFileStems() {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(stem + ".mp3"))
        }
        Self.clearAllOwnerRecords()
        refreshDownloadStatesFromDisk()
    }

    /// Remove downloaded audio for lessons in the given chapters.
    /// Used when a purchase is revoked: the buyer keeps downloads
    /// only for content they still own. Lesson ids carry their
    /// chapter ("ch<number>s<...>"); an id that does not parse is
    /// never removed. Call on the main thread: it updates
    /// published states through removeDownload(for:).
    func removeDownloads(forChapterIDs chapterIDs: Set<String>) {
        guard !chapterIDs.isEmpty else { return }
        for lessonID in downloadedLessonIDs {
            guard let chapterID = Self.chapterID(for: lessonID),
                  chapterIDs.contains(chapterID) else { continue }
            removeDownload(for: lessonID)
        }
    }

    /// The chapter id ("ch<number>") for a lesson id, or nil when
    /// the id does not follow the ch<number>s<...> shape.
    private static func chapterID(for lessonID: String) -> String? {
        guard lessonID.hasPrefix("ch") else { return nil }
        let digits = lessonID.dropFirst(2).prefix(while: { $0.isNumber })
        guard !digits.isEmpty,
              lessonID.dropFirst(2 + digits.count).hasPrefix("s") else { return nil }
        return "ch\(digits)"
    }
}
