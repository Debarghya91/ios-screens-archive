// CrashCapture.swift
// Payments Training Hub iOS - in-app crash capture.
// No stack trace exists for crashes the owner sees on a device with
// no cable workflow, so the app records its own fatal exceptions:
// an uncaught-exception handler writes a report to app-private
// storage, capped at the 5 newest files, each capped at 64 KB, and
// chains to the previous handler so the process still dies
// normally. A report is never swallowed, never uploaded, and never
// leaves the device except when the learner shares it from the
// Diagnostics view.
//
// Breadcrumbs are short action records ("audio play ch54s2") kept
// in a 50-entry ring and attached to the report. No user content
// and no PII is recorded: lesson ids and playback state only.
//
// Scope guard: Objective-C exceptions only. A Swift trap
// (force unwrap, out-of-bounds access, fatalError) bypasses the
// handler and leaves no report; the run-marker heuristic in
// previousDeathUnreported tells those deaths apart from clean runs.

import Foundation
import UIKit

/// The directory crash data lives in: Application Support, with
/// the temporary directory as a fallback. Never force unwrapped.
private func crashDataDirectory() -> URL {
    if let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        return directory
    }
    return FileManager.default.temporaryDirectory
}

// MARK: - Breadcrumbs

/// Short action records attached to crash reports. Thread-safe.
/// Entries are also persisted to pf-breadcrumbs.json, so the
/// Diagnostics view can show recent activity even after a kill
/// that bypassed the exception handler.
enum CrashBreadcrumbs {
    static let maxEntries = 50
    static let maxEntryChars = 120

    private static let lock = NSLock()
    private static var entries: [String] = []
    private static let persistQueue = DispatchQueue(label: "com.paymentstraininghub.crashbreadcrumbs")
    private static let fileName = "pf-breadcrumbs.json"

    private static var fileURL: URL {
        crashDataDirectory().appendingPathComponent(fileName)
    }

    /// Record one breadcrumb. Old entries drop off past maxEntries.
    static func record(_ entry: String) {
        let capped = String(entry.prefix(maxEntryChars))
        lock.lock()
        entries.append(capped)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        let snapshot = entries
        lock.unlock()
        persistQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: fileURL, options: [.atomic])
            }
        }
    }

    /// A snapshot of the recorded entries, oldest first.
    static func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// A snapshot for the crash handler: never blocks, so a crash
    /// inside record() itself cannot deadlock the report write.
    static func snapshotForCrashReport() -> [String] {
        guard lock.try() else { return [] }
        defer { lock.unlock() }
        return entries
    }

    /// The persisted entries, oldest first. Used by the
    /// Diagnostics view for recent activity.
    static func persistedEntries() -> [String] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Drop every recorded entry. Used by tests.
    static func clear() {
        lock.lock()
        entries = []
        lock.unlock()
        persistQueue.async {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}

// MARK: - Crash capture

enum CrashCapture {
    /// The newest report files kept; older ones are pruned on install.
    static let maxReportFiles = 5
    /// Each report is truncated to this many characters before writing.
    static let maxReportChars = 64 * 1024

    private static let reportsDirectoryName = "CrashReports"
    private static let markerFileName = "last-run.txt"
    private static let cleanExitFileName = "clean-exit.txt"

    /// One saved report, for the Diagnostics list.
    struct CrashReportInfo: Identifiable, Hashable {
        let fileName: String
        let writtenAt: Date
        let headline: String
        var id: String { fileName }
    }

    /// A snapshot of the audio state for the report. Reads state
    /// values only: never touch the AVPlayer instance from the
    /// crashing thread.
    static var audioStateProvider: (() -> String)?

    private static var installed = false
    private static let crashLock = NSLock()
    private static var handlingCrash = false
    private static var previousHandler: (@convention(c) (NSException) -> Void)?

    /// True when the previous run ended without writing a crash
    /// report and without reaching the background cleanly: that
    /// points at a Swift trap or a low-memory kill, which no
    /// exception handler can record. False on the first launch,
    /// false when the previous run left a report, and false when
    /// it reached the background (a jetsam kill from the
    /// background is normal and is not flagged).
    private(set) static var previousDeathUnreported = false

    /// Install the handler. Call first in the app init, before any
    /// other setup, so even an early crash is captured. Safe to
    /// call twice: the second call is a no-op.
    static func install() {
        guard !installed else { return }
        installed = true
        previousDeathUnreported = computePreviousDeathUnreported()
        markEnteredForeground()
        writeRunMarker()
        pruneReports()
        previousHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            CrashCapture.writeReport(for: exception)
            // Chain: the process must still die normally. Never
            // swallow a fatal exception.
            CrashCapture.previousHandler?(exception)
        }
    }

    /// Mark a clean exit path: the app reached the background
    /// without crashing. Called on scenePhase background.
    static func markCleanExit() {
        let url = reportsDirectory().appendingPathComponent(cleanExitFileName)
        try? FileManager.default.createDirectory(at: reportsDirectory(), withIntermediateDirectories: true)
        try? Data().write(to: url, options: [.atomic])
    }

    /// Clear the clean-exit mark: the app is in the foreground
    /// again, so a crash from here counts as unreported.
    static func markEnteredForeground() {
        try? FileManager.default.removeItem(at: reportsDirectory().appendingPathComponent(cleanExitFileName))
    }

    /// The saved reports, newest first. Never throws.
    static func listReports() -> [CrashReportInfo] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: reportsDirectory(),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else { return [] }
        let reports = files.compactMap { url -> CrashReportInfo? in
            guard url.lastPathComponent.hasPrefix("crash-"), url.pathExtension == "txt" else { return nil }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { return nil }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return CrashReportInfo(
                fileName: url.lastPathComponent,
                writtenAt: values.contentModificationDate ?? Date.distantPast,
                headline: headlineFor(text)
            )
        }
        return reports.sorted { $0.writtenAt > $1.writtenAt }
    }

    /// The full text of one report, or nil when it cannot be read.
    static func readReport(fileName: String) -> String? {
        // The file name comes from our own list; reject anything
        // that could escape the reports directory anyway.
        guard !fileName.contains("/"), !fileName.contains("..") else { return nil }
        let url = reportsDirectory().appendingPathComponent(fileName)
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Delete every saved report. Never throws.
    static func clearReports() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: reportsDirectory(), includingPropertiesForKeys: nil) else { return }
        for url in files where url.lastPathComponent.hasPrefix("crash-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// One block of device info for the Diagnostics view and for
    /// pasting into a support message: model, iOS version, app
    /// version, and free storage. No identifiers of any kind.
    static func deviceInfo() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let device = UIDevice.current
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(String(UnicodeScalar(UInt8(value))))
        }
        let freeText: String
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeBytes = attributes[.systemFreeSize] as? NSNumber {
            freeText = "\(freeBytes.int64Value / (1024 * 1024)) MB free"
        } else {
            freeText = "free storage unknown"
        }
        let model = machine.isEmpty ? device.model : machine
        return "Payments Training Hub \(version) (build \(build)), \(model), \(device.systemName) \(device.systemVersion), \(freeText)"
    }

    /// The first exception line of a report, for the list row.
    /// Pure and unit-tested: the report header carries the
    /// exception headline on its own line, and anything else
    /// falls back to the first non-blank line.
    static func headlineFor(_ reportText: String) -> String {
        let lines = reportText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for line in lines where line.hasPrefix("Exception: ") {
            return line.dropFirst("Exception: ".count).trimmingCharacters(in: .whitespaces)
        }
        return lines.first ?? "Crash report"
    }

    /// Which files to keep when pruning: the maxCount newest by
    /// modification time. Pure and unit-tested; the file layer
    /// only supplies (name, modified) pairs.
    static func filesToKeep(_ files: [(name: String, modified: Date)], maxCount: Int) -> Set<String> {
        Set(files.sorted { $0.modified > $1.modified }.prefix(maxCount).map { $0.name })
    }

    /// Truncate report text to the write cap. Pure and unit-tested.
    static func truncateReport(_ text: String) -> String {
        if text.count > maxReportChars {
            return String(text.prefix(maxReportChars)) + "\n[truncated]"
        }
        return text
    }

    private static func reportsDirectory() -> URL {
        crashDataDirectory().appendingPathComponent(reportsDirectoryName)
    }

    private static func writeRunMarker() {
        let directory = reportsDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = "\(Date().timeIntervalSince1970)"
        try? marker.write(to: directory.appendingPathComponent(markerFileName), atomically: true, encoding: .utf8)
    }

    private static func computePreviousDeathUnreported() -> Bool {
        let directory = reportsDirectory()
        let markerURL = directory.appendingPathComponent(markerFileName)
        guard let markerText = try? String(contentsOf: markerURL, encoding: .utf8),
              let markerSeconds = Double(markerText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        // The previous run reached the background cleanly: a later
        // jetsam kill is normal, not an unreported crash.
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(cleanExitFileName).path) {
            return false
        }
        let newestReport = listReports().map { $0.writtenAt.timeIntervalSince1970 }.max() ?? 0
        // The previous run started at markerSeconds. A report from
        // that run would be newer than the marker. No such report
        // means the process died without one.
        return newestReport < markerSeconds
    }

    private static func pruneReports() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: reportsDirectory(),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else { return }
        let crashFiles = files.compactMap { url -> (name: String, modified: Date, url: URL)? in
            guard url.lastPathComponent.hasPrefix("crash-"), url.pathExtension == "txt" else { return nil }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { return nil }
            return (url.lastPathComponent, values.contentModificationDate ?? Date.distantPast, url)
        }
        let keep = filesToKeep(crashFiles.map { (name: $0.name, modified: $0.modified) }, maxCount: maxReportFiles)
        for file in crashFiles where !keep.contains(file.name) {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    private static func writeReport(for exception: NSException) {
        // Re-entrancy guard: if writing a report throws, the
        // handler would otherwise recurse until the stack is gone.
        crashLock.lock()
        let alreadyHandling = handlingCrash
        handlingCrash = true
        crashLock.unlock()
        guard !alreadyHandling else { return }
        defer {
            crashLock.lock()
            handlingCrash = false
            crashLock.unlock()
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timeText = formatter.string(from: Date())
        var report = ""
        report += "Payments Training Hub crash report\n"
        report += "Time: \(timeText)\n"
        report += "Device: \(deviceInfo())\n"
        report += "Exception: \(exception.name.rawValue): \(exception.reason ?? "(no reason)")\n"
        report += "\nStack trace:\n"
        let symbols = exception.callStackSymbols
        report += symbols.isEmpty ? "(no symbols)\n" : symbols.joined(separator: "\n") + "\n"
        report += "\nBreadcrumbs:\n"
        let crumbs = CrashBreadcrumbs.snapshotForCrashReport()
        report += crumbs.isEmpty ? "(none)\n" : crumbs.joined(separator: "\n") + "\n"
        report += "\nAudio state:\n"
        report += (audioStateProvider?() ?? "(unknown)") + "\n"
        let directory = reportsDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("crash-\(timestamp).txt")
        try? truncateReport(report).write(to: url, atomically: true, encoding: .utf8)
        pruneReports()
    }
}
