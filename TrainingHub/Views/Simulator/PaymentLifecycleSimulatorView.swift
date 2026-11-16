// PaymentLifecycleSimulatorView.swift
// Payments Training Hub iOS - Payment Lifecycle Simulator.
// A flagship teaching simulator: a fictional sample payment travels
// through 14 stages, in Guided mode step by step, or in Investigation
// mode with free navigation and injected errors. Simplified
// educational model. Real architectures vary by bank, scheme and
// rail. All sample data is fictional and labelled SAMPLE. Runs are
// session only: nothing from a run is saved, stored or synced.
// Only the count of free runs used is stored (per account), so the
// 2 free runs can be counted. Stepping is
// manual; there is no auto-playing animation, so Reduce Motion
// needs no special handling here. Pass and fail states always use
// text plus an icon, never colour alone.
// No em dashes in any user-facing text or comments.

import SwiftUI

// MARK: - Free runs

/// The free-run count for the Payment Simulator gate. The first 2
/// runs are free; further runs need the Simulator product (or the
/// Integrated Course). The count is stored per account in
/// UserDefaults: it is the only simulator state ever stored, and
/// it is what the gate reads. The helpers take the store and key
/// explicitly so the counting rule is testable without the view.
enum SimulatorFreeRuns {
    static let baseKey = "pf.simulator.freeRunsUsed.v1"

    /// The account-scoped key for the current account (or guest).
    static var currentKey: String {
        AccountScopedStorage.currentKey(baseKey)
    }

    /// Runs used so far, 0 when nothing was recorded.
    static func runsUsed(in defaults: UserDefaults = .standard, key: String) -> Int {
        max(0, defaults.integer(forKey: key))
    }

    /// Record one used run.
    static func recordRun(in defaults: UserDefaults = .standard, key: String) {
        defaults.set(runsUsed(in: defaults, key: key) + 1, forKey: key)
    }

    /// True when the simulator must stay locked: no Simulator
    /// entitlement and the free runs are used up.
    static func isLocked(runsUsed: Int, isSimulatorUnlocked: Bool) -> Bool {
        !isSimulatorUnlocked && runsUsed >= FreeSampleRules.simulatorFreeRuns
    }
}

/// The two ways to run the simulator.
private enum SimulatorMode: String, CaseIterable, Identifiable {
    case guided
    case investigation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .guided: return "Guided"
        case .investigation: return "Investigation"
        }
    }

    var description: String {
        switch self {
        case .guided:
            return "Step through the stages in order, with an explanation at each stage."
        case .investigation:
            return "Jump to any stage, interrupt the flow, and inject an error to see the negative path."
        }
    }
}

struct PaymentLifecycleSimulatorView: View {
    init() {}

    @EnvironmentObject private var storeManager: StoreManager
    /// Mode, sample and stage live in scene storage, so the
    /// simulator setup survives process death and relaunch. The
    /// journey itself stays in @State: it is a live run, and a
    /// restored stage over a fresh journey would mislead. The
    /// summary sheet stays in @State for the same reason: it is
    /// only meaningful with the journey it summarises.
    @SceneStorage("simulator.mode") private var modeRaw: String = SimulatorMode.guided.rawValue
    private var mode: SimulatorMode {
        get { SimulatorMode(rawValue: modeRaw) ?? .guided }
        set { modeRaw = newValue.rawValue }
    }
    @SceneStorage("simulator.selectedSampleID") private var selectedSampleID: String = SamplePaymentCatalogue.defaultSample.id
    private var selectedSample: SamplePayment {
        get { SamplePaymentCatalogue.samples.first { $0.id == selectedSampleID } ?? SamplePaymentCatalogue.defaultSample }
        set { selectedSampleID = newValue.id }
    }
    @SceneStorage("simulator.currentStage") private var currentStageRaw: Int = PaymentLifecycleStage.initiation.rawValue
    private var currentStage: PaymentLifecycleStage {
        get { PaymentLifecycleStage(rawValue: currentStageRaw) ?? .initiation }
        set { currentStageRaw = newValue.rawValue }
    }
    @State private var journey = LifecycleJourney()
    @State private var showingSummary: Bool = false
    @State private var showCheckout = false
    /// Free runs used, read fresh on every entry to this screen.
    @State private var freeRunsUsed: Int = SimulatorFreeRuns.runsUsed(key: SimulatorFreeRuns.currentKey)
    /// True once the current journey has consumed a free run, so
    /// one journey counts once however far it is stepped.
    @State private var runCounted = false

    /// True when no more runs may start: no Simulator
    /// entitlement and the free runs are used up.
    private var runsExhausted: Bool {
        SimulatorFreeRuns.isLocked(runsUsed: freeRunsUsed, isSimulatorUnlocked: storeManager.isSimulatorUnlocked)
    }

    /// True when the lock card replaces the simulator: the runs
    /// are exhausted and no journey is under way. A journey
    /// already under way keeps running until it ends, even when
    /// it consumed the last free run; the lock takes effect when
    /// the next run is started.
    private var isLocked: Bool {
        runsExhausted && !runCounted
    }

    private var stageCount: Int { PaymentLifecycleStage.orderedStages.count }

    private var progress: Double {
        Double(currentStage.rawValue) / Double(stageCount)
    }

    /// True when an injected fault blocks the current stage, so
    /// Guided mode cannot step forward past it. A fault blocks the
    /// injected stage AND every downstream stage: the payment
    /// stops where it failed and never reaches the stages after
    /// it. This matches the Android simulator rule (G25 alignment).
    private var faultBlocksCurrentStage: Bool {
        guard let injection = journey.injection else { return false }
        return currentStage.rawValue >= injection.stage.rawValue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                headerCard
                if isLocked {
                    simulatorLockCard
                } else {
                    modePicker
                    samplePaymentCard
                    if mode == .guided {
                        guidedSection
                    } else {
                        investigationSection
                    }
                    if journey.injection != nil {
                        faultPanel
                    }
                    if showingSummary {
                        summaryCard
                    }
                }
                footerSection
            }
            .padding(PFSpacing.lg)
            .id("simulatorTop")
        }
        .pfScrollToTopOnAppear("simulatorTop", resetWhen: (mode.rawValue, currentStage.rawValue, selectedSample.id))
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("Payment Lifecycle")
        .sheet(isPresented: $showCheckout) {
            CheckoutView()
        }
        .onAppear {
            journey.visit(currentStage)
        }
    }

    /// The lock card shown in place of the simulator once the free
    /// runs are used up. The header stays visible (discovery); the
    /// buy prompt opens the Purchases screen.
    private var simulatorLockCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Label("Simulator locked", systemImage: "lock.fill")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                Text("Your \(FreeSampleRules.simulatorFreeRuns) free runs are used up. The Payment Simulator gives unlimited runs across all \(ContentManifest.simulatorCount) simulators\(storeManager.isPriceAvailable(for: ProductCatalogue.simulatorProductID) ? " for \(storeManager.priceText(for: ProductCatalogue.simulatorProductID))" : ""), with 1 year of access. The Integrated Course includes the Simulator too.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFPrimaryButton(title: "View Payment Simulator") {
                    showCheckout = true
                }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.sm) {
                    PFIconTile(systemImage: "arrow.triangle.2.circlepath", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Payment Lifecycle Simulator")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("Follow one payment from initiation to reconciliation.")
                            .font(.pfCallout)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Simplified model. Real architectures vary by bank, scheme, and rail.")
                    .font(.pfCallout)
                    .fontWeight(.semibold)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Every name, account reference and payment reference on this screen is fictional sample data, labelled SAMPLE. Amounts are sample units, not real money. This run is session only: nothing from a run is saved. Only the number of free runs used is stored.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !storeManager.isSimulatorUnlocked {
                    Text("The first \(FreeSampleRules.simulatorFreeRuns) runs are free.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("The Payments Training Hub catalogue lists \(ContentManifest.simulatorCount) simulators in total.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFSectionHeader(title: "How to run it")
            Picker("Simulator mode", selection: Binding(get: { mode }, set: { mode = $0 })) {
                ForEach(SimulatorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Simulator mode")
            PFBodyText(text: mode.description, textColor: .pfSecondaryText)
        }
    }

    // MARK: - Sample payment

    private var samplePaymentCard: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFSectionHeader(title: "Sample payment")
            Text("Choose a fictional sample payment. Choosing a different sample starts a new run.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(SamplePaymentCatalogue.samples) { sample in
                sampleRow(sample)
            }
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    HStack(spacing: PFSpacing.sm) {
                        Text(selectedSample.label)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Spacer()
                        PFPill(text: "SAMPLE", background: Color.pfGoldSoft, foreground: Color.pfGoldText)
                    }
                    SimulatorDetailRow(label: "Payer", text: selectedSample.payerName)
                    SimulatorDetailRow(label: "Payee", text: selectedSample.payeeName)
                    SimulatorDetailRow(label: "Payer account", text: selectedSample.payerAccountReference)
                    SimulatorDetailRow(label: "Payee account", text: selectedSample.payeeAccountReference)
                    SimulatorDetailRow(label: "Amount", text: selectedSample.amountText)
                    SimulatorDetailRow(label: "Payment reference", text: selectedSample.paymentReference)
                    SimulatorDetailRow(label: "Purpose", text: selectedSample.purpose)
                    SimulatorDetailRow(label: "Channel", text: selectedSample.channel)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Selected sample payment: \(selectedSample.label). Payer \(selectedSample.payerName). Payee \(selectedSample.payeeName). Amount \(selectedSample.amountText). Reference \(selectedSample.paymentReference). All sample data is fictional.")
        }
    }

    private func sampleRow(_ sample: SamplePayment) -> some View {
        let isSelected = sample == selectedSample
        return Button {
            selectSample(sample)
        } label: {
            HStack(spacing: PFSpacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .pfRoyal : .pfSecondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(sample.label)
                        .font(.pfBody)
                        .fontWeight(.semibold)
                        .foregroundColor(.pfNavy)
                    Text("\(sample.paymentReference), \(sample.amountText)")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                }
                Spacer()
                if isSelected {
                    Text("Selected")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                }
            }
            .padding(PFSpacing.md)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(isSelected ? Color.pfRoyal : Color.pfBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sample payment: \(sample.label), \(sample.paymentReference), \(sample.amountText)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: - Guided mode

    private var guidedSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Guided run")
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack {
                    Text("Stage \(currentStage.number) of \(stageCount): \(currentStage.title)")
                        .font(.pfBody)
                        .fontWeight(.semibold)
                        .foregroundColor(.pfNavy)
                    Spacer()
                    Text("\(journey.visitedStages.count) of \(stageCount) visited")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                }
                PFProgressBar(progress: progress)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Guided run progress. Stage \(currentStage.number) of \(stageCount): \(currentStage.title). \(journey.visitedStages.count) of \(stageCount) stages visited.")
            SimulatorStageDetailCard(stage: currentStage, stageCount: stageCount)
            if faultBlocksCurrentStage {
                Text("An injected fault stops the flow at this stage. Clear the fault below to keep stepping, or end the run to see the journey summary.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: PFSpacing.md) {
                PFSecondaryButton(
                    title: "Back",
                    action: goBack,
                    isEnabled: currentStage.previousStage != nil
                )
                .accessibilityLabel("Previous stage")
                if currentStage.nextStage == nil {
                    PFPrimaryButton(
                        title: "Finish run",
                        action: finishRun,
                        isEnabled: !faultBlocksCurrentStage
                    )
                    .accessibilityLabel("Finish run and show journey summary")
                } else {
                    PFPrimaryButton(
                        title: "Next stage",
                        action: goNext,
                        isEnabled: !faultBlocksCurrentStage
                    )
                    .accessibilityLabel("Next stage: \(currentStage.nextStage?.title ?? "")")
                }
            }
            PFSecondaryButton(title: "End run and show summary", action: endRunEarly)
                .accessibilityLabel("End run early and show journey summary")
        }
    }

    // MARK: - Investigation mode

    private var investigationSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Investigation run")
            Text("Tap any stage to jump to it. Inject an error to interrupt the flow at the selected stage and see the negative path. End the run at any point to see the journey summary.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: PFSpacing.sm) {
                ForEach(PaymentLifecycleStage.orderedStages) { stage in
                    stageRow(stage)
                }
            }
            .accessibilityLabel("All stages. \(journey.visitedStages.count) of \(stageCount) visited.")
            SimulatorStageDetailCard(stage: currentStage, stageCount: stageCount)
            faultInjectionPanel
            PFSecondaryButton(title: "End run and show summary", action: endRunEarly)
                .accessibilityLabel("End run early and show journey summary")
        }
    }

    private func stageRow(_ stage: PaymentLifecycleStage) -> some View {
        let status = statusFor(stage)
        let isCurrent = stage == currentStage
        // Downstream of an injected fault the payment never arrives,
        // so the row cannot be entered: dimmed and disabled, with
        // the "Blocked" status text carrying the reason.
        let isBlocked = journey.blockedStages.contains(stage)
        return Button {
            goTo(stage)
        } label: {
            HStack(spacing: PFSpacing.sm) {
                PFIconTile(systemImage: stage.systemImage, size: 40)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text("Stage \(stage.number): \(stage.title)")
                        .font(.pfBody)
                        .fontWeight(.semibold)
                        .foregroundColor(.pfNavy)
                    HStack(spacing: PFSpacing.xs) {
                        Image(systemName: status.systemImage)
                            .font(.pfCaption)
                            .foregroundColor(status.color)
                            .accessibilityHidden(true)
                        Text(status.text)
                            .font(.pfCaptionBold)
                            .foregroundColor(status.color)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .accessibilityHidden(true)
            }
            .padding(PFSpacing.md)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(isCurrent ? Color.pfRoyal : Color.pfBorder, lineWidth: isCurrent ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBlocked)
        .opacity(isBlocked ? 0.55 : 1)
        .accessibilityLabel("Stage \(stage.number): \(stage.title). Status: \(status.text).")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : [.isButton])
    }

    /// Status text plus icon for a stage row. Colour is never the
    /// only carrier: every status has words and an icon.
    private func statusFor(_ stage: PaymentLifecycleStage) -> (text: String, systemImage: String, color: Color) {
        if let injection = journey.injection, injection.stage == stage {
            switch injection.fault.effect {
            case .stopped:
                return ("Failed here", "xmark.octagon.fill", .pfError)
            case .held:
                return ("Held here", "pause.circle.fill", .pfNavy)
            case .waitingRetry:
                return ("Waiting here", "clock.fill", .pfNavy)
            }
        }
        if journey.blockedStages.contains(stage) {
            return ("Blocked", "minus.circle.fill", .pfSecondaryText)
        }
        if stage == currentStage {
            return ("Current", "arrow.right.circle.fill", .pfRoyal)
        }
        if journey.visitedStages.contains(stage) {
            return ("Visited", "checkmark.circle.fill", .pfSuccess)
        }
        return ("Not visited", "circle", .pfSecondaryText)
    }

    // MARK: - Fault injection

    private var faultInjectionPanel: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFSectionHeader(title: "Inject an error")
            Text("Defined faults: \(LifecycleFault.allCases.count). Only faults that make sense at Stage \(currentStage.number), \(currentStage.title), can be injected here. Injecting an error interrupts the flow at this stage.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(LifecycleFault.allCases) { fault in
                faultRow(fault)
            }
        }
    }

    private func faultRow(_ fault: LifecycleFault) -> some View {
        let applicable = fault.canInject(at: currentStage)
        return PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: fault.systemImage)
                        .foregroundColor(.pfRoyal)
                        .accessibilityHidden(true)
                    Text(fault.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Spacer()
                    Text(fault.effect.title)
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                        .multilineTextAlignment(.trailing)
                }
                PFBodyText(text: fault.description, textColor: .pfSecondaryText)
                if applicable {
                    Button {
                        journey.inject(fault, at: currentStage)
                    } label: {
                        Text("Inject this error")
                            .font(.pfBody)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, PFSpacing.md)
                            .background(Color.pfRoyal)
                            .cornerRadius(PFSpacing.cornerRadius)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Inject \(fault.title) at Stage \(currentStage.number), \(currentStage.title)")
                } else {
                    HStack(spacing: PFSpacing.xs) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.pfSecondaryText)
                            .accessibilityHidden(true)
                        Text("Not applicable at this stage. It applies at: \(fault.applicableStages.map(\.title).joined(separator: ", ")).")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Fault result panel

    private var faultPanel: some View {
        guard let injection = journey.injection else {
            return AnyView(EmptyView())
        }
        let fault = injection.fault
        let blocked = journey.blockedStages
        return AnyView(
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    HStack(spacing: PFSpacing.sm) {
                        Image(systemName: fault.effect.systemImage)
                            .foregroundColor(.pfError)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("Flow interrupted: \(fault.title)")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            Text("At Stage \(injection.stage.number): \(injection.stage.title). Effect: \(fault.effect.title).")
                                .font(.pfCallout)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    PFBodyText(text: fault.description)
                    Text("Failure outcome")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    PFBodyText(text: injection.stage.failureOutcome)
                    Text("Downstream stages")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    if blocked.isEmpty {
                        Text("None. This fault hit the last stage, so no stage follows it.")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(fault.effect.downstreamWording)
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(blocked) { stage in
                            HStack(spacing: PFSpacing.xs) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.pfSecondaryText)
                                    .accessibilityHidden(true)
                                Text("Stage \(stage.number): \(stage.title)")
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                            }
                        }
                    }
                    Text("What the operator would see next")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    ForEach(Array(fault.operatorNextSteps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Lesson: \(fault.learnerNote)")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    PFSecondaryButton(title: "Clear fault and keep exploring", action: clearFault)
                        .accessibilityLabel("Clear the injected fault and keep exploring")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Flow interrupted. \(fault.title) at Stage \(injection.stage.number), \(injection.stage.title). Effect: \(fault.effect.title). \(fault.description) \(blocked.isEmpty ? "No downstream stage follows." : "Downstream stages affected: \(blocked.map(\.title).joined(separator: ", ")). \(fault.effect.downstreamWording)")")
        )
    }

    // MARK: - Journey summary

    private var summaryCard: some View {
        let outcome = journey.outcome
        return VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFSectionHeader(title: "Journey summary")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    HStack(spacing: PFSpacing.sm) {
                        Image(systemName: outcome.systemImage)
                            .foregroundColor(.pfRoyal)
                            .accessibilityHidden(true)
                        Text(outcome.title)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                    }
                    PFBodyText(text: outcome.detail, textColor: .pfSecondaryText)
                    HStack(spacing: PFSpacing.sm) {
                        Text("Sample payment: \(selectedSample.label) (\(selectedSample.paymentReference))")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        PFPill(text: "SAMPLE", background: Color.pfGoldSoft, foreground: Color.pfGoldText)
                    }
                    Text("Stages visited, in visit order (\(journey.visitedStages.count) of \(stageCount))")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    if journey.visitedStages.isEmpty {
                        Text("No stage was visited yet.")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                    } else {
                        ForEach(Array(journey.visitedStages.enumerated()), id: \.offset) { index, stage in
                            HStack(spacing: PFSpacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.pfSuccess)
                                    .accessibilityHidden(true)
                                Text("\(index + 1). Stage \(stage.number): \(stage.title)")
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                            }
                        }
                    }
                    Text("Stages not visited (\(journey.unvisitedStages.count) of \(stageCount))")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    if journey.unvisitedStages.isEmpty {
                        Text("None. Every stage was visited.")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                    } else {
                        ForEach(journey.unvisitedStages) { stage in
                            HStack(spacing: PFSpacing.xs) {
                                Image(systemName: "circle")
                                    .foregroundColor(.pfSecondaryText)
                                    .accessibilityHidden(true)
                                Text("Stage \(stage.number): \(stage.title)")
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                            }
                        }
                    }
                    if let injection = journey.injection {
                        Text("Fault injected: \(injection.fault.title) at Stage \(injection.stage.number), \(injection.stage.title). Effect: \(injection.fault.effect.title).")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("This summary is session only. Nothing was saved.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summaryAccessibilityText)
        }
    }

    private var summaryAccessibilityText: String {
        let visited = journey.visitedStages.map { "Stage \($0.number): \($0.title)" }.joined(separator: ", ")
        var text = "Journey summary. Outcome: \(journey.outcome.title). \(journey.outcome.detail) Sample payment: \(selectedSample.label), \(selectedSample.paymentReference), fictional sample data. Stages visited, in order: \(visited.isEmpty ? "none" : visited)."
        if let injection = journey.injection {
            text += " Fault injected: \(injection.fault.title) at Stage \(injection.stage.number), \(injection.stage.title). Effect: \(injection.fault.effect.title)."
            if !journey.blockedStages.isEmpty {
                text += " Stages affected: \(journey.blockedStages.map(\.title).joined(separator: ", "))."
            }
        }
        if !journey.unvisitedStages.isEmpty {
            text += " Stages not visited: \(journey.unvisitedStages.map(\.title).joined(separator: ", "))."
        }
        return text
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            if !showingSummary {
                PFSecondaryButton(title: "Show journey summary", action: { showingSummary = true })
                    .accessibilityLabel("Show journey summary")
            }
            PFSecondaryButton(title: "Start a new run", action: startNewRun)
                .accessibilityLabel("Start a new run from Stage 1")
            Text("Simplified model. Real architectures vary by bank, scheme, and rail. Nothing on this screen is a real payment, a real account, or a real bank rule.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func goTo(_ stage: PaymentLifecycleStage) {
        // A fault blocks every downstream stage: the payment never
        // arrives there, so navigation into a blocked stage is
        // refused (the fault stage itself stays open for inspection).
        guard !journey.blockedStages.contains(stage) else { return }
        countRunIfNeeded()
        currentStage = stage
        journey.visit(stage)
    }

    /// Consume one free run for the current journey, once. The
    /// first real navigation, finishing, or ending a journey early
    /// consumes the run; only browsing the first stage does not.
    /// Entitled learners never consume runs.
    private func countRunIfNeeded() {
        guard !runCounted, !storeManager.isSimulatorUnlocked else { return }
        runCounted = true
        SimulatorFreeRuns.recordRun(key: SimulatorFreeRuns.currentKey)
        freeRunsUsed = SimulatorFreeRuns.runsUsed(key: SimulatorFreeRuns.currentKey)
    }

    private func goNext() {
        guard let next = currentStage.nextStage else { return }
        goTo(next)
    }

    private func goBack() {
        guard let previous = currentStage.previousStage else { return }
        goTo(previous)
    }

    private func finishRun() {
        countRunIfNeeded()
        journey.visit(currentStage)
        journey.markReachedEnd()
        showingSummary = true
    }

    private func endRunEarly() {
        countRunIfNeeded()
        journey.visit(currentStage)
        journey.markEndedEarly()
        showingSummary = true
    }

    private func clearFault() {
        journey.clearInjection()
    }

    private func selectSample(_ sample: SamplePayment) {
        guard !runsExhausted else { showCheckout = true; return }
        selectedSample = sample
        startNewRun()
    }

    private func startNewRun() {
        guard !runsExhausted else { showCheckout = true; return }
        journey.reset()
        currentStage = .initiation
        showingSummary = false
        runCounted = false
        journey.visit(.initiation)
    }
}

// MARK: - Stage detail card

/// The full detail for one stage: the four guiding questions first
/// (what comes in, what it does, what goes out, what happens if it
/// fails), then the component, state transition, data transformation
/// and expected result. Used by both modes so the teaching content
/// is identical whichever way the learner runs the simulator.
private struct SimulatorStageDetailCard: View {
    let stage: PaymentLifecycleStage
    let stageCount: Int

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.sm) {
                    PFIconTile(systemImage: stage.systemImage, size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Stage \(stage.number) of \(stageCount)")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                        Text(stage.title)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                SimulatorDetailRow(label: "What comes in", text: stage.incomingEvent)
                SimulatorDetailRow(label: "What does it do", text: stage.explanation)
                SimulatorDetailRow(label: "What goes out", text: stage.outgoingEvent)
                HStack(alignment: .top, spacing: PFSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.pfError)
                        .accessibilityHidden(true)
                    SimulatorDetailRow(label: "What happens if it fails", text: stage.failureOutcome)
                }
                Divider()
                SimulatorDetailRow(label: "Processing component", text: stage.processingComponent)
                SimulatorDetailRow(label: "State transition", text: stage.stateTransition)
                SimulatorDetailRow(label: "Data transformation", text: stage.dataTransformation)
                SimulatorDetailRow(label: "Expected result", text: stage.expectedResult)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stage \(stage.number) of \(stageCount): \(stage.title). What comes in: \(stage.incomingEvent) What does it do: \(stage.explanation) What goes out: \(stage.outgoingEvent) What happens if it fails: \(stage.failureOutcome) Processing component: \(stage.processingComponent) State transition: \(stage.stateTransition) Data transformation: \(stage.dataTransformation) Expected result: \(stage.expectedResult)")
    }
}

// MARK: - Labelled detail row

private struct SimulatorDetailRow: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.xs) {
            Text(label)
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            Text(text)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
