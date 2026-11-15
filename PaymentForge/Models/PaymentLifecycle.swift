// PaymentLifecycle.swift
// PaymentForge iOS - Payment Lifecycle Simulator data model.
// A simplified educational model of a payment journey. It teaches
// the shape of a journey, not any one bank, scheme or rail. Real
// architectures vary by bank, scheme and rail. All sample data in
// this file is fictional and labelled SAMPLE.
// No em dashes in any user-facing text or comments.

import Foundation

// MARK: - The 14 stages

/// One stage of the simplified payment lifecycle, in journey order.
/// The order is fixed by the raw values: 1 is first, 14 is last.
/// Every stage answers the same questions: what comes in, what the
/// stage does, what goes out, and what happens if it fails.
enum PaymentLifecycleStage: Int, CaseIterable, Identifiable, Hashable {
    case initiation = 1
    case gateway = 2
    case validation = 3
    case enrichment = 4
    case sanctionsScreening = 5
    case fraudChecks = 6
    case accountChecks = 7
    case processing = 8
    case routing = 9
    case clearing = 10
    case settlement = 11
    case ledgerUpdates = 12
    case notifications = 13
    case reconciliation = 14

    var id: Int { rawValue }

    /// All stages in journey order.
    static let orderedStages: [PaymentLifecycleStage] = PaymentLifecycleStage.allCases.sorted { $0.rawValue < $1.rawValue }

    /// The stage number shown to the learner, starting at 1.
    var number: Int { rawValue }

    var title: String {
        switch self {
        case .initiation: return "Payment initiation"
        case .gateway: return "Channel/API gateway"
        case .validation: return "Validation"
        case .enrichment: return "Enrichment"
        case .sanctionsScreening: return "Sanctions and compliance screening"
        case .fraudChecks: return "Fraud and risk checks"
        case .accountChecks: return "Account and balance checks"
        case .processing: return "Payment processing"
        case .routing: return "Routing"
        case .clearing: return "Clearing"
        case .settlement: return "Settlement"
        case .ledgerUpdates: return "Ledger updates"
        case .notifications: return "Notifications"
        case .reconciliation: return "Reconciliation"
        }
    }

    var systemImage: String {
        switch self {
        case .initiation: return "paperplane.fill"
        case .gateway: return "network"
        case .validation: return "checklist"
        case .enrichment: return "doc.badge.plus"
        case .sanctionsScreening: return "shield.fill"
        case .fraudChecks: return "magnifyingglass.circle.fill"
        case .accountChecks: return "creditcard.fill"
        case .processing: return "gearshape.fill"
        case .routing: return "signpost.right.fill"
        case .clearing: return "arrow.left.arrow.right"
        case .settlement: return "dollarsign.circle.fill"
        case .ledgerUpdates: return "book.fill"
        case .notifications: return "bell.fill"
        case .reconciliation: return "checkmark.seal.fill"
        }
    }

    /// What the stage does, in plain language. Written for the
    /// simplified model only; it states no scheme rule and no
    /// real bank behaviour.
    var explanation: String {
        switch self {
        case .initiation:
            return "The payer starts a payment. In this model, the payment begins as an instruction carrying the payer, the payee, the amount and a reference."
        case .gateway:
            return "The gateway is the front door. It accepts the instruction, checks that the sender is allowed to connect, and passes the instruction inside."
        case .validation:
            return "Validation checks the instruction itself: is it complete, well formed and internally consistent, before any money or account work begins."
        case .enrichment:
            return "Enrichment adds the extra information later stages need, using reference data the bank already holds."
        case .sanctionsScreening:
            return "Screening compares the payment against sanctions and compliance lists. A match does not mean wrongdoing; it means a person needs to review the payment."
        case .fraudChecks:
            return "Fraud and risk checks look for signs that the payment may not be genuine or may carry unusual risk, using patterns and rules."
        case .accountChecks:
            return "These checks confirm the payer account exists, is open for payments, and can fund the payment in this model."
        case .processing:
            return "Processing turns the checked instruction into the payment the bank will execute. It applies business rules and prepares the payment for routing."
        case .routing:
            return "Routing decides which path the payment will take next, based on the payment details and the routes available in this model."
        case .clearing:
            return "Clearing is where payment details are exchanged and agreed with the other side, so both sides hold the same payment information."
        case .settlement:
            return "Settlement is the movement of value itself: the payer side is debited and the payee side is credited in this model."
        case .ledgerUpdates:
            return "Ledger updates record the payment in the books, so the accounts and the bank records agree with what happened."
        case .notifications:
            return "Notifications tell the people involved what happened: the payer, the payee, and any system waiting for the result."
        case .reconciliation:
            return "Reconciliation checks the payment against the records afterwards, confirming that every stage agrees and nothing is missing or counted twice."
        }
    }

    /// What comes in: the event that starts this stage.
    var incomingEvent: String {
        switch self {
        case .initiation:
            return "Payer instruction received. The payer has asked for money to move from their account to the payee."
        case .gateway:
            return "Payment instruction arrives from the initiation channel."
        case .validation:
            return "Payment instruction forwarded by the gateway."
        case .enrichment:
            return "Validated payment instruction."
        case .sanctionsScreening:
            return "Enriched payment instruction."
        case .fraudChecks:
            return "Screened payment instruction."
        case .accountChecks:
            return "Risk checked payment instruction."
        case .processing:
            return "Funded payment instruction."
        case .routing:
            return "Execution ready payment."
        case .clearing:
            return "Routed payment."
        case .settlement:
            return "Cleared payment."
        case .ledgerUpdates:
            return "Settlement confirmation."
        case .notifications:
            return "Posting confirmation."
        case .reconciliation:
            return "Completed payment record, with settlement, ledger and notification results."
        }
    }

    /// The component that does the work in this simplified model.
    /// Component names are generic roles, not real products.
    var processingComponent: String {
        switch self {
        case .initiation:
            return "Initiation channel. The place where the payer enters the instruction, such as an online banking screen or a business system."
        case .gateway:
            return "Channel or API gateway. It receives requests from outside and routes them to internal processing."
        case .validation:
            return "Validation service. It checks the shape and completeness of the instruction."
        case .enrichment:
            return "Enrichment service with reference data, such as account and routing reference tables."
        case .sanctionsScreening:
            return "Screening engine with sanctions and compliance lists, plus a case queue for human review."
        case .fraudChecks:
            return "Fraud and risk engine, with rules and pattern checks."
        case .accountChecks:
            return "Account service, which holds account status and balance information."
        case .processing:
            return "Payment processing engine, which applies the bank payment business rules."
        case .routing:
            return "Routing service, which selects the next path from the routes available."
        case .clearing:
            return "Clearing function, which exchanges and agrees payment details with the other side."
        case .settlement:
            return "Settlement function, which moves value between the payer and payee sides."
        case .ledgerUpdates:
            return "Ledger and accounting function, which posts the payment to the books."
        case .notifications:
            return "Notification service, which sends status messages to the payer, the payee and waiting systems."
        case .reconciliation:
            return "Reconciliation function, which compares records across stages and systems."
        }
    }

    /// How the payment status changes across this stage.
    var stateTransition: String {
        switch self {
        case .initiation:
            return "No payment record yet, to Payment created. The instruction becomes a tracked payment record."
        case .gateway:
            return "Payment created, to Payment received. The bank systems now hold the instruction."
        case .validation:
            return "Payment received, to Payment validated. When a check fails, to Payment rejected instead."
        case .enrichment:
            return "Payment validated, to Payment enriched."
        case .sanctionsScreening:
            return "Payment enriched, to Payment screened. When a possible match needs review, to Payment held instead."
        case .fraudChecks:
            return "Payment screened, to Payment risk checked. When a check needs review, to Payment held instead."
        case .accountChecks:
            return "Payment risk checked, to Payment funded. When the account cannot fund it, to Payment rejected instead."
        case .processing:
            return "Payment funded, to Payment ready to route."
        case .routing:
            return "Payment ready to route, to Payment routed."
        case .clearing:
            return "Payment routed, to Payment cleared. When clearing does not accept it, to Payment rejected instead."
        case .settlement:
            return "Payment cleared, to Payment settled."
        case .ledgerUpdates:
            return "Payment settled, to Payment recorded."
        case .notifications:
            return "Payment recorded, to Payment notified."
        case .reconciliation:
            return "Payment notified, to Payment reconciled. When records disagree, to Payment with exception instead."
        }
    }

    /// How the payment data changes across this stage.
    var dataTransformation: String {
        switch self {
        case .initiation:
            return "The payer entries become a structured payment instruction with payer, payee, amount and reference fields."
        case .gateway:
            return "The outside request format becomes the internal message shape used by later stages. No business facts change here."
        case .validation:
            return "The instruction is checked field by field. Nothing is added yet; invalid values are flagged, not fixed silently."
        case .enrichment:
            return "Reference details are added to the instruction, such as the internal account identifiers that later stages use."
        case .sanctionsScreening:
            return "Screening results are attached to the instruction: clear, or held with the reason for review."
        case .fraudChecks:
            return "A risk result is attached: pass, or hold with the checks that raised concern."
        case .accountChecks:
            return "The account status and a funds result are attached. No money moves yet; this stage only checks."
        case .processing:
            return "The instruction becomes an execution ready payment, with processing results and any duplicate check outcome attached."
        case .routing:
            return "The chosen route is recorded on the payment. The payment details themselves do not change."
        case .clearing:
            return "The clearing result is attached: agreed, or rejected with the reason given."
        case .settlement:
            return "Settlement entries are created: a debit on the payer side and a credit on the payee side."
        case .ledgerUpdates:
            return "The settlement entries become ledger postings against the payer and payee accounts."
        case .notifications:
            return "The payment result becomes one or more status messages, each addressed to the party that needs it."
        case .reconciliation:
            return "Comparison results are attached: matched, or an exception describing the difference."
        }
    }

    /// What goes out: the event this stage sends onward.
    var outgoingEvent: String {
        switch self {
        case .initiation:
            return "Payment instruction created and sent to the channel or API gateway."
        case .gateway:
            return "Payment instruction forwarded for validation."
        case .validation:
            return "Validated instruction passed to enrichment, or a rejection notice when validation fails."
        case .enrichment:
            return "Enriched instruction passed to sanctions and compliance screening."
        case .sanctionsScreening:
            return "Cleared instruction passed to fraud and risk checks, or a hold notice when review is needed."
        case .fraudChecks:
            return "Checked instruction passed to account and balance checks, or a hold notice when review is needed."
        case .accountChecks:
            return "Funded instruction passed to payment processing, or a rejection notice when funding fails."
        case .processing:
            return "Execution ready payment passed to routing."
        case .routing:
            return "Routed payment sent toward clearing."
        case .clearing:
            return "Cleared payment passed to settlement, or a rejection notice when clearing does not accept it."
        case .settlement:
            return "Settlement confirmation passed to ledger updates."
        case .ledgerUpdates:
            return "Posting confirmation passed to notifications."
        case .notifications:
            return "Status messages sent. The payment result is visible to the payer and the payee."
        case .reconciliation:
            return "Reconciliation result recorded. The payment journey ends as matched or as an open exception."
        }
    }

    /// The expected result when the stage goes well.
    var expectedResult: String {
        switch self {
        case .initiation:
            return "A complete instruction exists and can be tracked through the later stages."
        case .gateway:
            return "The instruction is accepted, logged and handed to validation."
        case .validation:
            return "The instruction is complete and consistent, and ready for enrichment."
        case .enrichment:
            return "The instruction carries everything later stages need, and the original payer entries are unchanged."
        case .sanctionsScreening:
            return "The payment is screened and cleared, or held for review with a clear reason."
        case .fraudChecks:
            return "The payment passes the checks, or is held for review with the concern recorded."
        case .accountChecks:
            return "The account is confirmed able to fund the payment."
        case .processing:
            return "One execution ready payment exists, with no unresolved duplicate concern."
        case .routing:
            return "The payment has a chosen route and is sent on that route."
        case .clearing:
            return "Both sides agree on the payment details, and the payment can settle."
        case .settlement:
            return "Value has moved, and a settlement confirmation exists."
        case .ledgerUpdates:
            return "The books match the settlement, and the payment is fully recorded."
        case .notifications:
            return "Everyone who needs to know has been told the payment completed."
        case .reconciliation:
            return "All records agree, and the payment journey is closed as matched."
        }
    }

    /// What happens if the stage fails. This is the negative path
    /// for the stage, shown in both modes.
    var failureOutcome: String {
        switch self {
        case .initiation:
            return "The instruction is not created. The payer sees that the payment did not start, and no later stage runs."
        case .gateway:
            return "The instruction is rejected at the door. The sender gets an error response and the payment goes no further."
        case .validation:
            return "The payment is rejected with the reason recorded. Later stages do not run. The payer can correct the instruction and start again."
        case .enrichment:
            return "The payment pauses when a needed reference cannot be found. An operator reviews the missing reference before the payment can continue."
        case .sanctionsScreening:
            return "The payment is held. No money moves while the hold lasts. A compliance reviewer decides the next step."
        case .fraudChecks:
            return "The payment is held or stopped. The payer may be contacted to confirm the payment is genuine."
        case .accountChecks:
            return "The payment is rejected. The payer is told the payment could not be funded. Later stages do not run."
        case .processing:
            return "The payment stops. A duplicate concern or a processing error sends it to an operator queue for review."
        case .routing:
            return "The payment waits. No route is available, or the next system does not respond, so an operator checks the route before retrying."
        case .clearing:
            return "The payment is rejected by clearing. It does not settle. The reason is recorded and the payer is told."
        case .settlement:
            return "The payment waits for settlement. An operator checks whether value moved before any retry, so the payment is never settled twice."
        case .ledgerUpdates:
            return "The payment is settled but not yet recorded. An operator resolves the posting difference before the payment is treated as complete."
        case .notifications:
            return "The payment itself is complete, but a message fails to send. The message is retried; the payment is not run again."
        case .reconciliation:
            return "An exception is opened. An operator investigates the difference; the payment itself is not run again."
        }
    }

    /// The stage before this one in journey order, if any.
    var previousStage: PaymentLifecycleStage? {
        PaymentLifecycleStage(rawValue: rawValue - 1)
    }

    /// The stage after this one in journey order, if any.
    var nextStage: PaymentLifecycleStage? {
        PaymentLifecycleStage(rawValue: rawValue + 1)
    }
}

// MARK: - Fictional sample payments

/// One fictional sample payment. Every name, account reference and
/// payment reference is invented for training and labelled SAMPLE
/// wherever it is shown. Amounts are sample units, not real money.
struct SamplePayment: Identifiable, Hashable {
    let id: String
    /// Short label for the picker, for example "Sample supplier invoice".
    let label: String
    let payerName: String
    let payeeName: String
    let payerAccountReference: String
    let payeeAccountReference: String
    /// Amount text in sample units, for example "1,250.00 sample units".
    let amountText: String
    let paymentReference: String
    let purpose: String
    let channel: String
}

enum SamplePaymentCatalogue {
    static let samples: [SamplePayment] = [
        SamplePayment(
            id: "sample-a",
            label: "Sample supplier invoice",
            payerName: "Asha Example (fictional)",
            payeeName: "Northwind Supplies Ltd (fictional)",
            payerAccountReference: "SAMPLE-ACC-1001",
            payeeAccountReference: "SAMPLE-ACC-2001",
            amountText: "1,250.00 sample units",
            paymentReference: "SAMPLE-PAY-001",
            purpose: "Sample invoice payment for training",
            channel: "Sample online banking (fictional)"
        ),
        SamplePayment(
            id: "sample-b",
            label: "Sample payroll style payment",
            payerName: "Example Payroll Services (fictional)",
            payeeName: "Ben Example (fictional)",
            payerAccountReference: "SAMPLE-ACC-1002",
            payeeAccountReference: "SAMPLE-ACC-2002",
            amountText: "3,400.00 sample units",
            paymentReference: "SAMPLE-PAY-002",
            purpose: "Sample payroll style payment for training",
            channel: "Sample business payment file (fictional)"
        ),
        SamplePayment(
            id: "sample-c",
            label: "Sample customer refund",
            payerName: "Example Retail Group (fictional)",
            payeeName: "Cara Example (fictional)",
            payerAccountReference: "SAMPLE-ACC-1003",
            payeeAccountReference: "SAMPLE-ACC-2003",
            amountText: "89.50 sample units",
            paymentReference: "SAMPLE-PAY-003",
            purpose: "Sample customer refund for training",
            channel: "Sample phone channel (fictional)"
        )
    ]

    static let defaultSample: SamplePayment = samples[0]
}

// MARK: - Injected faults (negative paths)

/// What an injected fault does to the payment journey.
enum LifecycleFaultEffect: String, Hashable {
    /// The payment stops. Later stages do not run.
    case stopped
    /// The payment is held for a human decision. Later stages wait.
    case held
    /// The outcome is unknown, so the payment waits. A careful
    /// retry may be possible once the operator checks what happened.
    case waitingRetry

    var title: String {
        switch self {
        case .stopped: return "Payment stops"
        case .held: return "Payment held for review"
        case .waitingRetry: return "Payment waits, retry may be possible"
        }
    }

    var systemImage: String {
        switch self {
        case .stopped: return "xmark.octagon.fill"
        case .held: return "pause.circle.fill"
        case .waitingRetry: return "arrow.clockwise.circle.fill"
        }
    }

    /// How the later stages are described while this effect holds.
    var downstreamWording: String {
        switch self {
        case .stopped: return "These stages do not run."
        case .held: return "These stages wait until a reviewer decides."
        case .waitingRetry: return "These stages wait until the operator knows what happened."
        }
    }
}

/// One error the learner can inject in Investigation mode. Each
/// fault names the stages where it can happen, what the operator
/// would see next, and the lesson it teaches. Faults are teaching
/// cases, not claims about any real system behaviour.
enum LifecycleFault: String, CaseIterable, Identifiable, Hashable {
    case validationFailure
    case sanctionsHold
    case insufficientFunds
    case duplicatePayment
    case downstreamTimeout
    case clearingRejection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .validationFailure: return "Validation failure"
        case .sanctionsHold: return "Sanctions hold"
        case .insufficientFunds: return "Insufficient funds"
        case .duplicatePayment: return "Duplicate payment"
        case .downstreamTimeout: return "Downstream timeout"
        case .clearingRejection: return "Clearing rejection"
        }
    }

    var systemImage: String {
        switch self {
        case .validationFailure: return "exclamationmark.triangle.fill"
        case .sanctionsHold: return "shield.fill"
        case .insufficientFunds: return "banknote.fill"
        case .duplicatePayment: return "doc.on.doc.fill"
        case .downstreamTimeout: return "clock.fill"
        case .clearingRejection: return "xmark.circle.fill"
        }
    }

    /// What happens, in one plain sentence.
    var description: String {
        switch self {
        case .validationFailure:
            return "A detail is missing or inconsistent, so validation rejects the instruction."
        case .sanctionsHold:
            return "A possible list match is found, so the payment is held for a compliance review."
        case .insufficientFunds:
            return "The payer account cannot fund the payment in this model, so the payment is rejected."
        case .duplicatePayment:
            return "The payment looks like one already sent, so it is held until an operator confirms whether it is a duplicate."
        case .downstreamTimeout:
            return "The next system does not respond in time, so the stage cannot confirm what happened."
        case .clearingRejection:
            return "Clearing does not accept the payment, so it cannot settle."
        }
    }

    /// The stages where this fault can be injected. A fault can
    /// only be injected at a stage where it makes sense in the model.
    var applicableStages: [PaymentLifecycleStage] {
        switch self {
        case .validationFailure: return [.validation]
        case .sanctionsHold: return [.sanctionsScreening]
        case .insufficientFunds: return [.accountChecks]
        case .duplicatePayment: return [.validation, .processing]
        case .downstreamTimeout: return [.routing, .clearing, .settlement]
        case .clearingRejection: return [.clearing]
        }
    }

    func canInject(at stage: PaymentLifecycleStage) -> Bool {
        applicableStages.contains(stage)
    }

    var effect: LifecycleFaultEffect {
        switch self {
        case .validationFailure: return .stopped
        case .sanctionsHold: return .held
        case .insufficientFunds: return .stopped
        case .duplicatePayment: return .held
        case .downstreamTimeout: return .waitingRetry
        case .clearingRejection: return .stopped
        }
    }

    /// What the operator would see next and do next, in order.
    /// Written as generic operator practice for the model, not as
    /// any real bank procedure.
    var operatorNextSteps: [String] {
        switch self {
        case .validationFailure:
            return [
                "Read the rejection reason on the payment record.",
                "Tell the payer which detail to correct.",
                "Wait for a corrected instruction. Do not edit the payer entries yourself."
            ]
        case .sanctionsHold:
            return [
                "Open the screening case and read the match detail.",
                "A compliance reviewer decides: release the payment or escalate it.",
                "Keep the payment held until the reviewer decides."
            ]
        case .insufficientFunds:
            return [
                "Confirm the rejection reason on the payment record.",
                "Tell the payer the payment could not be funded.",
                "Take no further action on this payment unless the payer sends a new instruction."
            ]
        case .duplicatePayment:
            return [
                "Find the earlier payment this one resembles.",
                "Confirm with the payer whether this is a second genuine payment.",
                "Release it only when confirmed genuine. Cancel it when confirmed a duplicate."
            ]
        case .downstreamTimeout:
            return [
                "Check whether the downstream system already acted before retrying.",
                "Retry only when it is safe to do so.",
                "Raise an incident when the system stays silent."
            ]
        case .clearingRejection:
            return [
                "Read the rejection reason returned by clearing.",
                "Tell the payer the payment was not accepted.",
                "Correct the cause and start a new payment when the payer asks."
            ]
        }
    }

    /// The lesson the fault teaches.
    var learnerNote: String {
        switch self {
        case .validationFailure:
            return "Validation protects later stages from working on a broken instruction. Failing early is cheaper than failing late."
        case .sanctionsHold:
            return "A hold is not a finding of wrongdoing. It means a person needs to decide before money moves."
        case .insufficientFunds:
            return "Funding is checked before processing, so a payment that cannot be funded never reaches routing or settlement."
        case .duplicatePayment:
            return "A duplicate check asks whether this payment already happened. Releasing a real duplicate would move the money twice."
        case .downstreamTimeout:
            return "A timeout means unknown, not failed. Retrying blindly can run the payment twice, so the operator checks first."
        case .clearingRejection:
            return "When clearing does not accept a payment, the payment cannot settle. The reason is recorded so it can be fixed."
        }
    }
}

// MARK: - Journey record (session only)

/// One injected fault, with the stage where it was injected.
struct LifecycleFaultInjection: Hashable {
    let fault: LifecycleFault
    let stage: PaymentLifecycleStage
}

/// The overall outcome of a simulator run.
enum LifecycleJourneyOutcome: Hashable {
    case inProgress
    case happyPathComplete
    case stoppedByFault
    case heldByFault
    case waitingAfterFault
    case endedEarly

    var title: String {
        switch self {
        case .inProgress: return "Run in progress"
        case .happyPathComplete: return "Happy path complete"
        case .stoppedByFault: return "Payment stopped"
        case .heldByFault: return "Payment held for review"
        case .waitingAfterFault: return "Payment waiting after a timeout"
        case .endedEarly: return "Run ended early"
        }
    }

    var systemImage: String {
        switch self {
        case .inProgress: return "play.circle.fill"
        case .happyPathComplete: return "checkmark.circle.fill"
        case .stoppedByFault: return "xmark.octagon.fill"
        case .heldByFault: return "pause.circle.fill"
        case .waitingAfterFault: return "clock.fill"
        case .endedEarly: return "flag.fill"
        }
    }

    /// Short plain language explanation of the outcome.
    var detail: String {
        switch self {
        case .inProgress:
            return "The run is still going. Keep stepping through the stages, or end the run to see the journey summary."
        case .happyPathComplete:
            return "The sample payment passed every stage with no injected fault. Every stage ran in order."
        case .stoppedByFault:
            return "An injected fault stopped the payment. The stages after the fault did not run."
        case .heldByFault:
            return "An injected fault held the payment for review. The stages after the fault waited for a decision."
        case .waitingAfterFault:
            return "An injected timeout left the outcome unknown. The stages after the fault waited while the operator checked what happened."
        case .endedEarly:
            return "The run was ended before the last stage. Only the stages visited are listed in the summary."
        }
    }
}

/// The record of one simulator run: which stages were visited, in
/// which order, and whether a fault was injected. Session only.
/// Nothing here is saved, stored or synced; leaving the screen
/// discards the run.
struct LifecycleJourney: Hashable {
    /// Stages visited, in the order first visited. Each stage
    /// appears at most once.
    private(set) var visitedStages: [PaymentLifecycleStage] = []
    private(set) var injection: LifecycleFaultInjection? = nil
    private(set) var reachedEnd: Bool = false
    private(set) var endedEarly: Bool = false

    mutating func visit(_ stage: PaymentLifecycleStage) {
        if !visitedStages.contains(stage) {
            visitedStages.append(stage)
        }
    }

    mutating func inject(_ fault: LifecycleFault, at stage: PaymentLifecycleStage) {
        visit(stage)
        injection = LifecycleFaultInjection(fault: fault, stage: stage)
    }

    /// Clears the injected fault so the learner can keep exploring.
    /// Visited stages stay visited; the run itself is not reset.
    mutating func clearInjection() {
        injection = nil
    }

    mutating func markReachedEnd() {
        reachedEnd = true
    }

    mutating func markEndedEarly() {
        endedEarly = true
    }

    mutating func reset() {
        visitedStages = []
        injection = nil
        reachedEnd = false
        endedEarly = false
    }

    /// Stages after the fault stage, in journey order. Empty when
    /// no fault was injected, or when the fault hit the last stage.
    var blockedStages: [PaymentLifecycleStage] {
        guard let injection else { return [] }
        return PaymentLifecycleStage.orderedStages.filter { $0.rawValue > injection.stage.rawValue }
    }

    /// Stages never visited in this run, in journey order.
    var unvisitedStages: [PaymentLifecycleStage] {
        PaymentLifecycleStage.orderedStages.filter { !visitedStages.contains($0) }
    }

    var outcome: LifecycleJourneyOutcome {
        if let injection {
            switch injection.fault.effect {
            case .stopped: return .stoppedByFault
            case .held: return .heldByFault
            case .waitingRetry: return .waitingAfterFault
            }
        }
        if reachedEnd { return .happyPathComplete }
        if endedEarly { return .endedEarly }
        return .inProgress
    }

    /// True when the run has an ending worth summarising: the end
    /// was reached, a fault was injected, or the learner ended early.
    var hasEnding: Bool {
        injection != nil || reachedEnd || endedEarly
    }
}
