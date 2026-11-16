// DiagnosticsView.swift
// Payments Training Hub iOS - Diagnostics: device info, saved crash
// reports, and recent activity. Nothing here leaves the device
// except when the learner copies or shares it.

import SwiftUI
import UniformTypeIdentifiers

/// Diagnostics, presented from the drawer. Shows the device info
/// line, any saved crash reports with their full text, and the
/// recent activity breadcrumbs. Own navigation stack with a Done
/// button, matching the other drawer sheets.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var reports: [CrashCapture.CrashReportInfo] = []
    @State private var breadcrumbs: [String] = []
    @State private var deviceInfoCopied = false
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(CrashCapture.deviceInfo())
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(deviceInfoCopied ? "Copied" : "Copy device info") {
                        UIPasteboard.general.string = CrashCapture.deviceInfo()
                        deviceInfoCopied = true
                    }
                } header: {
                    Text("Device info")
                } footer: {
                    Text("No account details or identifiers are included.")
                }

                if CrashCapture.previousDeathUnreported {
                    Section {
                        Text("The last run ended without a crash report and without reaching the background cleanly. That can mean the app was closed by the system, or a fault the recorder cannot capture.")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        Text("Last run")
                    }
                }

                Section {
                    if reports.isEmpty {
                        Text("No crash reports have been saved.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    } else {
                        ForEach(reports) { report in
                            NavigationLink(destination: CrashReportDetailView(report: report)) {
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(report.headline)
                                        .font(.pfBody)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(report.writtenAt, style: .date)
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                }
                            }
                        }
                        Button("Clear all reports", role: .destructive) {
                            showClearConfirmation = true
                        }
                    }
                } header: {
                    Text("Crash reports")
                } footer: {
                    Text("Reports stay on this device. Share one only if you choose to, from its detail screen.")
                }

                Section {
                    if breadcrumbs.isEmpty {
                        Text("No recent activity has been recorded.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    } else {
                        ForEach(breadcrumbs, id: \.self) { entry in
                            Text(entry)
                                .font(.pfCaption)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } header: {
                    Text("Recent activity")
                } footer: {
                    Text("Short records of playback actions only. No lesson content and no personal details are recorded.")
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                reports = CrashCapture.listReports()
                breadcrumbs = CrashBreadcrumbs.persistedEntries()
            }
            .confirmationDialog(
                "Clear all crash reports?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear all reports", role: .destructive) {
                    CrashCapture.clearReports()
                    reports = []
                }
                Button("Keep reports", role: .cancel) {}
            } message: {
                Text("Saved reports cannot be recovered once cleared.")
            }
        }
    }
}

/// The full text of one crash report, with Copy and Share.
private struct CrashReportDetailView: View {
    let report: CrashCapture.CrashReportInfo

    @State private var reportText: String? = nil
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                if let text = reportText {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack(spacing: PFSpacing.md) {
                        Button(copied ? "Copied" : "Copy report") {
                            UIPasteboard.general.string = text
                            copied = true
                        }
                        ShareLink(item: text) {
                            Text("Share report")
                        }
                    }
                } else {
                    Text("This report could not be read.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
            }
            .padding(PFSpacing.lg)
        }
        .navigationTitle("Crash report")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reportText = CrashCapture.readReport(fileName: report.fileName)
        }
    }
}
