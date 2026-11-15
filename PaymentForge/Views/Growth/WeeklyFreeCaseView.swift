// WeeklyFreeCaseView.swift
// PaymentForge iOS - The free payment case of the week: one real
// situation every week, free to open,
// with no purchase and no sign-in.
//
// The case is picked deterministically by WeeklyFreeCaseSelector:
// the same week and the same list always pick the same case, on
// every device, with no server. The pick prefers the dedicated
// 52-case weekly list when it has loaded, and keeps the
// catalogue pick as the fallback while it has not, so the
// feature never breaks before the weekly asset is deployed.
// The case detail itself is SituationDetailView, the same detail
// every other case uses, so
// the weekly case renders exactly like a case opened from Payment
// Cases, including its Practice Mode entry. The weekly path marks
// the detail with isWeeklyFreeCase, the D101 exemption for this
// path only: the gating rule itself lives in SituationDetailView,
// and the weekly case is free by design under this brief, as the
// one free case outside the six free samples. The detail's
// upsell card still appears for a case that is not a free sample
// when Payment Situations is not unlocked, which stays truthful
// about the full set.
// No em dashes in any user-facing text.

import SwiftUI
import UIKit

// MARK: - Opened marker (per account, device only)

/// Records which weekly cases the learner opened, one marker per
/// ISO week, so the view can say "You opened this week's case".
/// Device only, namespaced per account through
/// AccountScopedStorage: one learner's opened weeks are never
/// served to another. The store re-reads on every refresh, so a
/// view that calls refresh on appear always shows the current
/// account's markers even before AuthService wires the reload
/// call for this store.
final class WeeklyFreeCaseStore: ObservableObject {
    static let shared = WeeklyFreeCaseStore()

    private enum Keys {
        static let opened = "pf.weeklyFreeCase.opened.v1"
    }

    /// Week keys ("2026-W46") to the situation id opened that week.
    @Published private(set) var openedByWeek: [String: String] = [:]

    init() {
        load()
    }

    /// Reload for the current account namespace, clearing the
    /// previous account's markers first.
    func reloadForCurrentAccount() {
        openedByWeek = [:]
        load()
    }

    /// Re-read the current account's markers. The weekly view
    /// calls this on appear.
    func refresh() {
        load()
    }

    /// True when the learner opened a case for this week key.
    func hasOpened(weekKey: String) -> Bool {
        openedByWeek[weekKey] != nil
    }

    /// The situation id opened for this week key, if any.
    func openedSituationID(forWeekKey weekKey: String) -> String? {
        openedByWeek[weekKey]
    }

    /// Record that the learner opened this week's case.
    func markOpened(weekKey: String, situationID: String) {
        guard !weekKey.isEmpty, !situationID.isEmpty else { return }
        openedByWeek[weekKey] = situationID
        save()
    }

    private func load() {
        AccountScopedStorage.adoptLegacyKey(Keys.opened)
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: AccountScopedStorage.currentKey(Keys.opened)),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            openedByWeek = decoded
        } else {
            openedByWeek = [:]
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(openedByWeek) {
            UserDefaults.standard.set(data, forKey: AccountScopedStorage.currentKey(Keys.opened))
        }
    }
}

// MARK: - The weekly free case

/// One free payment case every week. The root shows the week, the
/// case title and an invite card; opening the case shows the full
/// case detail. Presented as a sheet from the side drawer and
/// from the weekly-case deep link, inside the sheet's own
/// NavigationStack, so this view carries no stack of its own.
struct WeeklyFreeCaseView: View {
    @EnvironmentObject private var contentService: ContentService
    @ObservedObject private var weeklyStore = WeeklyFreeCaseStore.shared

    @State private var linkedInTextCopied = false

    /// All situations, full data first and search index fallback,
    /// in catalogue order, the same order SituationsView shows.
    /// The weekly pick depends on this order staying stable.
    private var allSituations: [Situation] {
        if let full = contentService.fullSituations, !full.isEmpty {
            return full.map { situation(fromFull: $0) }
        }
        return contentService.allSituations.map { situation(from: $0) }
    }

    /// The dedicated weekly-case list, when it has loaded, in
    /// week order: the order the website build ships it in. The
    /// weekly pick prefers this list; see weeklySituation.
    private var weeklyCaseItems: [Situation]? {
        guard let weekly = contentService.weeklyCases, !weekly.isEmpty else { return nil }
        return weekly.map { situation(fromFull: $0) }
    }

    private var today: Date { Date() }

    private var weekKey: String {
        WeeklyFreeCaseSelector.weekKey(for: today)
    }

    private var weekLabel: String {
        WeeklyFreeCaseSelector.weekLabel(for: today)
    }

    /// This week's case, picked deterministically. The dedicated
    /// weekly-case list wins when it has loaded; otherwise the
    /// pick falls back to the catalogue order, exactly as before.
    /// Nil while the catalogue is loading.
    private var weeklySituation: Situation? {
        if let items = weeklyCaseItems {
            guard let pickedID = WeeklyFreeCaseSelector.situationID(
                from: items.map(\.id), on: today
            ) else { return nil }
            return items.first { $0.id == pickedID }
        }
        guard let pickedID = WeeklyFreeCaseSelector.situationID(
            from: allSituations.map(\.id), on: today
        ) else { return nil }
        return allSituations.first { $0.id == pickedID }
    }

    /// "Case N of 52" for this week's pick, from its position in
    /// the weekly-case list. Nil when the catalogue fallback is in
    /// use, so no position is claimed for a catalogue pick.
    private var weeklyCasePositionLabel: String? {
        guard let items = weeklyCaseItems,
              let picked = WeeklyFreeCaseSelector.index(for: today, count: items.count) else { return nil }
        return "Case \(picked + 1) of \(items.count)"
    }

    /// The invite for this week's free case: text plus the
    /// website link, local only, no reward offered.
    private var invite: ReferralInvite { ReferralInvite.weeklyFreeCase() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                headerCard

                if contentService.isShowingCachedContent {
                    PFOfflineBanner()
                }

                if let situation = weeklySituation {
                    caseCard(for: situation, positionLabel: weeklyCasePositionLabel)
                    inviteCard
                    aboutCard
                } else if contentService.isLoadingIndex && contentService.searchIndex == nil {
                    VStack(spacing: PFSpacing.md) {
                        ProgressView()
                        Text("Loading this week's free case...")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, PFSpacing.xxl)
                } else {
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            PFIconTile(systemImage: "briefcase.fill", size: 48)
                            Text("This week's case is not available yet")
                                .font(.pfSectionTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Check your connection and try again. The free case appears once the catalogue has loaded.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            PFPrimaryButton(title: "Try again") {
                                Task {
                                    await contentService.loadSearchIndex()
                                    await contentService.loadFullSituations()
                                    await contentService.loadWeeklyCases()
                                }
                            }
                        }
                    }
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Free Case of the Week")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            weeklyStore.refresh()
        }
        .task {
            await contentService.loadFullSituations()
            await contentService.loadWeeklyCases()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            HStack(spacing: PFSpacing.sm) {
                Text("Free every week")
                    .font(.pfCaption.weight(.bold))
                    .tracking(1)
                    .foregroundColor(.pfGold)
                Rectangle()
                    .fill(Color.pfGold)
                    .frame(width: 28, height: 2)
                    .cornerRadius(1)
            }
            Text("One real payment case, free this week")
                .font(.pfHeroTitle)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(weekLabel). A new case appears every Monday. Free to open, no purchase and no sign-in needed.")
                .font(.pfBody)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if weeklyStore.hasOpened(weekKey: weekKey) {
                Label("You opened this week's case", systemImage: "checkmark.circle.fill")
                    .font(.pfCaptionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
            }
        }
        .padding(PFSpacing.xl)
        .background(Color.pfHeroGradient)
        .cornerRadius(PFSpacing.cardRadius)
        .shadow(color: Color.pfNavy.opacity(0.30), radius: 20, x: 0, y: 10)
    }

    // MARK: - Case card

    private func caseCard(for situation: Situation, positionLabel: String? = nil) -> some View {
        NavigationLink(
            destination: WeeklyCaseDetailHost(situation: situation, weekKey: weekKey)
        ) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: situation.stageName)
                        if let positionLabel = positionLabel {
                            PFPill(text: positionLabel)
                        }
                        PFPill(
                            text: situation.level.displayName,
                            background: Color.pfGoldSoft,
                            foreground: Color.pfGoldText
                        )
                        if let schemeName = scheme(for: situation) {
                            PFPill(text: schemeName)
                        }
                        Spacer()
                    }
                    Text(situation.title)
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    if let readLabel = ReadTime.label(for: situation.explain + " " + situation.takeaway) {
                        Label(readLabel, systemImage: "clock")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                    HStack {
                        Text("Open this week's case")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.white)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, PFSpacing.lg)
                    .background(Color.pfRoyal)
                    .cornerRadius(PFSpacing.cornerRadius)
                }
            }
        }
        .buttonStyle(PFCardButtonStyle())
        .accessibilityLabel("Open this week's free case: \(situation.title)")
    }

    // MARK: - Invite card

    private var inviteCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "person.2.fill", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Invite a colleague")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("Share this week's free case. The invite is only text and a link. There is no referral reward.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ShareLink(item: invite.shareText) {
                    Label("Share the invite", systemImage: "square.and.arrow.up")
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.pfRoyal)
                        .cornerRadius(PFSpacing.cornerRadius)
                }
                if let linkedInURL = LinkedInShare.shareOffsiteURL(for: invite.webLink) {
                    Button {
                        UIPasteboard.general.string = invite.linkedInText
                        linkedInTextCopied = true
                        UIApplication.shared.open(linkedInURL)
                    } label: {
                        Label(
                            linkedInTextCopied ? "Post text copied. Paste it in LinkedIn" : "Share on LinkedIn",
                            systemImage: "link.badge.plus"
                        )
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfRoyal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.pfRoyal.opacity(0.10))
                        .cornerRadius(PFSpacing.cornerRadius)
                    }
                    .accessibilityHint("Copies the post text, then opens LinkedIn sharing with the link attached. Paste the text into your post.")
                }
            }
        }
    }

    // MARK: - About card

    private var aboutCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("How the weekly case works")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text("Every Monday a different real payment case becomes free for the week. It is the same case for everyone that week. The six free samples in Payment Cases stay free all the time, and the first lesson of each chapter is free to open with the full content.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Detail host

/// Opens the weekly case in the standard case detail and records
/// the opened marker for the week. The marker is written when the
/// detail appears, which is when the learner actually opens the
/// case, not when the weekly screen loads. The detail is opened
/// with isWeeklyFreeCase, the D101 exemption for the weekly path:
/// this week's case shows full content here even when Payment
/// Situations is not unlocked. The same situation opened from any
/// other path stays gated, because only this host passes the flag.
private struct WeeklyCaseDetailHost: View {
    let situation: Situation
    let weekKey: String

    @ObservedObject private var weeklyStore = WeeklyFreeCaseStore.shared

    var body: some View {
        SituationDetailView(situation: situation, isWeeklyFreeCase: true)
            .onAppear {
                weeklyStore.markOpened(weekKey: weekKey, situationID: situation.id)
            }
    }
}
