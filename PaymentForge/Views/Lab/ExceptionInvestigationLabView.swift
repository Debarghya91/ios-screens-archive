// ExceptionInvestigationLabView.swift
// PaymentForge iOS - Payment Exception Investigation Lab.
//
// The learner investigates payment incidents step by step: reading
// the narrative, opening evidence as it is revealed, and choosing
// the next action at each step. Scoring measures investigation
// quality (best-first actions, wrong turns, red herrings, efficiency
// and thoroughness) and the full breakdown is shown on completion.
// Scores are device-only: ExceptionLabStore persists them per
// account on this device and mirrors nothing to any server.
//
// Gating (settled; this file changes no gating code): a case
// grounded in a non-free situation requires
// StoreManager.isSituationsUnlocked. Cases grounded in a free-sample
// situation and purely authored practice exercises are open to all.
// A locked case shows its title, incident type and level only, with
// an unlock card and checkout path; its narrative, evidence, steps
// and takeaway stay hidden until unlock. SituationsView applies the
// same hard gate since D101 was decided (owner decision, 13 Nov
// 2026): a locked situation detail shows its teaser plus the
// checkout card, and no explain or takeaway text.
// Free samples stay free: the free-sample cases in this lab are
// open to every learner, with no purchase needed.
//
// This view carries no NavigationStack of its own, following
// PracticeModeView and DailyChallengeView: the host provides the
// stack (the PracticeSheetView pattern), so the detail navigation
// and back button belong to the host.
// No em dashes in any user-facing text.

import SwiftUI

struct ExceptionInvestigationLabView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var storeManager: StoreManager
    @ObservedObject private var labStore = ExceptionLabStore.shared

    @State private var showCheckout = false

    init() {}

    /// Levels in play order, with their section headings.
    private var levelSections: [(level: SituationLevel, heading: String)] {
        [
            (.foundation, "Foundation cases"),
            (.core, "Core cases"),
            (.advanced, "Advanced cases"),
        ]
    }

    private func cases(for level: SituationLevel) -> [ExceptionCase] {
        ExceptionCaseCatalogue.allCases.filter { $0.level == level }
    }

    /// True when the learner may open this case: it needs no unlock,
    /// or the situations entitlement is active.
    private func isOpen(_ exceptionCase: ExceptionCase) -> Bool {
        !exceptionCase.requiresSituationsUnlock || storeManager.isSituationsUnlocked
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                headerCard

                if contentService.isShowingCachedContent {
                    PFOfflineBanner()
                }

                ForEach(levelSections, id: \.level) { section in
                    levelSection(level: section.level, heading: section.heading)
                }

                if !storeManager.isSituationsUnlocked {
                    footerCard
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("Investigation Lab")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showCheckout) {
            CheckoutView()
        }
        .task {
            await contentService.loadFullSituations()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    PFIconTile(systemImage: "magnifyingglass", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Investigate real payment incidents")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(ExceptionCaseCatalogue.allCases.count) cases, from foundation to advanced. Each case is built from a real Payment Situation.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Read the incident, open the evidence as it is revealed, and choose the best next step at each stage. A wrong turn costs points, and chasing a red herring costs more, so investigate before you act.")
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                PFBodyText(text: "How scoring works: each step solved on the first try earns \(ExceptionLabScoring.bestFirstPointsPerStep) points. A step solved after a wrong turn earns \(ExceptionLabScoring.recoveredPointsPerStep) points. Each wrong turn deducts \(ExceptionLabScoring.wrongPickDeduction) points, and each red herring action deducts a further \(ExceptionLabScoring.redHerringPickDeduction) points. Solving a case with no wrong turns earns a \(ExceptionLabScoring.efficiencyBonusNoWrongTurn) point efficiency bonus, or \(ExceptionLabScoring.efficiencyBonusOneWrongTurn) points with one wrong turn. Opening each genuine piece of evidence earns \(ExceptionLabScoring.thoroughnessPointsPerEvidence) points.", textColor: .pfSecondaryText)
                Text("Your lab scores stay on this device.")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                if labStore.completedCount > 0 {
                    Text("\(labStore.completedCount) of \(ExceptionCaseCatalogue.allCases.count) cases completed.")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Level sections

    private func levelSection(level: SituationLevel, heading: String) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: heading)
            VStack(spacing: PFSpacing.sm) {
                ForEach(cases(for: level)) { exceptionCase in
                    if isOpen(exceptionCase) {
                        NavigationLink(destination: InvestigationExperienceView(
                            investigation: InvestigationEngine.caseForLabCase(exceptionCase, difficulty: .professional),
                            isFreeSample: !exceptionCase.requiresSituationsUnlock,
                            isWeeklyFreeCase: false,
                            onDifficultyChange: { difficulty in
                                InvestigationEngine.caseForLabCase(exceptionCase, difficulty: difficulty)
                            }
                        )) {
                            caseRow(exceptionCase)
                        }
                        .buttonStyle(PFCardButtonStyle())
                        .accessibilityLabel("\(exceptionCase.incidentType): \(exceptionCase.title). \(exceptionCase.level.displayName) case.")
                    } else {
                        lockedCaseCard(exceptionCase)
                    }
                }
            }
        }
    }

    /// An open case row: incident type, title, level and source
    /// pills, and the best score when the case is completed.
    private func caseRow(_ exceptionCase: ExceptionCase) -> some View {
        HStack(alignment: .top, spacing: PFSpacing.md) {
            PFIconTile(systemImage: "doc.text.magnifyingglass", size: 44)
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                if let sourceSituationID = exceptionCase.sourceSituationID {
                    Text("Case \(sourceSituationID)")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                }
                Text(exceptionCase.incidentType)
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfRoyal)
                Text(exceptionCase.title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: PFSpacing.sm) {
                    PFLevelPill(text: exceptionCase.level.displayName)
                    if exceptionCase.isPracticeExercise {
                        PFPill(
                            text: "Practice exercise",
                            background: Color.pfRoyal.opacity(0.10),
                            foreground: .pfRoyal
                        )
                    } else if exceptionCase.isGroundedInFreeSample {
                        PFPill(
                            text: "Free sample",
                            background: Color.pfSuccess.opacity(0.12),
                            foreground: .pfSuccess
                        )
                    }
                    if labStore.isCompleted(exceptionCase.id) {
                        PFPill(
                            text: "Completed",
                            background: Color.pfSuccess.opacity(0.12),
                            foreground: .pfSuccess
                        )
                    }
                }
                if let result = labStore.result(for: exceptionCase.id) {
                    Text("Best score: \(result.bestTotal) of \(result.bestMaximum)")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                }
                Text("\(exceptionCase.steps.count) investigation steps")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.pfCaption.weight(.semibold))
                .foregroundColor(.pfSecondaryText)
                .padding(.top, PFSpacing.xs)
        }
        .padding(PFSpacing.lg)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
        .shadow(color: Color.pfNavy.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    /// A locked case card. Only the title, incident type and level
    /// are shown, with the same unlock card and checkout path
    /// SituationsView uses. The narrative, evidence, steps and
    /// takeaway stay hidden until the situations set is unlocked.
    private func lockedCaseCard(_ exceptionCase: ExceptionCase) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: "lock.fill")
                        .font(.pfCardTitle.weight(.semibold))
                        .foregroundColor(.pfGold)
                        .accessibilityHidden(true)
                    Text(exceptionCase.incidentType)
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                    Spacer()
                    PFPill(
                        text: "Locked",
                        background: Color.pfNavy.opacity(0.08),
                        foreground: .pfNavy
                    )
                }
                Text(exceptionCase.title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: PFSpacing.sm) {
                    PFLevelPill(text: exceptionCase.level.displayName)
                }
                Text("This investigation case is built from a Payment Situation in the full set. Unlock all \(ContentManifest.situationCount) situations with the Payment Situations purchase. The Integrated Course includes all situations too.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFPrimaryButton(title: "Go to checkout") {
                    showCheckout = true
                }
                .accessibilityLabel("Go to checkout to unlock \(exceptionCase.title)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Footer card

    /// The unlock card, mirroring the SituationsView footer card.
    private var footerCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Unlock all \(ContentManifest.situationCount) situations")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text("One-time payment by In-App Purchase. The free sample cases stay free. The Integrated Course includes all situations too.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                PFPrimaryButton(title: "Go to checkout") {
                    showCheckout = true
                }
                .accessibilityLabel("Go to checkout to unlock all situations")
            }
        }
    }
}
