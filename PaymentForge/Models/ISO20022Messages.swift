// ISO20022Messages.swift
// PaymentForge iOS - ISO 20022 message explorer content.
// Teaches message structure from the ISO 20022 base schema only.
// Mandatory and optional follow the base schema. Scheme usage guides,
// for example CBPR+ or SEPA, decide what is actually mandatory in a
// live payment; this file states no scheme rules, no scheme code
// lists and no usage mandates. Every sample value is fictional.
// No em dashes in any user-facing text.

import Foundation

// MARK: - Requirement (base schema only)

/// Whether an element is required by the ISO 20022 base schema.
/// A field marked mandatory is required when its parent block is
/// present. Scheme usage guides may tighten an optional field into
/// a required one; that decision lives with the scheme, never here.
enum ISO20022Requirement: String, Hashable {
    case mandatory
    case optional

    /// Short label for pills. The pill text itself differs, so the
    /// requirement is never carried by colour alone.
    var shortLabel: String {
        switch self {
        case .mandatory: return "Mandatory"
        case .optional: return "Optional"
        }
    }

    /// Full label spelling out that the base schema is the source.
    var label: String {
        switch self {
        case .mandatory: return "Mandatory in base schema"
        case .optional: return "Optional in base schema"
        }
    }
}

// MARK: - Message family

/// The three ISO 20022 business areas covered by this explorer.
enum ISO20022Family: String, Hashable, CaseIterable {
    case pain
    case pacs
    case camt

    var displayName: String {
        switch self {
        case .pain: return "Payment initiation"
        case .pacs: return "Payments clearing and settlement"
        case .camt: return "Cash management"
        }
    }

    var description: String {
        switch self {
        case .pain:
            return "Messages a customer sends to its bank, and the status reports that come back."
        case .pacs:
            return "Messages banks send to each other to move money, report status, return funds or reverse a payment."
        case .camt:
            return "Reports and notifications a bank sends to its customer about account balances and entries."
        }
    }

    var systemImage: String {
        switch self {
        case .pain: return "paperplane.fill"
        case .pacs: return "arrow.left.arrow.right"
        case .camt: return "doc.text.fill"
        }
    }
}

// MARK: - Field

/// One XML element in a message: a block that groups other elements,
/// or a leaf field that carries a value. Blocks carry children;
/// leaves carry an example value. Every element carries a
/// definition and a usage note, and its base-schema requirement.
struct ISO20022Field: Identifiable, Hashable {
    let id: String
    let element: String
    let definition: String
    let exampleValue: String?
    let usageNote: String
    let requirement: ISO20022Requirement
    let children: [ISO20022Field]

    init(
        id: String,
        element: String,
        definition: String,
        exampleValue: String? = nil,
        usageNote: String,
        requirement: ISO20022Requirement,
        children: [ISO20022Field] = []
    ) {
        self.id = id
        self.element = element
        self.definition = definition
        self.exampleValue = exampleValue
        self.usageNote = usageNote
        self.requirement = requirement
        self.children = children
    }
}

// MARK: - Relationship

/// How one message in this explorer relates to another. The related
/// message is always one of the ten covered messages, so the link
/// stays inside the explorer.
struct ISO20022Relationship: Identifiable, Hashable {
    /// The related message code, for example "pacs.002".
    let relatedMessageID: String
    /// The kind of link, for example "Answered by".
    let kind: String
    /// One sentence explaining the link.
    let note: String

    var id: String { relatedMessageID }
}

// MARK: - Validation problems (structural examples only)

/// One common structural validation problem, phrased as a general
/// educational example. These are structural checks only: whether a
/// live payment is accepted also depends on the scheme usage guide
/// and the receiving bank, which this explorer does not cover.
struct ISO20022ValidationProblem: Identifiable, Hashable {
    let title: String
    let explanation: String

    var id: String { title }

    /// The shared list shown for every message. The same structural
    /// checks apply to any XML message, so one honest list is used
    /// everywhere instead of inventing per-message problems.
    static let commonProblems: [ISO20022ValidationProblem] = [
        ISO20022ValidationProblem(
            title: "Malformed XML",
            explanation: "The file is not well formed XML: a missing closing tag, mismatched tags or a stray character stops any parser before the message content is even read."
        ),
        ISO20022ValidationProblem(
            title: "Missing required block",
            explanation: "A block the base schema requires is absent, for example a transaction block with no payment identification block. The file may parse as XML but still fails schema validation."
        ),
        ISO20022ValidationProblem(
            title: "Wrong data type",
            explanation: "A value has the wrong shape for its element, for example letters inside an amount or a date written in the wrong format. Schema validation rejects the value even though the tag name is right."
        ),
        ISO20022ValidationProblem(
            title: "Characters the receiver does not accept",
            explanation: "The text uses characters outside the set the receiving system accepts, for example an accented letter or a symbol the receiver cannot process. The message fails before it is processed."
        ),
        ISO20022ValidationProblem(
            title: "Duplicate identifiers within the file",
            explanation: "The same message or instruction identifier appears twice in one file, so the receiver cannot tell the two items apart. Identifiers must be unique within the file."
        ),
    ]
}

// MARK: - Message

/// One ISO 20022 message taught by the explorer: its purpose, an
/// abbreviated fictional sample, its field tree, and its links to
/// the other covered messages.
struct ISO20022Message: Identifiable, Hashable {
    /// The message code, for example "pacs.008". This is the id.
    let id: String
    /// The ISO 20022 message name, for example "FIToFICustomerCreditTransfer".
    let isoName: String
    /// The plain-language message name shown in lists.
    let displayName: String
    let family: ISO20022Family
    /// The purpose in one paragraph, in general educational wording.
    let purpose: String
    /// The root element inside Document, for example "FIToFICstmrCdtTrf".
    let rootElement: String
    /// Abbreviated sample XML with fictional values. The namespace
    /// declaration and non-essential blocks are omitted; the view
    /// labels every sample as abbreviated with fictional values.
    let sampleXML: String
    /// The top-level blocks of the message. Each block expands into
    /// its child elements in the view.
    let fields: [ISO20022Field]
    let relationships: [ISO20022Relationship]
}

// MARK: - Catalogue

/// The ten messages covered by this explorer, in teaching order:
/// initiation first, then bank-to-bank payments, then reports.
enum ISO20022Catalogue {
    static let messages: [ISO20022Message] = [
        ISO20022Message(
            id: "pain.001",
            isoName: "CustomerCreditTransferInitiation",
            displayName: "Customer Credit Transfer Initiation",
            family: .pain,
            purpose: "pain.001 is the message a customer sends to its bank to instruct one or more credit transfers. A company uses it to tell its bank to pay suppliers, salaries or other beneficiaries from its account. One file can carry many payments, grouped into payment information blocks that share a debtor account and an execution date. The bank answers with a pain.002 status report, and the payment itself then travels between banks as a pacs.008.",
            rootElement: "CstmrCdtTrfInitn",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <CstmrCdtTrfInitn>
                    <GrpHdr>
                      <MsgId>EXAMPLE-PAIN001-001</MsgId>
                      <CreDtTm>2026-11-12T09:30:00Z</CreDtTm>
                      <NbOfTxs>1</NbOfTxs>
                      <InitgPty>
                        <Nm>Example Buyer BV</Nm>
                      </InitgPty>
                    </GrpHdr>
                    <PmtInf>
                      <PmtInfId>EXAMPLE-PMTINF-001</PmtInfId>
                      <PmtMtd>TRF</PmtMtd>
                      <ReqdExctnDt>
                        <Dt>2026-11-13</Dt>
                      </ReqdExctnDt>
                      <Dbtr>
                        <Nm>Example Buyer BV</Nm>
                      </Dbtr>
                      <DbtrAcct>
                        <Id>
                          <IBAN>GB00FICT00000000000000</IBAN>
                        </Id>
                      </DbtrAcct>
                      <DbtrAgt>
                        <FinInstnId>
                          <BICFI>FCTNGB2L</BICFI>
                        </FinInstnId>
                      </DbtrAgt>
                      <CdtTrfTxInf>
                        <PmtId>
                          <InstrId>EXAMPLE-INSTR-001</InstrId>
                          <EndToEndId>EXAMPLE-E2E-001</EndToEndId>
                        </PmtId>
                        <Amt>
                          <InstdAmt Ccy="EUR">12500.00</InstdAmt>
                        </Amt>
                        <Cdtr>
                          <Nm>Example Seller Ltd</Nm>
                        </Cdtr>
                        <CdtrAcct>
                          <Id>
                            <IBAN>DE00000000000000000000</IBAN>
                          </Id>
                        </CdtrAcct>
                        <RmtInf>
                          <Ustrd>Invoice EXAMPLE-INV-1001</Ustrd>
                        </RmtInf>
                      </CdtTrfTxInf>
                    </PmtInf>
                  </CstmrCdtTrfInitn>
                </Document>
                """,
            fields: [
                ISO20022Field(
                    id: "pain.001-grphdr",
                    element: "GrpHdr",
                    definition: "The group header. It identifies the whole file and says who sent it, so the bank can log, acknowledge and deduplicate the instruction.",
                    usageNote: "One group header per file. It describes the file as a whole, never a single payment.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pain.001-grphdr-msgid",
                            element: "MsgId",
                            definition: "The unique reference the sender gives this file. The bank uses it to spot a file sent twice.",
                            exampleValue: "EXAMPLE-PAIN001-001",
                            usageNote: "Give every file a new reference. Reusing a reference makes the file look like a duplicate.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pain.001-grphdr-credttm",
                            element: "CreDtTm",
                            definition: "The date and time the sender created the file.",
                            exampleValue: "2026-11-12T09:30:00Z",
                            usageNote: "Use the creation time of the file, not the time the payments should run.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pain.001-grphdr-nboftxs",
                            element: "NbOfTxs",
                            definition: "How many payment transactions the file contains.",
                            exampleValue: "1",
                            usageNote: "Count every transaction block in the file. A wrong count is a common reconciliation break.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pain.001-grphdr-initgpty",
                            element: "InitgPty",
                            definition: "The party that created the instruction, usually the customer sending the file.",
                            usageNote: "Name the sender of the file. It is the party the bank holds responsible for the instruction.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pain.001-grphdr-initgpty-nm",
                                    element: "Nm",
                                    definition: "The name of the initiating party.",
                                    exampleValue: "Example Buyer BV",
                                    usageNote: "Use the name the bank knows the customer by.",
                                    requirement: .optional
                                ),
                            ]
                        ),
                    ]
                ),
                ISO20022Field(
                    id: "pain.001-pmtinf",
                    element: "PmtInf",
                    definition: "One payment information block. It groups transactions that share a debtor account and payment terms, and it carries the execution date and the debtor details for the whole group.",
                    usageNote: "Use one block per debtor account and execution date combination. A file can carry several blocks.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pain.001-pmtinf-pmtinfid",
                            element: "PmtInfId",
                            definition: "The unique reference for this payment information block within the file.",
                            exampleValue: "EXAMPLE-PMTINF-001",
                            usageNote: "Status reports quote this reference back, so keep it stable and unique.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pain.001-pmtinf-pmtmtd",
                            element: "PmtMtd",
                            definition: "How the payment is made. For a credit transfer file this is a transfer.",
                            exampleValue: "TRF",
                            usageNote: "TRF is the widely used code for a transfer. This explorer does not reproduce code lists.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pain.001-pmtinf-reqdexctndt",
                            element: "ReqdExctnDt",
                            definition: "The date the customer asks the bank to execute the payments in this block.",
                            exampleValue: "2026-11-13",
                            usageNote: "Use it when the payments must run on a particular date. When it is absent, timing follows the agreement with the bank.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pain.001-pmtinf-dbtr",
                            element: "Dbtr",
                            definition: "The debtor: the party whose account is debited for the payments in this block.",
                            usageNote: "One debtor per block. Every transaction in the block debits this party.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pain.001-pmtinf-dbtr-nm",
                                    element: "Nm",
                                    definition: "The name of the debtor.",
                                    exampleValue: "Example Buyer BV",
                                    usageNote: "Use the account holder name as the bank holds it.",
                                    requirement: .optional
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pain.001-pmtinf-dbtracc",
                            element: "DbtrAcct",
                            definition: "The account to debit for the payments in this block.",
                            usageNote: "The account must belong to the debtor named in this block.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pain.001-pmtinf-dbtracc-id",
                                    element: "Id",
                                    definition: "The account identification block. It holds one form of account identifier.",
                                    usageNote: "One identifier form per account block. The base schema offers a choice of forms.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pain.001-pmtinf-dbtracc-id-iban",
                                            element: "IBAN",
                                            definition: "The International Bank Account Number for the account.",
                                            exampleValue: "GB00FICT00000000000000",
                                            usageNote: "Fictional value in this sample. In a live file the IBAN must be the real account number.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pain.001-pmtinf-dbtragt",
                            element: "DbtrAgt",
                            definition: "The debtor agent: the bank that holds the debtor account.",
                            usageNote: "Name the bank that will debit the account.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pain.001-pmtinf-dbtragt-fininstnid",
                                    element: "FinInstnId",
                                    definition: "The financial institution identification block for the debtor agent.",
                                    usageNote: "It holds the bank identifier, usually a BIC.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pain.001-pmtinf-dbtragt-fininstnid-bicfi",
                                            element: "BICFI",
                                            definition: "The Business Identifier Code of the financial institution.",
                                            exampleValue: "FCTNGB2L",
                                            usageNote: "Fictional value in this sample. In a live file this is the real BIC of the bank.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pain.001-pmtinf-cdttrftxinf",
                            element: "CdtTrfTxInf",
                            definition: "One credit transfer transaction: a single payment to a single creditor, with its own references, amount and remittance information.",
                            usageNote: "One block per payment. A block can repeat many times inside one payment information block.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pain.001-pmtinf-cdttrftxinf-pmtid",
                                    element: "PmtId",
                                    definition: "The payment identification block. It holds the references that let every party match this payment through its life.",
                                    usageNote: "References set here travel with the payment into the bank-to-bank messages.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pain.001-pmtinf-cdttrftxinf-pmtid-instrid",
                                            element: "InstrId",
                                            definition: "The instruction reference given by the instructing party for this single transaction.",
                                            exampleValue: "EXAMPLE-INSTR-001",
                                            usageNote: "Use a reference the sender can quote when asking about this payment.",
                                            requirement: .optional
                                        ),
                                        ISO20022Field(
                                            id: "pain.001-pmtinf-cdttrftxinf-pmtid-endtoendid",
                                            element: "EndToEndId",
                                            definition: "The end-to-end reference that travels unchanged with the payment from originator to beneficiary, so both ends can match the same payment.",
                                            exampleValue: "EXAMPLE-E2E-001",
                                            usageNote: "Optional in the base schema, and often required by scheme usage guides. When present, it must pass through unchanged.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                                ISO20022Field(
                                    id: "pain.001-pmtinf-cdttrftxinf-amt",
                                    element: "Amt",
                                    definition: "The amount block for this transaction.",
                                    usageNote: "It holds the instructed amount for the payment.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pain.001-pmtinf-cdttrftxinf-amt-instdamt",
                                            element: "InstdAmt",
                                            definition: "The amount to pay, with the currency carried as an attribute.",
                                            exampleValue: "12500.00 EUR",
                                            usageNote: "Fictional amount in this sample. The currency attribute is part of the value, not a separate field.",
                                            requirement: .mandatory
                                        ),
                                    ]
                                ),
                                ISO20022Field(
                                    id: "pain.001-pmtinf-cdttrftxinf-cdtr",
                                    element: "Cdtr",
                                    definition: "The creditor: the party to be paid.",
                                    usageNote: "Name the beneficiary of this single payment.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pain.001-pmtinf-cdttrftxinf-cdtr-nm",
                                            element: "Nm",
                                            definition: "The name of the creditor.",
                                            exampleValue: "Example Seller Ltd",
                                            usageNote: "Use the name on the beneficiary account.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                                ISO20022Field(
                                    id: "pain.001-pmtinf-cdttrftxinf-cdtracct",
                                    element: "CdtrAcct",
                                    definition: "The account to credit for this payment.",
                                    usageNote: "The account must belong to the creditor named in this transaction.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pain.001-pmtinf-cdttrftxinf-cdtracct-id",
                                            element: "Id",
                                            definition: "The account identification block. It holds one form of account identifier.",
                                            usageNote: "One identifier form per account block. The base schema offers a choice of forms.",
                                            requirement: .mandatory,
                                            children: [
                                                ISO20022Field(
                                                    id: "pain.001-pmtinf-cdttrftxinf-cdtracct-id-iban",
                                                    element: "IBAN",
                                                    definition: "The International Bank Account Number for the account.",
                                                    exampleValue: "DE00000000000000000000",
                                                    usageNote: "Fictional value in this sample. In a live file the IBAN must be the real account number.",
                                                    requirement: .optional
                                                ),
                                            ]
                                        ),
                                    ]
                                ),
                                ISO20022Field(
                                    id: "pain.001-pmtinf-cdttrftxinf-rmtinf",
                                    element: "RmtInf",
                                    definition: "Remittance information: what the payment is for, so the creditor can match it to an invoice or account.",
                                    usageNote: "Keep it short and useful to the creditor. It travels with the payment.",
                                    requirement: .optional,
                                    children: [
                                        ISO20022Field(
                                            id: "pain.001-pmtinf-cdttrftxinf-rmtinf-ustrd",
                                            element: "Ustrd",
                                            definition: "Unstructured remittance information: free text describing the payment.",
                                            exampleValue: "Invoice EXAMPLE-INV-1001",
                                            usageNote: "Use plain text the creditor can read. Structured remittance forms exist but are outside this abbreviated sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            relationships: [
                ISO20022Relationship(
                    relatedMessageID: "pain.002",
                    kind: "Answered by",
                    note: "The bank reports whether it accepted or rejected this instruction."
                ),
                ISO20022Relationship(
                    relatedMessageID: "pacs.008",
                    kind: "Leads to",
                    note: "The bank-to-bank message that carries the payment onward between banks."
                ),
            ]
        ),
        ISO20022Message(
            id: "pain.002",
            isoName: "CustomerPaymentStatusReport",
            displayName: "Customer Payment Status Report",
            family: .pain,
            purpose: "pain.002 is the status report a bank sends back to its customer about a pain.001 instruction. It says whether a group of payments, a payment information block or a single transaction was accepted, rejected or is still pending, and it gives a reason when something was rejected. The customer matches each status entry back to the original instruction using the original message and instruction references.",
            rootElement: "CstmrPmtStsRpt",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <CstmrPmtStsRpt>
                    <GrpHdr>
                      <MsgId>EXAMPLE-PAIN002-001</MsgId>
                      <CreDtTm>2026-11-12T09:35:00Z</CreDtTm>
                      <InitgPty>
                        <Nm>Example Bank</Nm>
                      </InitgPty>
                    </GrpHdr>
                    <OrgnlGrpInfAndSts>
                      <OrgnlMsgId>EXAMPLE-PAIN001-001</OrgnlMsgId>
                      <OrgnlMsgNmId>pain.001.001.09</OrgnlMsgNmId>
                      <GrpSts>ACCP</GrpSts>
                    </OrgnlGrpInfAndSts>
                    <OrgnlPmtInfAndSts>
                      <OrgnlPmtInfId>EXAMPLE-PMTINF-001</OrgnlPmtInfId>
                      <PmtInfSts>ACCP</PmtInfSts>
                      <TxInfAndSts>
                        <OrgnlInstrId>EXAMPLE-INSTR-001</OrgnlInstrId>
                        <OrgnlEndToEndId>EXAMPLE-E2E-001</OrgnlEndToEndId>
                        <TxSts>ACCP</TxSts>
                      </TxInfAndSts>
                    </OrgnlPmtInfAndSts>
                  </CstmrPmtStsRpt>
                </Document>
                """,
            fields: [
                ISO20022Field(
                    id: "pain.002-grphdr",
                    element: "GrpHdr",
                    definition: "The group header. It identifies this status report and says who sent it.",
                    usageNote: "One group header per report. It describes the report, never the original instruction.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pain.002-grphdr-msgid",
                            element: "MsgId",
                            definition: "The unique reference the sender gives this status report.",
                            exampleValue: "EXAMPLE-PAIN002-001",
                            usageNote: "Give every report a new reference, distinct from the original instruction reference.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pain.002-grphdr-credttm",
                            element: "CreDtTm",
                            definition: "The date and time the sender created the report.",
                            exampleValue: "2026-11-12T09:35:00Z",
                            usageNote: "Use the creation time of the report.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pain.002-grphdr-initgpty",
                            element: "InitgPty",
                            definition: "The party that created the report, usually the bank answering the instruction.",
                            usageNote: "Name the sender of the report, not the original customer.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pain.002-grphdr-initgpty-nm",
                                    element: "Nm",
                                    definition: "The name of the initiating party.",
                                    exampleValue: "Example Bank",
                                    usageNote: "Fictional name in this sample.",
                                    requirement: .optional
                                ),
                            ]
                        ),
                    ]
                ),
                ISO20022Field(
                    id: "pain.002-orgnlgrpinfandsts",
                    element: "OrgnlGrpInfAndSts",
                    definition: "Information about the original group of payments, with the status for the group as a whole. It points back to the original pain.001 file.",
                    usageNote: "Read this first: it says which original file the report answers and how the group fared overall.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pain.002-orgnlgrpinfandsts-orgnlmsgid",
                            element: "OrgnlMsgId",
                            definition: "The message reference of the original instruction, copied from its group header.",
                            exampleValue: "EXAMPLE-PAIN001-001",
                            usageNote: "Match this against the MsgId of the pain.001 file that was sent.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pain.002-orgnlgrpinfandsts-orgnlmsgnmid",
                            element: "OrgnlMsgNmId",
                            definition: "The full name of the original message, including its version.",
                            exampleValue: "pain.001.001.09",
                            usageNote: "The version suffix is part of the name. It says exactly which message definition the original used.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pain.002-orgnlgrpinfandsts-grpsts",
                            element: "GrpSts",
                            definition: "The status of the original group as a whole, as a code.",
                            exampleValue: "ACCP",
                            usageNote: "ACCP is the widely used code for accepted. A group can also be reported at block or transaction level instead. This explorer does not reproduce code lists.",
                            requirement: .optional
                        ),
                    ]
                ),
                ISO20022Field(
                    id: "pain.002-orgnlpmtinfandsts",
                    element: "OrgnlPmtInfAndSts",
                    definition: "Status for one original payment information block, with status entries for its individual transactions.",
                    usageNote: "One block per original payment information block being reported on.",
                    requirement: .optional,
                    children: [
                        ISO20022Field(
                            id: "pain.002-orgnlpmtinfandsts-orgnlpmtinfid",
                            element: "OrgnlPmtInfId",
                            definition: "The reference of the original payment information block, copied from the pain.001 file.",
                            exampleValue: "EXAMPLE-PMTINF-001",
                            usageNote: "Match this against the PmtInfId in the original instruction.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pain.002-orgnlpmtinfandsts-pmtinfsts",
                            element: "PmtInfSts",
                            definition: "The status of the original payment information block as a whole, as a code.",
                            exampleValue: "ACCP",
                            usageNote: "ACCP is the widely used code for accepted. This explorer does not reproduce code lists.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pain.002-orgnlpmtinfandsts-txinfandsts",
                            element: "TxInfAndSts",
                            definition: "Status for one original transaction, with the original references that identify it.",
                            usageNote: "One entry per transaction being reported on. The original references are what let the customer match the status to its own payment record.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pain.002-orgnlpmtinfandsts-txinfandsts-orgnlinstrid",
                                    element: "OrgnlInstrId",
                                    definition: "The instruction reference from the original transaction, copied from its payment identification block.",
                                    exampleValue: "EXAMPLE-INSTR-001",
                                    usageNote: "Quote back exactly what the original carried. Do not invent a new reference here.",
                                    requirement: .optional
                                ),
                                ISO20022Field(
                                    id: "pain.002-orgnlpmtinfandsts-txinfandsts-orgnlendtoendid",
                                    element: "OrgnlEndToEndId",
                                    definition: "The end-to-end reference from the original transaction, copied from its payment identification block.",
                                    exampleValue: "EXAMPLE-E2E-001",
                                    usageNote: "This is the reference the originator and beneficiary both know, so it is the most useful matching key.",
                                    requirement: .optional
                                ),
                                ISO20022Field(
                                    id: "pain.002-orgnlpmtinfandsts-txinfandsts-txsts",
                                    element: "TxSts",
                                    definition: "The status of this single transaction, as a code.",
                                    exampleValue: "ACCP",
                                    usageNote: "ACCP is the widely used code for accepted. When a transaction is rejected, a reason block explains why. This explorer does not reproduce code lists.",
                                    requirement: .optional
                                ),
                                ISO20022Field(
                                    id: "pain.002-orgnlpmtinfandsts-txinfandsts-stsrsninf",
                                    element: "StsRsnInf",
                                    definition: "Status reason information: why a transaction has the status it has, used in particular for rejections.",
                                    usageNote: "Read this block whenever a status is a rejection. It carries the reason code and any extra explanation.",
                                    requirement: .optional
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            relationships: [
                ISO20022Relationship(
                    relatedMessageID: "pain.001",
                    kind: "Reports on",
                    note: "This report answers a customer credit transfer instruction."
                ),
                ISO20022Relationship(
                    relatedMessageID: "pacs.002",
                    kind: "Companion to",
                    note: "The bank-to-bank equivalent: a status report between financial institutions."
                ),
            ]
        ),
        ISO20022Message(
            id: "pacs.008",
            isoName: "FIToFICustomerCreditTransfer",
            displayName: "FI to FI Customer Credit Transfer",
            family: .pacs,
            purpose: "pacs.008 is the message one financial institution sends to another to move a customer payment between banks. It carries the amount, the debtor and creditor details, the charges instruction and the references that let every bank in the chain track the same payment, including the end-to-end reference and the UETR. A pacs.008 can be answered by a pacs.002 status report, returned with a pacs.004, or reversed with a pacs.007.",
            rootElement: "FIToFICstmrCdtTrf",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <FIToFICstmrCdtTrf>
                    <GrpHdr>
                      <MsgId>EXAMPLE-PACS008-001</MsgId>
                      <CreDtTm>2026-11-12T09:32:00Z</CreDtTm>
                      <NbOfTxs>1</NbOfTxs>
                      <SttlmInf>
                        <SttlmMtd>INDA</SttlmMtd>
                      </SttlmInf>
                    </GrpHdr>
                    <CdtTrfTxInf>
                      <PmtId>
                        <InstrId>EXAMPLE-INSTR-001</InstrId>
                        <EndToEndId>EXAMPLE-E2E-001</EndToEndId>
                        <UETR>123e4567-e89b-42d3-a456-426614174000</UETR>
                      </PmtId>
                      <IntrBkSttlmAmt Ccy="EUR">12500.00</IntrBkSttlmAmt>
                      <IntrBkSttlmDt>2026-11-13</IntrBkSttlmDt>
                      <ChrgBr>SHAR</ChrgBr>
                      <InstgAgt>
                        <FinInstnId>
                          <BICFI>FCTNGB2L</BICFI>
                        </FinInstnId>
                      </InstgAgt>
                      <InstdAgt>
                        <FinInstnId>
                          <BICFI>FCTNDEFF</BICFI>
                        </FinInstnId>
                      </InstdAgt>
                      <Dbtr>
                        <Nm>Example Buyer BV</Nm>
                      </Dbtr>
                      <DbtrAcct>
                        <Id>
                          <IBAN>GB00FICT00000000000000</IBAN>
                        </Id>
                      </DbtrAcct>
                      <CdtrAgt>
                        <FinInstnId>
                          <BICFI>FCTNDEFF</BICFI>
                        </FinInstnId>
                      </CdtrAgt>
                      <Cdtr>
                        <Nm>Example Seller Ltd</Nm>
                      </Cdtr>
                      <CdtrAcct>
                        <Id>
                          <IBAN>DE00000000000000000000</IBAN>
                        </Id>
                      </CdtrAcct>
                      <RmtInf>
                        <Ustrd>Invoice EXAMPLE-INV-1001</Ustrd>
                      </RmtInf>
                    </CdtTrfTxInf>
                  </FIToFICstmrCdtTrf>
                </Document>
                """,
            fields: [
                ISO20022Field(
                    id: "pacs.008-grphdr",
                    element: "GrpHdr",
                    definition: "The group header. It identifies the whole message and carries the settlement information shared by its transactions.",
                    usageNote: "One group header per message. Settlement details here apply to every transaction in the message.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pacs.008-grphdr-msgid",
                            element: "MsgId",
                            definition: "The unique reference the sender gives this message.",
                            exampleValue: "EXAMPLE-PACS008-001",
                            usageNote: "Give every message a new reference. Reusing one makes the message look like a duplicate.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.008-grphdr-credttm",
                            element: "CreDtTm",
                            definition: "The date and time the sender created the message.",
                            exampleValue: "2026-11-12T09:32:00Z",
                            usageNote: "Use the creation time of the message.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.008-grphdr-nboftxs",
                            element: "NbOfTxs",
                            definition: "How many credit transfer transactions the message contains.",
                            exampleValue: "1",
                            usageNote: "Count every transaction block in the message.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.008-grphdr-sttlminf",
                            element: "SttlmInf",
                            definition: "Settlement information: how the amount is settled between the banks.",
                            usageNote: "It describes the settlement method for the message. The settlement date itself sits on each transaction.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.008-grphdr-sttlminf-sttlmmtd",
                                    element: "SttlmMtd",
                                    definition: "The settlement method, as a code.",
                                    exampleValue: "INDA",
                                    usageNote: "INDA is the widely used code for settlement through the instructed agent. This explorer does not reproduce code lists.",
                                    requirement: .mandatory
                                ),
                            ]
                        ),
                    ]
                ),
                ISO20022Field(
                    id: "pacs.008-cdttrftxinf",
                    element: "CdtTrfTxInf",
                    definition: "One credit transfer transaction: a single customer payment moving between two banks, with its references, amounts, parties and remittance information.",
                    usageNote: "One block per payment. A message can carry several transactions that share the group header.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-pmtid",
                            element: "PmtId",
                            definition: "The payment identification block. It holds the references that let every bank in the chain track the same payment.",
                            usageNote: "References set here are quoted back by status reports, returns and reversals.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pacs.008-cdttrftxinf-pmtid-instrid",
                                    element: "InstrId",
                                    definition: "The instruction reference given by the instructing party for this transaction.",
                                    exampleValue: "EXAMPLE-INSTR-001",
                                    usageNote: "Carried over from the original instruction when the payment started as a pain.001.",
                                    requirement: .optional
                                ),
                                ISO20022Field(
                                    id: "pacs.008-cdttrftxinf-pmtid-endtoendid",
                                    element: "EndToEndId",
                                    definition: "The end-to-end reference that travels unchanged with the payment from originator to beneficiary.",
                                    exampleValue: "EXAMPLE-E2E-001",
                                    usageNote: "Optional in the base schema, and often required by scheme usage guides. When present, it must pass through unchanged.",
                                    requirement: .optional
                                ),
                                ISO20022Field(
                                    id: "pacs.008-cdttrftxinf-pmtid-uetr",
                                    element: "UETR",
                                    definition: "The Unique End-to-end Transaction Reference: a globally unique reference that identifies the payment across every bank and message in its journey.",
                                    exampleValue: "123e4567-e89b-42d3-a456-426614174000",
                                    usageNote: "Illustrative value in this sample, using the well known example UUID. Optional in the base schema, and often required by scheme usage guides for cross-border payments.",
                                    requirement: .optional
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-intrkbksttlmamt",
                            element: "IntrBkSttlmAmt",
                            definition: "The interbank settlement amount: the amount to settle between the banks, with the currency carried as an attribute.",
                            exampleValue: "12500.00 EUR",
                            usageNote: "Fictional amount in this sample. This is the amount the banks settle, which can differ from the amount the customer instructed.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-intrkbksttlmdt",
                            element: "IntrBkSttlmDt",
                            definition: "The interbank settlement date: the date the banks settle the amount.",
                            exampleValue: "2026-11-13",
                            usageNote: "Use the date the settlement is due between the banks.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-instdamt",
                            element: "InstdAmt",
                            definition: "The instructed amount: the amount as originally instructed, used when it differs from the settlement amount, for example after a currency conversion.",
                            exampleValue: "12500.00 EUR",
                            usageNote: "Omit it when the instructed amount and the settlement amount are the same.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-chrgbr",
                            element: "ChrgBr",
                            definition: "The charge bearer: who bears the charges for the payment, as a code.",
                            exampleValue: "SHAR",
                            usageNote: "SHAR is one of the charge bearer codes and means the charges are shared. This explorer does not reproduce code lists.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-instgagt",
                            element: "InstgAgt",
                            definition: "The instructing agent: the bank sending this message.",
                            usageNote: "Name the bank that instructs the next bank in the chain.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.008-cdttrftxinf-instgagt-fininstnid",
                                    element: "FinInstnId",
                                    definition: "The financial institution identification block for the instructing agent.",
                                    usageNote: "It holds the bank identifier, usually a BIC.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.008-cdttrftxinf-instgagt-fininstnid-bicfi",
                                            element: "BICFI",
                                            definition: "The Business Identifier Code of the financial institution.",
                                            exampleValue: "FCTNGB2L",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-instdagt",
                            element: "InstdAgt",
                            definition: "The instructed agent: the bank receiving this message.",
                            usageNote: "Name the bank being instructed to act on the payment.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.008-cdttrftxinf-instdagt-fininstnid",
                                    element: "FinInstnId",
                                    definition: "The financial institution identification block for the instructed agent.",
                                    usageNote: "It holds the bank identifier, usually a BIC.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.008-cdttrftxinf-instdagt-fininstnid-bicfi",
                                            element: "BICFI",
                                            definition: "The Business Identifier Code of the financial institution.",
                                            exampleValue: "FCTNDEFF",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-dbtr",
                            element: "Dbtr",
                            definition: "The debtor: the customer whose payment this is.",
                            usageNote: "Name the originator of the payment, not the bank sending the message.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pacs.008-cdttrftxinf-dbtr-nm",
                                    element: "Nm",
                                    definition: "The name of the debtor.",
                                    exampleValue: "Example Buyer BV",
                                    usageNote: "Use the name on the debtor account.",
                                    requirement: .optional
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-dbtracc",
                            element: "DbtrAcct",
                            definition: "The debtor account.",
                            usageNote: "The account the payment is funded from.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.008-cdttrftxinf-dbtracc-id",
                                    element: "Id",
                                    definition: "The account identification block. It holds one form of account identifier.",
                                    usageNote: "One identifier form per account block. The base schema offers a choice of forms.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.008-cdttrftxinf-dbtracc-id-iban",
                                            element: "IBAN",
                                            definition: "The International Bank Account Number for the account.",
                                            exampleValue: "GB00FICT00000000000000",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-cdtragt",
                            element: "CdtrAgt",
                            definition: "The creditor agent: the bank that holds the creditor account.",
                            usageNote: "Name the bank that will credit the beneficiary.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.008-cdttrftxinf-cdtragt-fininstnid",
                                    element: "FinInstnId",
                                    definition: "The financial institution identification block for the creditor agent.",
                                    usageNote: "It holds the bank identifier, usually a BIC.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.008-cdttrftxinf-cdtragt-fininstnid-bicfi",
                                            element: "BICFI",
                                            definition: "The Business Identifier Code of the financial institution.",
                                            exampleValue: "FCTNDEFF",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-cdtr",
                            element: "Cdtr",
                            definition: "The creditor: the customer to be paid.",
                            usageNote: "Name the beneficiary of the payment, not the bank holding the account.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pacs.008-cdttrftxinf-cdtr-nm",
                                    element: "Nm",
                                    definition: "The name of the creditor.",
                                    exampleValue: "Example Seller Ltd",
                                    usageNote: "Use the name on the beneficiary account.",
                                    requirement: .optional
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-cdtracct",
                            element: "CdtrAcct",
                            definition: "The creditor account.",
                            usageNote: "The account to credit for this payment.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.008-cdttrftxinf-cdtracct-id",
                                    element: "Id",
                                    definition: "The account identification block. It holds one form of account identifier.",
                                    usageNote: "One identifier form per account block. The base schema offers a choice of forms.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.008-cdttrftxinf-cdtracct-id-iban",
                                            element: "IBAN",
                                            definition: "The International Bank Account Number for the account.",
                                            exampleValue: "DE00000000000000000000",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.008-cdttrftxinf-rmtinf",
                            element: "RmtInf",
                            definition: "Remittance information: what the payment is for, so the creditor can match it to an invoice or account.",
                            usageNote: "It travels with the payment to the beneficiary.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.008-cdttrftxinf-rmtinf-ustrd",
                                    element: "Ustrd",
                                    definition: "Unstructured remittance information: free text describing the payment.",
                                    exampleValue: "Invoice EXAMPLE-INV-1001",
                                    usageNote: "Use plain text the creditor can read.",
                                    requirement: .optional
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            relationships: [
                ISO20022Relationship(
                    relatedMessageID: "pain.001",
                    kind: "Follows",
                    note: "A customer instruction often becomes a pacs.008 between banks."
                ),
                ISO20022Relationship(
                    relatedMessageID: "pacs.002",
                    kind: "Answered by",
                    note: "The receiving bank reports whether it accepted or rejected the payment."
                ),
                ISO20022Relationship(
                    relatedMessageID: "pacs.004",
                    kind: "Can trigger",
                    note: "The receiving side can return the funds when the payment cannot be applied."
                ),
                ISO20022Relationship(
                    relatedMessageID: "pacs.007",
                    kind: "Can trigger",
                    note: "The sending side can reverse the payment, for example when it was sent twice."
                ),
            ]
        ),
        ISO20022Message(
            id: "pacs.009",
            isoName: "FinancialInstitutionCreditTransfer",
            displayName: "Financial Institution Credit Transfer",
            family: .pacs,
            purpose: "pacs.009 is the message one financial institution uses to pay another financial institution from its own funds, rather than on behalf of a customer. Typical uses are funding an account the bank holds with another bank, settling positions between banks, or moving liquidity. It has the same settlement amount and agent structure as pacs.008, but its transaction block names the institutions directly instead of carrying a customer payment instruction.",
            rootElement: "FIToFICdtTrf",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <FIToFICdtTrf>
                    <GrpHdr>
                      <MsgId>EXAMPLE-PACS009-001</MsgId>
                      <CreDtTm>2026-11-12T10:00:00Z</CreDtTm>
                      <NbOfTxs>1</NbOfTxs>
                      <SttlmInf>
                        <SttlmMtd>INDA</SttlmMtd>
                      </SttlmInf>
                    </GrpHdr>
                    <CdtTrfTxInf>
                      <PmtId>
                        <InstrId>EXAMPLE-PACS009-INSTR-001</InstrId>
                        <EndToEndId>EXAMPLE-PACS009-E2E-001</EndToEndId>
                        <UETR>123e4567-e89b-42d3-a456-426614174000</UETR>
                      </PmtId>
                      <IntrBkSttlmAmt Ccy="EUR">500000.00</IntrBkSttlmAmt>
                      <IntrBkSttlmDt>2026-11-12</IntrBkSttlmDt>
                      <InstgAgt>
                        <FinInstnId>
                          <BICFI>FCTNGB2L</BICFI>
                        </FinInstnId>
                      </InstgAgt>
                      <InstdAgt>
                        <FinInstnId>
                          <BICFI>FCTNDEFF</BICFI>
                        </FinInstnId>
                      </InstdAgt>
                      <Dbtr>
                        <FinInstnId>
                          <BICFI>FCTNGB2L</BICFI>
                        </FinInstnId>
                      </Dbtr>
                      <DbtrAcct>
                        <Id>
                          <IBAN>GB00FICT00000000000000</IBAN>
                        </Id>
                      </DbtrAcct>
                      <Cdtr>
                        <FinInstnId>
                          <BICFI>FCTNDEFF</BICFI>
                        </FinInstnId>
                      </Cdtr>
                      <CdtrAcct>
                        <Id>
                          <IBAN>DE00000000000000000000</IBAN>
                        </Id>
                      </CdtrAcct>
                    </CdtTrfTxInf>
                  </FIToFICdtTrf>
                </Document>
                """,
            fields: [
                ISO20022Field(
                    id: "pacs.009-grphdr",
                    element: "GrpHdr",
                    definition: "The group header. It identifies the whole message and carries the settlement information shared by its transactions.",
                    usageNote: "One group header per message. Settlement details here apply to every transaction in the message.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pacs.009-grphdr-msgid",
                            element: "MsgId",
                            definition: "The unique reference the sender gives this message.",
                            exampleValue: "EXAMPLE-PACS009-001",
                            usageNote: "Give every message a new reference. Reusing one makes the message look like a duplicate.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.009-grphdr-credttm",
                            element: "CreDtTm",
                            definition: "The date and time the sender created the message.",
                            exampleValue: "2026-11-12T10:00:00Z",
                            usageNote: "Use the creation time of the message.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.009-grphdr-nboftxs",
                            element: "NbOfTxs",
                            definition: "How many credit transfer transactions the message contains.",
                            exampleValue: "1",
                            usageNote: "Count every transaction block in the message.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.009-grphdr-sttlminf",
                            element: "SttlmInf",
                            definition: "Settlement information: how the amount is settled between the banks.",
                            usageNote: "It describes the settlement method for the message.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.009-grphdr-sttlminf-sttlmmtd",
                                    element: "SttlmMtd",
                                    definition: "The settlement method, as a code.",
                                    exampleValue: "INDA",
                                    usageNote: "INDA is the widely used code for settlement through the instructed agent. This explorer does not reproduce code lists.",
                                    requirement: .mandatory
                                ),
                            ]
                        ),
                    ]
                ),
                ISO20022Field(
                    id: "pacs.009-cdttrftxinf",
                    element: "CdtTrfTxInf",
                    definition: "One credit transfer transaction between two financial institutions, with its references, settlement amount and the institutions involved.",
                    usageNote: "One block per transfer. The debtor and creditor here are institutions, not customers.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pacs.009-cdttrftxinf-pmtid",
                            element: "PmtId",
                            definition: "The payment identification block. It holds the references that let both banks track the same transfer.",
                            usageNote: "References set here are quoted back by status reports and reversals.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pacs.009-cdttrftxinf-pmtid-instrid",
                                    element: "InstrId",
                                    definition: "The instruction reference given by the instructing institution for this transaction.",
                                    exampleValue: "EXAMPLE-PACS009-INSTR-001",
                                    usageNote: "Use a reference the sender can quote when asking about this transfer.",
                                    requirement: .optional
                                ),
                                ISO20022Field(
                                    id: "pacs.009-cdttrftxinf-pmtid-endtoendid",
                                    element: "EndToEndId",
                                    definition: "The end-to-end reference that travels unchanged with the transfer.",
                                    exampleValue: "EXAMPLE-PACS009-E2E-001",
                                    usageNote: "When present, it must pass through unchanged.",
                                    requirement: .optional
                                ),
                                ISO20022Field(
                                    id: "pacs.009-cdttrftxinf-pmtid-uetr",
                                    element: "UETR",
                                    definition: "The Unique End-to-end Transaction Reference: a globally unique reference that identifies the transfer across every message in its journey.",
                                    exampleValue: "123e4567-e89b-42d3-a456-426614174000",
                                    usageNote: "Illustrative value in this sample, using the well known example UUID.",
                                    requirement: .optional
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.009-cdttrftxinf-intrkbksttlmamt",
                            element: "IntrBkSttlmAmt",
                            definition: "The interbank settlement amount: the amount to settle between the banks, with the currency carried as an attribute.",
                            exampleValue: "500000.00 EUR",
                            usageNote: "Fictional amount in this sample.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.009-cdttrftxinf-intrkbksttlmdt",
                            element: "IntrBkSttlmDt",
                            definition: "The interbank settlement date: the date the banks settle the amount.",
                            exampleValue: "2026-11-12",
                            usageNote: "Use the date the settlement is due between the banks.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.009-cdttrftxinf-instgagt",
                            element: "InstgAgt",
                            definition: "The instructing agent: the bank sending this message.",
                            usageNote: "Name the bank that instructs the next bank in the chain.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.009-cdttrftxinf-instgagt-fininstnid",
                                    element: "FinInstnId",
                                    definition: "The financial institution identification block for the instructing agent.",
                                    usageNote: "It holds the bank identifier, usually a BIC.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.009-cdttrftxinf-instgagt-fininstnid-bicfi",
                                            element: "BICFI",
                                            definition: "The Business Identifier Code of the financial institution.",
                                            exampleValue: "FCTNGB2L",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.009-cdttrftxinf-instdagt",
                            element: "InstdAgt",
                            definition: "The instructed agent: the bank receiving this message.",
                            usageNote: "Name the bank being instructed to act on the transfer.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.009-cdttrftxinf-instdagt-fininstnid",
                                    element: "FinInstnId",
                                    definition: "The financial institution identification block for the instructed agent.",
                                    usageNote: "It holds the bank identifier, usually a BIC.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.009-cdttrftxinf-instdagt-fininstnid-bicfi",
                                            element: "BICFI",
                                            definition: "The Business Identifier Code of the financial institution.",
                                            exampleValue: "FCTNDEFF",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.009-cdttrftxinf-dbtr",
                            element: "Dbtr",
                            definition: "The debtor: the financial institution sending the funds, identified as an institution rather than by a customer name.",
                            usageNote: "This is what makes pacs.009 a bank-to-bank transfer: the debtor is a bank.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pacs.009-cdttrftxinf-dbtr-fininstnid",
                                    element: "FinInstnId",
                                    definition: "The financial institution identification block for the debtor institution.",
                                    usageNote: "It holds the bank identifier, usually a BIC.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.009-cdttrftxinf-dbtr-fininstnid-bicfi",
                                            element: "BICFI",
                                            definition: "The Business Identifier Code of the financial institution.",
                                            exampleValue: "FCTNGB2L",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.009-cdttrftxinf-dbtracc",
                            element: "DbtrAcct",
                            definition: "The debtor account: the account the funds are paid from.",
                            usageNote: "The account must belong to the debtor institution.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.009-cdttrftxinf-dbtracc-id",
                                    element: "Id",
                                    definition: "The account identification block. It holds one form of account identifier.",
                                    usageNote: "One identifier form per account block. The base schema offers a choice of forms.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.009-cdttrftxinf-dbtracc-id-iban",
                                            element: "IBAN",
                                            definition: "The International Bank Account Number for the account.",
                                            exampleValue: "GB00FICT00000000000000",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.009-cdttrftxinf-cdtr",
                            element: "Cdtr",
                            definition: "The creditor: the financial institution receiving the funds, identified as an institution rather than by a customer name.",
                            usageNote: "Name the institution being paid.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pacs.009-cdttrftxinf-cdtr-fininstnid",
                                    element: "FinInstnId",
                                    definition: "The financial institution identification block for the creditor institution.",
                                    usageNote: "It holds the bank identifier, usually a BIC.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.009-cdttrftxinf-cdtr-fininstnid-bicfi",
                                            element: "BICFI",
                                            definition: "The Business Identifier Code of the financial institution.",
                                            exampleValue: "FCTNDEFF",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.009-cdttrftxinf-cdtracct",
                            element: "CdtrAcct",
                            definition: "The creditor account: the account the funds are paid to.",
                            usageNote: "The account must belong to the creditor institution.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.009-cdttrftxinf-cdtracct-id",
                                    element: "Id",
                                    definition: "The account identification block. It holds one form of account identifier.",
                                    usageNote: "One identifier form per account block. The base schema offers a choice of forms.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.009-cdttrftxinf-cdtracct-id-iban",
                                            element: "IBAN",
                                            definition: "The International Bank Account Number for the account.",
                                            exampleValue: "DE00000000000000000000",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            relationships: [
                ISO20022Relationship(
                    relatedMessageID: "pacs.008",
                    kind: "Companion to",
                    note: "The customer payment equivalent: same settlement structure, but for a customer payment."
                ),
                ISO20022Relationship(
                    relatedMessageID: "pacs.002",
                    kind: "Answered by",
                    note: "The receiving bank reports whether it accepted or rejected the transfer."
                ),
                ISO20022Relationship(
                    relatedMessageID: "pacs.007",
                    kind: "Can trigger",
                    note: "The sending side can reverse the transfer, for example when it was sent twice."
                ),
            ]
        ),
        ISO20022Message(
            id: "pacs.002",
            isoName: "FIToFIPaymentStatusReport",
            displayName: "FI to FI Payment Status Report",
            family: .pacs,
            purpose: "pacs.002 is the status report one financial institution sends to another about a payment message it received, most often a pacs.008 or pacs.009. It says whether the original payment was accepted or rejected and, when rejected, gives a reason. Every status entry points back to the original payment with its original references, so the sender can match the report to the payment it sent.",
            rootElement: "FIToFIPmtStsRpt",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <FIToFIPmtStsRpt>
                    <GrpHdr>
                      <MsgId>EXAMPLE-PACS002-001</MsgId>
                      <CreDtTm>2026-11-12T09:40:00Z</CreDtTm>
                      <InstgAgt>
                        <FinInstnId>
                          <BICFI>FCTNDEFF</BICFI>
                        </FinInstnId>
                      </InstgAgt>
                      <InstdAgt>
                        <FinInstnId>
                          <BICFI>FCTNGB2L</BICFI>
                        </FinInstnId>
                      </InstdAgt>
                    </GrpHdr>
                    <OrgnlGrpInfAndSts>
                      <OrgnlMsgId>EXAMPLE-PACS008-001</OrgnlMsgId>
                      <OrgnlMsgNmId>pacs.008.001.08</OrgnlMsgNmId>
                      <GrpSts>ACCP</GrpSts>
                    </OrgnlGrpInfAndSts>
                    <TxInfAndSts>
                      <OrgnlInstrId>EXAMPLE-INSTR-001</OrgnlInstrId>
                      <OrgnlEndToEndId>EXAMPLE-E2E-001</OrgnlEndToEndId>
                      <OrgnlUETR>123e4567-e89b-42d3-a456-426614174000</OrgnlUETR>
                      <TxSts>ACCP</TxSts>
                      <AccptncDtTm>2026-11-12T09:40:00Z</AccptncDtTm>
                    </TxInfAndSts>
                  </FIToFIPmtStsRpt>
                </Document>
                """,
            fields: [
                ISO20022Field(
                    id: "pacs.002-grphdr",
                    element: "GrpHdr",
                    definition: "The group header. It identifies this status report and names the banks sending and receiving it.",
                    usageNote: "Note the direction: the bank that received the original payment is the sender of this report.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pacs.002-grphdr-msgid",
                            element: "MsgId",
                            definition: "The unique reference the sender gives this status report.",
                            exampleValue: "EXAMPLE-PACS002-001",
                            usageNote: "Give every report a new reference, distinct from the original payment reference.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.002-grphdr-credttm",
                            element: "CreDtTm",
                            definition: "The date and time the sender created the report.",
                            exampleValue: "2026-11-12T09:40:00Z",
                            usageNote: "Use the creation time of the report.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.002-grphdr-instgagt",
                            element: "InstgAgt",
                            definition: "The instructing agent: the bank sending this status report.",
                            usageNote: "This is the bank that received and processed the original payment.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.002-grphdr-instgagt-fininstnid",
                                    element: "FinInstnId",
                                    definition: "The financial institution identification block for the instructing agent.",
                                    usageNote: "It holds the bank identifier, usually a BIC.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.002-grphdr-instgagt-fininstnid-bicfi",
                                            element: "BICFI",
                                            definition: "The Business Identifier Code of the financial institution.",
                                            exampleValue: "FCTNDEFF",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.002-grphdr-instdagt",
                            element: "InstdAgt",
                            definition: "The instructed agent: the bank receiving this status report.",
                            usageNote: "This is the bank that sent the original payment.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.002-grphdr-instdagt-fininstnid",
                                    element: "FinInstnId",
                                    definition: "The financial institution identification block for the instructed agent.",
                                    usageNote: "It holds the bank identifier, usually a BIC.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.002-grphdr-instdagt-fininstnid-bicfi",
                                            element: "BICFI",
                                            definition: "The Business Identifier Code of the financial institution.",
                                            exampleValue: "FCTNGB2L",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                    ]
                ),
                ISO20022Field(
                    id: "pacs.002-orgnlgrpinfandsts",
                    element: "OrgnlGrpInfAndSts",
                    definition: "Information about the original group of payments, with the status for the group as a whole. It points back to the original message.",
                    usageNote: "Read this first: it says which original message the report answers.",
                    requirement: .optional,
                    children: [
                        ISO20022Field(
                            id: "pacs.002-orgnlgrpinfandsts-orgnlmsgid",
                            element: "OrgnlMsgId",
                            definition: "The message reference of the original payment message, copied from its group header.",
                            exampleValue: "EXAMPLE-PACS008-001",
                            usageNote: "Match this against the MsgId of the original pacs.008 or pacs.009.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.002-orgnlgrpinfandsts-orgnlmsgnmid",
                            element: "OrgnlMsgNmId",
                            definition: "The full name of the original message, including its version.",
                            exampleValue: "pacs.008.001.08",
                            usageNote: "The version suffix is part of the name. It says exactly which message definition the original used.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.002-orgnlgrpinfandsts-orgnlcredttm",
                            element: "OrgnlCreDtTm",
                            definition: "The creation date and time of the original message, copied from its group header.",
                            exampleValue: "2026-11-12T09:32:00Z",
                            usageNote: "A further matching key when the same reference could appear more than once over time.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.002-orgnlgrpinfandsts-grpsts",
                            element: "GrpSts",
                            definition: "The status of the original group as a whole, as a code.",
                            exampleValue: "ACCP",
                            usageNote: "ACCP is the widely used code for accepted. This explorer does not reproduce code lists.",
                            requirement: .optional
                        ),
                    ]
                ),
                ISO20022Field(
                    id: "pacs.002-txinfandsts",
                    element: "TxInfAndSts",
                    definition: "Status for one original transaction, with the original references that identify it and the reason when it was rejected.",
                    usageNote: "One entry per transaction being reported on. The original references are what let the sender match the status to its own payment record.",
                    requirement: .optional,
                    children: [
                        ISO20022Field(
                            id: "pacs.002-txinfandsts-orgnlinstrid",
                            element: "OrgnlInstrId",
                            definition: "The instruction reference from the original transaction, copied from its payment identification block.",
                            exampleValue: "EXAMPLE-INSTR-001",
                            usageNote: "Quote back exactly what the original carried. Do not invent a new reference here.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.002-txinfandsts-orgnlendtoendid",
                            element: "OrgnlEndToEndId",
                            definition: "The end-to-end reference from the original transaction, copied from its payment identification block.",
                            exampleValue: "EXAMPLE-E2E-001",
                            usageNote: "This is the reference the originator and beneficiary both know, so it is the most useful matching key.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.002-txinfandsts-orgnluetr",
                            element: "OrgnlUETR",
                            definition: "The UETR from the original transaction, copied from its payment identification block.",
                            exampleValue: "123e4567-e89b-42d3-a456-426614174000",
                            usageNote: "Illustrative value in this sample, using the well known example UUID. The UETR lets every party track the same payment across messages.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.002-txinfandsts-txsts",
                            element: "TxSts",
                            definition: "The status of this single transaction, as a code.",
                            exampleValue: "ACCP",
                            usageNote: "ACCP is the widely used code for accepted. When a transaction is rejected, a reason block explains why. This explorer does not reproduce code lists.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.002-txinfandsts-accptncdttm",
                            element: "AccptncDtTm",
                            definition: "The date and time the original transaction was accepted or rejected.",
                            exampleValue: "2026-11-12T09:40:00Z",
                            usageNote: "Use the time the decision was made, not the time this report was created.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.002-txinfandsts-stsrsninf",
                            element: "StsRsnInf",
                            definition: "Status reason information: why a transaction has the status it has, used in particular for rejections.",
                            usageNote: "Read this block whenever a status is a rejection. It carries the reason code and any extra explanation.",
                            requirement: .optional
                        ),
                    ]
                ),
            ],
            relationships: [
                ISO20022Relationship(
                    relatedMessageID: "pacs.008",
                    kind: "Answers",
                    note: "Reports whether a customer credit transfer was accepted or rejected."
                ),
                ISO20022Relationship(
                    relatedMessageID: "pacs.009",
                    kind: "Answers",
                    note: "Reports whether a financial institution credit transfer was accepted or rejected."
                ),
                ISO20022Relationship(
                    relatedMessageID: "pain.002",
                    kind: "Companion to",
                    note: "The customer equivalent: a status report from a bank to its customer."
                ),
            ]
        ),
        ISO20022Message(
            id: "pacs.004",
            isoName: "PaymentReturn",
            displayName: "Payment Return",
            family: .pacs,
            purpose: "pacs.004 is the message a bank sends to return funds from a payment it received, for example when the beneficiary account does not exist, the account is closed, or the beneficiary bank cannot apply the payment. It points back to the original payment with the original references and gives a return reason, and it carries the returned settlement amount. A return is different from a reversal: the return comes from the receiving side, while a pacs.007 reversal comes from the side that sent the original payment.",
            rootElement: "PmtRtr",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <PmtRtr>
                    <GrpHdr>
                      <MsgId>EXAMPLE-PACS004-001</MsgId>
                      <CreDtTm>2026-11-12T11:00:00Z</CreDtTm>
                      <SttlmInf>
                        <SttlmMtd>INDA</SttlmMtd>
                      </SttlmInf>
                    </GrpHdr>
                    <TxInf>
                      <RtrId>EXAMPLE-RTR-001</RtrId>
                      <OrgnlGrpInf>
                        <OrgnlMsgId>EXAMPLE-PACS008-001</OrgnlMsgId>
                        <OrgnlMsgNmId>pacs.008.001.08</OrgnlMsgNmId>
                      </OrgnlGrpInf>
                      <OrgnlEndToEndId>EXAMPLE-E2E-001</OrgnlEndToEndId>
                      <OrgnlUETR>123e4567-e89b-42d3-a456-426614174000</OrgnlUETR>
                      <RtrdIntrBkSttlmAmt Ccy="EUR">12500.00</RtrdIntrBkSttlmAmt>
                      <RtrRsnInf>
                        <Rsn>
                          <Cd>AC03</Cd>
                        </Rsn>
                        <AddtlInf>Account number does not match a valid account.</AddtlInf>
                      </RtrRsnInf>
                    </TxInf>
                  </PmtRtr>
                </Document>
                """,
            fields: [
                ISO20022Field(
                    id: "pacs.004-grphdr",
                    element: "GrpHdr",
                    definition: "The group header. It identifies the whole return message and carries the settlement information shared by its transactions.",
                    usageNote: "One group header per message.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pacs.004-grphdr-msgid",
                            element: "MsgId",
                            definition: "The unique reference the sender gives this return message.",
                            exampleValue: "EXAMPLE-PACS004-001",
                            usageNote: "Give every return a new reference, distinct from the original payment reference.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.004-grphdr-credttm",
                            element: "CreDtTm",
                            definition: "The date and time the sender created the message.",
                            exampleValue: "2026-11-12T11:00:00Z",
                            usageNote: "Use the creation time of the return message.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.004-grphdr-sttlminf",
                            element: "SttlmInf",
                            definition: "Settlement information: how the returned amount is settled between the banks.",
                            usageNote: "It describes the settlement method for the return.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.004-grphdr-sttlminf-sttlmmtd",
                                    element: "SttlmMtd",
                                    definition: "The settlement method, as a code.",
                                    exampleValue: "INDA",
                                    usageNote: "INDA is the widely used code for settlement through the instructed agent. This explorer does not reproduce code lists.",
                                    requirement: .mandatory
                                ),
                            ]
                        ),
                    ]
                ),
                ISO20022Field(
                    id: "pacs.004-txinf",
                    element: "TxInf",
                    definition: "One returned transaction: the original payment being returned, the amount being returned, and the reason for the return.",
                    usageNote: "One block per returned payment. A message can return several payments.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pacs.004-txinf-rtrid",
                            element: "RtrId",
                            definition: "The return reference given by the returning bank for this returned transaction.",
                            exampleValue: "EXAMPLE-RTR-001",
                            usageNote: "Use a reference the returning bank can quote when asked about this return.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.004-txinf-orgnlgrpinf",
                            element: "OrgnlGrpInf",
                            definition: "Information about the original message group that carried the payment being returned.",
                            usageNote: "It points the return back to the exact original message.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.004-txinf-orgnlgrpinf-orgnlmsgid",
                                    element: "OrgnlMsgId",
                                    definition: "The message reference of the original payment message, copied from its group header.",
                                    exampleValue: "EXAMPLE-PACS008-001",
                                    usageNote: "Match this against the MsgId of the original pacs.008.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "pacs.004-txinf-orgnlgrpinf-orgnlmsgnmid",
                                    element: "OrgnlMsgNmId",
                                    definition: "The full name of the original message, including its version.",
                                    exampleValue: "pacs.008.001.08",
                                    usageNote: "The version suffix is part of the name.",
                                    requirement: .mandatory
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.004-txinf-orgnlinstrid",
                            element: "OrgnlInstrId",
                            definition: "The instruction reference from the original transaction, copied from its payment identification block.",
                            exampleValue: "EXAMPLE-INSTR-001",
                            usageNote: "Quote back exactly what the original carried.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.004-txinf-orgnlendtoendid",
                            element: "OrgnlEndToEndId",
                            definition: "The end-to-end reference from the original transaction, copied from its payment identification block.",
                            exampleValue: "EXAMPLE-E2E-001",
                            usageNote: "This is the reference the originator and beneficiary both know, so it is the most useful matching key.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.004-txinf-orgnluetr",
                            element: "OrgnlUETR",
                            definition: "The UETR from the original transaction, copied from its payment identification block.",
                            exampleValue: "123e4567-e89b-42d3-a456-426614174000",
                            usageNote: "Illustrative value in this sample, using the well known example UUID.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.004-txinf-rtrdintrkbksttlmamt",
                            element: "RtrdIntrBkSttlmAmt",
                            definition: "The returned interbank settlement amount: the amount being returned between the banks, with the currency carried as an attribute.",
                            exampleValue: "12500.00 EUR",
                            usageNote: "Fictional amount in this sample. A return can be for the full amount or, where the scheme allows, part of it.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.004-txinf-rtrrsninf",
                            element: "RtrRsnInf",
                            definition: "Return reason information: why the payment is being returned, with a reason code and any extra explanation.",
                            usageNote: "Always read the reason before acting on a return. It decides whether the payment can be sent again with corrected details.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pacs.004-txinf-rtrrsninf-rsn",
                                    element: "Rsn",
                                    definition: "The return reason block. It holds the reason code.",
                                    usageNote: "The code names the reason in a form every bank can process the same way.",
                                    requirement: .optional,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.004-txinf-rtrrsninf-rsn-cd",
                                            element: "Cd",
                                            definition: "The return reason code.",
                                            exampleValue: "AC03",
                                            usageNote: "AC03 is the widely used code for an invalid creditor account number. This explorer does not reproduce code lists.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                                ISO20022Field(
                                    id: "pacs.004-txinf-rtrrsninf-addtlinf",
                                    element: "AddtlInf",
                                    definition: "Additional information about the return, in free text.",
                                    exampleValue: "Account number does not match a valid account.",
                                    usageNote: "Use it to add detail the code alone cannot carry.",
                                    requirement: .optional
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            relationships: [
                ISO20022Relationship(
                    relatedMessageID: "pacs.008",
                    kind: "Returns",
                    note: "Returns the funds from a customer credit transfer that cannot be applied."
                ),
                ISO20022Relationship(
                    relatedMessageID: "pacs.007",
                    kind: "Companion to",
                    note: "A reversal is sent by the original sender instead of the receiving side."
                ),
            ]
        ),
        ISO20022Message(
            id: "pacs.007",
            isoName: "FIToFIPaymentReversal",
            displayName: "FI to FI Payment Reversal",
            family: .pacs,
            purpose: "pacs.007 is the message a financial institution sends to reverse a payment it previously sent, for example when the same payment was sent twice by mistake or the original instruction should not have been sent. It points back to the original payment with the original references, states the reversed settlement amount and gives a reversal reason. Unlike a pacs.004 return, which comes from the receiving side, a reversal is started by the side that sent the original payment.",
            rootElement: "FIToFIPmtRvsl",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <FIToFIPmtRvsl>
                    <GrpHdr>
                      <MsgId>EXAMPLE-PACS007-001</MsgId>
                      <CreDtTm>2026-11-12T11:30:00Z</CreDtTm>
                      <SttlmInf>
                        <SttlmMtd>INDA</SttlmMtd>
                      </SttlmInf>
                    </GrpHdr>
                    <TxInf>
                      <RvslId>EXAMPLE-RVSL-001</RvslId>
                      <OrgnlGrpInf>
                        <OrgnlMsgId>EXAMPLE-PACS008-001</OrgnlMsgId>
                        <OrgnlMsgNmId>pacs.008.001.08</OrgnlMsgNmId>
                      </OrgnlGrpInf>
                      <OrgnlEndToEndId>EXAMPLE-E2E-001</OrgnlEndToEndId>
                      <OrgnlUETR>123e4567-e89b-42d3-a456-426614174000</OrgnlUETR>
                      <RvslIntrBkSttlmAmt Ccy="EUR">12500.00</RvslIntrBkSttlmAmt>
                      <RvslRsnInf>
                        <Rsn>
                          <Cd>DUPL</Cd>
                        </Rsn>
                        <AddtlInf>Payment was sent twice by mistake.</AddtlInf>
                      </RvslRsnInf>
                    </TxInf>
                  </FIToFIPmtRvsl>
                </Document>
                """,
            fields: [
                ISO20022Field(
                    id: "pacs.007-grphdr",
                    element: "GrpHdr",
                    definition: "The group header. It identifies the whole reversal message and carries the settlement information shared by its transactions.",
                    usageNote: "One group header per message.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pacs.007-grphdr-msgid",
                            element: "MsgId",
                            definition: "The unique reference the sender gives this reversal message.",
                            exampleValue: "EXAMPLE-PACS007-001",
                            usageNote: "Give every reversal a new reference, distinct from the original payment reference.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.007-grphdr-credttm",
                            element: "CreDtTm",
                            definition: "The date and time the sender created the message.",
                            exampleValue: "2026-11-12T11:30:00Z",
                            usageNote: "Use the creation time of the reversal message.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.007-grphdr-sttlminf",
                            element: "SttlmInf",
                            definition: "Settlement information: how the reversed amount is settled between the banks.",
                            usageNote: "It describes the settlement method for the reversal.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.007-grphdr-sttlminf-sttlmmtd",
                                    element: "SttlmMtd",
                                    definition: "The settlement method, as a code.",
                                    exampleValue: "INDA",
                                    usageNote: "INDA is the widely used code for settlement through the instructed agent. This explorer does not reproduce code lists.",
                                    requirement: .mandatory
                                ),
                            ]
                        ),
                    ]
                ),
                ISO20022Field(
                    id: "pacs.007-txinf",
                    element: "TxInf",
                    definition: "One reversed transaction: the original payment being reversed, the amount being reversed, and the reason for the reversal.",
                    usageNote: "One block per reversed payment. A message can reverse several payments.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "pacs.007-txinf-rvslid",
                            element: "RvslId",
                            definition: "The reversal reference given by the reversing bank for this reversed transaction.",
                            exampleValue: "EXAMPLE-RVSL-001",
                            usageNote: "Use a reference the reversing bank can quote when asked about this reversal.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.007-txinf-orgnlgrpinf",
                            element: "OrgnlGrpInf",
                            definition: "Information about the original message group that carried the payment being reversed.",
                            usageNote: "It points the reversal back to the exact original message.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "pacs.007-txinf-orgnlgrpinf-orgnlmsgid",
                                    element: "OrgnlMsgId",
                                    definition: "The message reference of the original payment message, copied from its group header.",
                                    exampleValue: "EXAMPLE-PACS008-001",
                                    usageNote: "Match this against the MsgId of the original pacs.008.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "pacs.007-txinf-orgnlgrpinf-orgnlmsgnmid",
                                    element: "OrgnlMsgNmId",
                                    definition: "The full name of the original message, including its version.",
                                    exampleValue: "pacs.008.001.08",
                                    usageNote: "The version suffix is part of the name.",
                                    requirement: .mandatory
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "pacs.007-txinf-orgnlinstrid",
                            element: "OrgnlInstrId",
                            definition: "The instruction reference from the original transaction, copied from its payment identification block.",
                            exampleValue: "EXAMPLE-INSTR-001",
                            usageNote: "Quote back exactly what the original carried.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.007-txinf-orgnlendtoendid",
                            element: "OrgnlEndToEndId",
                            definition: "The end-to-end reference from the original transaction, copied from its payment identification block.",
                            exampleValue: "EXAMPLE-E2E-001",
                            usageNote: "This is the reference the originator and beneficiary both know, so it is the most useful matching key.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.007-txinf-orgnluetr",
                            element: "OrgnlUETR",
                            definition: "The UETR from the original transaction, copied from its payment identification block.",
                            exampleValue: "123e4567-e89b-42d3-a456-426614174000",
                            usageNote: "Illustrative value in this sample, using the well known example UUID.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "pacs.007-txinf-rvslintrkbksttlmamt",
                            element: "RvslIntrBkSttlmAmt",
                            definition: "The reversed interbank settlement amount: the amount being reversed between the banks, with the currency carried as an attribute.",
                            exampleValue: "12500.00 EUR",
                            usageNote: "Fictional amount in this sample.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "pacs.007-txinf-rvslrsninf",
                            element: "RvslRsnInf",
                            definition: "Reversal reason information: why the payment is being reversed, with a reason code and any extra explanation.",
                            usageNote: "Always read the reason before acting on a reversal. It says what went wrong with the original payment.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "pacs.007-txinf-rvslrsninf-rsn",
                                    element: "Rsn",
                                    definition: "The reversal reason block. It holds the reason code.",
                                    usageNote: "The code names the reason in a form every bank can process the same way.",
                                    requirement: .optional,
                                    children: [
                                        ISO20022Field(
                                            id: "pacs.007-txinf-rvslrsninf-rsn-cd",
                                            element: "Cd",
                                            definition: "The reversal reason code.",
                                            exampleValue: "DUPL",
                                            usageNote: "DUPL is the widely used code for a duplicate payment. This explorer does not reproduce code lists.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                                ISO20022Field(
                                    id: "pacs.007-txinf-rvslrsninf-addtlinf",
                                    element: "AddtlInf",
                                    definition: "Additional information about the reversal, in free text.",
                                    exampleValue: "Payment was sent twice by mistake.",
                                    usageNote: "Use it to add detail the code alone cannot carry.",
                                    requirement: .optional
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            relationships: [
                ISO20022Relationship(
                    relatedMessageID: "pacs.008",
                    kind: "Reverses",
                    note: "Undoes a customer credit transfer the sender previously sent."
                ),
                ISO20022Relationship(
                    relatedMessageID: "pacs.009",
                    kind: "Reverses",
                    note: "Undoes a financial institution credit transfer the sender previously sent."
                ),
                ISO20022Relationship(
                    relatedMessageID: "pacs.004",
                    kind: "Companion to",
                    note: "A return comes from the receiving side instead of the original sender."
                ),
            ]
        ),
        ISO20022Message(
            id: "camt.052",
            isoName: "BankToCustomerAccountReport",
            displayName: "Bank to Customer Account Report",
            family: .camt,
            purpose: "camt.052 is the intraday account report a bank sends to its customer during the business day. It shows the entries booked so far and interim balances, so the customer can see incoming and outgoing payments before the day closes. Unlike the camt.053 statement, which is the record for a completed period, a camt.052 report is a snapshot in time and later reports on the same day can add more entries.",
            rootElement: "BkToCstmrAcctRpt",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <BkToCstmrAcctRpt>
                    <GrpHdr>
                      <MsgId>EXAMPLE-CAMT052-001</MsgId>
                      <CreDtTm>2026-11-12T12:00:00Z</CreDtTm>
                    </GrpHdr>
                    <Rpt>
                      <Id>EXAMPLE-RPT-001</Id>
                      <CreDtTm>2026-11-12T12:00:00Z</CreDtTm>
                      <Acct>
                        <Id>
                          <IBAN>GB00FICT00000000000000</IBAN>
                        </Id>
                      </Acct>
                      <Bal>
                        <Tp>
                          <CdOrPrtry>
                            <Cd>CLBD</Cd>
                          </CdOrPrtry>
                        </Tp>
                        <Amt Ccy="EUR">862500.00</Amt>
                        <CdtDbtInd>CRDT</CdtDbtInd>
                      </Bal>
                      <Ntry>
                        <Amt Ccy="EUR">12500.00</Amt>
                        <CdtDbtInd>DBIT</CdtDbtInd>
                        <Sts>BOOK</Sts>
                        <BookgDt>
                          <Dt>2026-11-12</Dt>
                        </BookgDt>
                        <ValDt>
                          <Dt>2026-11-13</Dt>
                        </ValDt>
                      </Ntry>
                    </Rpt>
                  </BkToCstmrAcctRpt>
                </Document>
                """,
            fields: [
                ISO20022Field(
                    id: "camt.052-grphdr",
                    element: "GrpHdr",
                    definition: "The group header. It identifies the whole report.",
                    usageNote: "One group header per report.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "camt.052-grphdr-msgid",
                            element: "MsgId",
                            definition: "The unique reference the sender gives this report.",
                            exampleValue: "EXAMPLE-CAMT052-001",
                            usageNote: "Give every report a new reference.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "camt.052-grphdr-credttm",
                            element: "CreDtTm",
                            definition: "The date and time the sender created the report.",
                            exampleValue: "2026-11-12T12:00:00Z",
                            usageNote: "Use the creation time of the report. For an intraday report this is the snapshot time.",
                            requirement: .mandatory
                        ),
                    ]
                ),
                ISO20022Field(
                    id: "camt.052-rpt",
                    element: "Rpt",
                    definition: "One account report: the account, its balances and the entries booked so far in the reporting period.",
                    usageNote: "One report block per account. A message can report on several accounts.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "camt.052-rpt-id",
                            element: "Id",
                            definition: "The unique reference for this report block.",
                            exampleValue: "EXAMPLE-RPT-001",
                            usageNote: "Use it when asking the bank about this specific report.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "camt.052-rpt-credttm",
                            element: "CreDtTm",
                            definition: "The date and time this report block was created.",
                            exampleValue: "2026-11-12T12:00:00Z",
                            usageNote: "This is the time the snapshot was taken.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "camt.052-rpt-acct",
                            element: "Acct",
                            definition: "The account this report covers.",
                            usageNote: "Every balance and entry in the block belongs to this account.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "camt.052-rpt-acct-id",
                                    element: "Id",
                                    definition: "The account identification block. It holds one form of account identifier.",
                                    usageNote: "One identifier form per account block. The base schema offers a choice of forms.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "camt.052-rpt-acct-id-iban",
                                            element: "IBAN",
                                            definition: "The International Bank Account Number for the account.",
                                            exampleValue: "GB00FICT00000000000000",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "camt.052-rpt-bal",
                            element: "Bal",
                            definition: "One balance for the account: its type, its amount and whether it is a credit or debit balance.",
                            usageNote: "A report can carry several balances, for example an opening balance and a closing balance. Read the type before reading the amount.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "camt.052-rpt-bal-tp",
                                    element: "Tp",
                                    definition: "The balance type block. It names which balance this is.",
                                    usageNote: "The type decides how to read the amount. Never assume a balance is the closing balance.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "camt.052-rpt-bal-tp-cdorprtry",
                                            element: "CdOrPrtry",
                                            definition: "The balance type as a code, or as a proprietary type agreed with the bank.",
                                            usageNote: "In most reports this holds a standard code.",
                                            requirement: .mandatory,
                                            children: [
                                                ISO20022Field(
                                                    id: "camt.052-rpt-bal-tp-cdorprtry-cd",
                                                    element: "Cd",
                                                    definition: "The balance type code.",
                                                    exampleValue: "CLBD",
                                                    usageNote: "CLBD is the widely used code for the closing balance, and OPBD for the opening balance. This explorer does not reproduce code lists.",
                                                    requirement: .optional
                                                ),
                                            ]
                                        ),
                                    ]
                                ),
                                ISO20022Field(
                                    id: "camt.052-rpt-bal-amt",
                                    element: "Amt",
                                    definition: "The balance amount, with the currency carried as an attribute.",
                                    exampleValue: "862500.00 EUR",
                                    usageNote: "Fictional amount in this sample. Read it together with the credit or debit indicator.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "camt.052-rpt-bal-cdtdbtind",
                                    element: "CdtDbtInd",
                                    definition: "Whether the balance is a credit balance or a debit balance.",
                                    exampleValue: "CRDT",
                                    usageNote: "CRDT means a credit balance and DBIT means a debit balance. The indicator is part of the balance, never optional reading.",
                                    requirement: .mandatory
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "camt.052-rpt-ntry",
                            element: "Ntry",
                            definition: "One entry on the account: a single booked or expected movement of money, with its amount, direction, status and dates.",
                            usageNote: "One block per entry. Entries appear in the order the bank reports them.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "camt.052-rpt-ntry-amt",
                                    element: "Amt",
                                    definition: "The entry amount, with the currency carried as an attribute.",
                                    exampleValue: "12500.00 EUR",
                                    usageNote: "Fictional amount in this sample. Read it together with the credit or debit indicator.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "camt.052-rpt-ntry-cdtdbtind",
                                    element: "CdtDbtInd",
                                    definition: "Whether the entry is a credit to the account or a debit from it.",
                                    exampleValue: "DBIT",
                                    usageNote: "DBIT means money left the account and CRDT means money arrived. Never read an amount without it.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "camt.052-rpt-ntry-sts",
                                    element: "Sts",
                                    definition: "The status of the entry, as a code.",
                                    exampleValue: "BOOK",
                                    usageNote: "BOOK is the widely used code for a booked entry. This explorer does not reproduce code lists.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "camt.052-rpt-ntry-bookgdt",
                                    element: "BookgDt",
                                    definition: "The booking date: when the entry was booked to the account.",
                                    exampleValue: "2026-11-12",
                                    usageNote: "The booking date can differ from the value date. Both matter for reconciliation.",
                                    requirement: .optional
                                ),
                                ISO20022Field(
                                    id: "camt.052-rpt-ntry-valdt",
                                    element: "ValDt",
                                    definition: "The value date: when the funds count for interest and availability.",
                                    exampleValue: "2026-11-13",
                                    usageNote: "Compare the value date with the booking date when an entry looks early or late.",
                                    requirement: .optional
                                ),
                                ISO20022Field(
                                    id: "camt.052-rpt-ntry-bktxcd",
                                    element: "BkTxCd",
                                    definition: "The bank transaction code: a code naming the type of entry, for example a credit transfer or a charge.",
                                    usageNote: "Use it to classify entries in reconciliation. The code list lives in the ISO 20022 data dictionary, not in this explorer.",
                                    requirement: .mandatory
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            relationships: [
                ISO20022Relationship(
                    relatedMessageID: "camt.053",
                    kind: "Companion to",
                    note: "The end-of-period statement is the completed record; this report is the intraday snapshot."
                ),
                ISO20022Relationship(
                    relatedMessageID: "camt.054",
                    kind: "Companion to",
                    note: "Single-entry notifications arrive per entry instead of in a report."
                ),
            ]
        ),
        ISO20022Message(
            id: "camt.053",
            isoName: "BankToCustomerStatement",
            displayName: "Bank to Customer Statement",
            family: .camt,
            purpose: "camt.053 is the bank statement a bank sends to its customer for a completed period, usually a business day. It lists the booked entries on the account with opening and closing balances, and it is the record the customer reconciles against. Statements carry a sequence number, so a missing statement is visible as a gap in the sequence. Intraday positions during the day come from camt.052 reports instead.",
            rootElement: "BkToCstmrStmt",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <BkToCstmrStmt>
                    <GrpHdr>
                      <MsgId>EXAMPLE-CAMT053-001</MsgId>
                      <CreDtTm>2026-11-12T18:00:00Z</CreDtTm>
                    </GrpHdr>
                    <Stmt>
                      <Id>EXAMPLE-STMT-001</Id>
                      <ElctrncSeqNb>42</ElctrncSeqNb>
                      <CreDtTm>2026-11-12T18:00:00Z</CreDtTm>
                      <Acct>
                        <Id>
                          <IBAN>GB00FICT00000000000000</IBAN>
                        </Id>
                      </Acct>
                      <Bal>
                        <Tp>
                          <CdOrPrtry>
                            <Cd>OPBD</Cd>
                          </CdOrPrtry>
                        </Tp>
                        <Amt Ccy="EUR">875000.00</Amt>
                        <CdtDbtInd>CRDT</CdtDbtInd>
                      </Bal>
                      <Bal>
                        <Tp>
                          <CdOrPrtry>
                            <Cd>CLBD</Cd>
                          </CdOrPrtry>
                        </Tp>
                        <Amt Ccy="EUR">862500.00</Amt>
                        <CdtDbtInd>CRDT</CdtDbtInd>
                      </Bal>
                      <Ntry>
                        <Amt Ccy="EUR">12500.00</Amt>
                        <CdtDbtInd>DBIT</CdtDbtInd>
                        <Sts>BOOK</Sts>
                        <BookgDt>
                          <Dt>2026-11-12</Dt>
                        </BookgDt>
                        <ValDt>
                          <Dt>2026-11-13</Dt>
                        </ValDt>
                      </Ntry>
                    </Stmt>
                  </BkToCstmrStmt>
                </Document>
                """,
            fields: [
                ISO20022Field(
                    id: "camt.053-grphdr",
                    element: "GrpHdr",
                    definition: "The group header. It identifies the whole statement message.",
                    usageNote: "One group header per message.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "camt.053-grphdr-msgid",
                            element: "MsgId",
                            definition: "The unique reference the sender gives this statement message.",
                            exampleValue: "EXAMPLE-CAMT053-001",
                            usageNote: "Give every statement message a new reference.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "camt.053-grphdr-credttm",
                            element: "CreDtTm",
                            definition: "The date and time the sender created the message.",
                            exampleValue: "2026-11-12T18:00:00Z",
                            usageNote: "Use the creation time of the statement message.",
                            requirement: .mandatory
                        ),
                    ]
                ),
                ISO20022Field(
                    id: "camt.053-stmt",
                    element: "Stmt",
                    definition: "One statement: the account, its balances and the booked entries for the statement period.",
                    usageNote: "One statement block per account. A message can carry statements for several accounts.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "camt.053-stmt-id",
                            element: "Id",
                            definition: "The unique reference for this statement block.",
                            exampleValue: "EXAMPLE-STMT-001",
                            usageNote: "Use it when asking the bank about this specific statement.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "camt.053-stmt-elctrncseqnb",
                            element: "ElctrncSeqNb",
                            definition: "The electronic sequence number of the statement for this account.",
                            exampleValue: "42",
                            usageNote: "Fictional number in this sample. Check the sequence: a gap means a statement is missing.",
                            requirement: .optional
                        ),
                        ISO20022Field(
                            id: "camt.053-stmt-credttm",
                            element: "CreDtTm",
                            definition: "The date and time this statement block was created.",
                            exampleValue: "2026-11-12T18:00:00Z",
                            usageNote: "Use the creation time of the statement.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "camt.053-stmt-acct",
                            element: "Acct",
                            definition: "The account this statement covers.",
                            usageNote: "Every balance and entry in the block belongs to this account.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "camt.053-stmt-acct-id",
                                    element: "Id",
                                    definition: "The account identification block. It holds one form of account identifier.",
                                    usageNote: "One identifier form per account block. The base schema offers a choice of forms.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "camt.053-stmt-acct-id-iban",
                                            element: "IBAN",
                                            definition: "The International Bank Account Number for the account.",
                                            exampleValue: "GB00FICT00000000000000",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "camt.053-stmt-bal",
                            element: "Bal",
                            definition: "One balance for the account: its type, its amount and whether it is a credit or debit balance. A statement normally carries an opening balance and a closing balance.",
                            usageNote: "Reconcile from the opening balance, through the entries, to the closing balance. Read the type before reading any amount.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "camt.053-stmt-bal-tp",
                                    element: "Tp",
                                    definition: "The balance type block. It names which balance this is.",
                                    usageNote: "The type decides how to read the amount. Never assume a balance is the closing balance.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "camt.053-stmt-bal-tp-cdorprtry",
                                            element: "CdOrPrtry",
                                            definition: "The balance type as a code, or as a proprietary type agreed with the bank.",
                                            usageNote: "In most statements this holds a standard code.",
                                            requirement: .mandatory,
                                            children: [
                                                ISO20022Field(
                                                    id: "camt.053-stmt-bal-tp-cdorprtry-cd",
                                                    element: "Cd",
                                                    definition: "The balance type code.",
                                                    exampleValue: "OPBD",
                                                    usageNote: "OPBD is the widely used code for the opening balance, and CLBD for the closing balance. This explorer does not reproduce code lists.",
                                                    requirement: .optional
                                                ),
                                            ]
                                        ),
                                    ]
                                ),
                                ISO20022Field(
                                    id: "camt.053-stmt-bal-amt",
                                    element: "Amt",
                                    definition: "The balance amount, with the currency carried as an attribute.",
                                    exampleValue: "875000.00 EUR",
                                    usageNote: "Fictional amount in this sample. Read it together with the credit or debit indicator.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "camt.053-stmt-bal-cdtdbtind",
                                    element: "CdtDbtInd",
                                    definition: "Whether the balance is a credit balance or a debit balance.",
                                    exampleValue: "CRDT",
                                    usageNote: "CRDT means a credit balance and DBIT means a debit balance. The indicator is part of the balance, never optional reading.",
                                    requirement: .mandatory
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "camt.053-stmt-ntry",
                            element: "Ntry",
                            definition: "One entry on the account: a single booked movement of money, with its amount, direction, status and dates.",
                            usageNote: "One block per entry. The entries plus the opening balance must arrive at the closing balance.",
                            requirement: .optional,
                            children: [
                                ISO20022Field(
                                    id: "camt.053-stmt-ntry-amt",
                                    element: "Amt",
                                    definition: "The entry amount, with the currency carried as an attribute.",
                                    exampleValue: "12500.00 EUR",
                                    usageNote: "Fictional amount in this sample. Read it together with the credit or debit indicator.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "camt.053-stmt-ntry-cdtdbtind",
                                    element: "CdtDbtInd",
                                    definition: "Whether the entry is a credit to the account or a debit from it.",
                                    exampleValue: "DBIT",
                                    usageNote: "DBIT means money left the account and CRDT means money arrived. Never read an amount without it.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "camt.053-stmt-ntry-sts",
                                    element: "Sts",
                                    definition: "The status of the entry, as a code.",
                                    exampleValue: "BOOK",
                                    usageNote: "BOOK is the widely used code for a booked entry. This explorer does not reproduce code lists.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "camt.053-stmt-ntry-bookgdt",
                                    element: "BookgDt",
                                    definition: "The booking date: when the entry was booked to the account.",
                                    exampleValue: "2026-11-12",
                                    usageNote: "The booking date can differ from the value date. Both matter for reconciliation.",
                                    requirement: .optional
                                ),
                                ISO20022Field(
                                    id: "camt.053-stmt-ntry-valdt",
                                    element: "ValDt",
                                    definition: "The value date: when the funds count for interest and availability.",
                                    exampleValue: "2026-11-13",
                                    usageNote: "Compare the value date with the booking date when an entry looks early or late.",
                                    requirement: .optional
                                ),
                                ISO20022Field(
                                    id: "camt.053-stmt-ntry-bktxcd",
                                    element: "BkTxCd",
                                    definition: "The bank transaction code: a code naming the type of entry, for example a credit transfer or a charge.",
                                    usageNote: "Use it to classify entries in reconciliation. The code list lives in the ISO 20022 data dictionary, not in this explorer.",
                                    requirement: .mandatory
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            relationships: [
                ISO20022Relationship(
                    relatedMessageID: "camt.052",
                    kind: "Companion to",
                    note: "Intraday reports show positions during the day; this statement is the completed record."
                ),
                ISO20022Relationship(
                    relatedMessageID: "camt.054",
                    kind: "Companion to",
                    note: "Single-entry notifications arrive per entry instead of in a statement."
                ),
            ]
        ),
        ISO20022Message(
            id: "camt.054",
            isoName: "BankToCustomerDebitCreditNotification",
            displayName: "Bank to Customer Debit Credit Notification",
            family: .camt,
            purpose: "camt.054 is the notification a bank sends to its customer about individual debit or credit entries, often soon after each entry is booked. Unlike a camt.053 statement, which covers a whole period, a camt.054 notification carries just the entries being notified, with entry details that help the customer match each one to a payment. It is a notification about entries, not a statement and not a balance report.",
            rootElement: "BkToCstmrDbtCdtNtfctn",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <BkToCstmrDbtCdtNtfctn>
                    <GrpHdr>
                      <MsgId>EXAMPLE-CAMT054-001</MsgId>
                      <CreDtTm>2026-11-12T09:45:00Z</CreDtTm>
                    </GrpHdr>
                    <Ntfctn>
                      <Id>EXAMPLE-NTFCTN-001</Id>
                      <CreDtTm>2026-11-12T09:45:00Z</CreDtTm>
                      <Acct>
                        <Id>
                          <IBAN>GB00FICT00000000000000</IBAN>
                        </Id>
                      </Acct>
                      <Ntry>
                        <Amt Ccy="EUR">12500.00</Amt>
                        <CdtDbtInd>DBIT</CdtDbtInd>
                        <Sts>BOOK</Sts>
                        <BookgDt>
                          <Dt>2026-11-12</Dt>
                        </BookgDt>
                        <NtryDtls>
                          <TxDtls>
                            <RmtInf>
                              <Ustrd>Invoice EXAMPLE-INV-1001</Ustrd>
                            </RmtInf>
                          </TxDtls>
                        </NtryDtls>
                      </Ntry>
                    </Ntfctn>
                  </BkToCstmrDbtCdtNtfctn>
                </Document>
                """,
            fields: [
                ISO20022Field(
                    id: "camt.054-grphdr",
                    element: "GrpHdr",
                    definition: "The group header. It identifies the whole notification message.",
                    usageNote: "One group header per message.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "camt.054-grphdr-msgid",
                            element: "MsgId",
                            definition: "The unique reference the sender gives this notification message.",
                            exampleValue: "EXAMPLE-CAMT054-001",
                            usageNote: "Give every notification message a new reference.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "camt.054-grphdr-credttm",
                            element: "CreDtTm",
                            definition: "The date and time the sender created the message.",
                            exampleValue: "2026-11-12T09:45:00Z",
                            usageNote: "Use the creation time of the notification message.",
                            requirement: .mandatory
                        ),
                    ]
                ),
                ISO20022Field(
                    id: "camt.054-ntfctn",
                    element: "Ntfctn",
                    definition: "One notification: the account and the entries being notified.",
                    usageNote: "One notification block per account. A message can notify entries on several accounts.",
                    requirement: .mandatory,
                    children: [
                        ISO20022Field(
                            id: "camt.054-ntfctn-id",
                            element: "Id",
                            definition: "The unique reference for this notification block.",
                            exampleValue: "EXAMPLE-NTFCTN-001",
                            usageNote: "Use it when asking the bank about this specific notification.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "camt.054-ntfctn-credttm",
                            element: "CreDtTm",
                            definition: "The date and time this notification block was created.",
                            exampleValue: "2026-11-12T09:45:00Z",
                            usageNote: "Use the creation time of the notification.",
                            requirement: .mandatory
                        ),
                        ISO20022Field(
                            id: "camt.054-ntfctn-acct",
                            element: "Acct",
                            definition: "The account the notified entries belong to.",
                            usageNote: "Every entry in the block belongs to this account.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "camt.054-ntfctn-acct-id",
                                    element: "Id",
                                    definition: "The account identification block. It holds one form of account identifier.",
                                    usageNote: "One identifier form per account block. The base schema offers a choice of forms.",
                                    requirement: .mandatory,
                                    children: [
                                        ISO20022Field(
                                            id: "camt.054-ntfctn-acct-id-iban",
                                            element: "IBAN",
                                            definition: "The International Bank Account Number for the account.",
                                            exampleValue: "GB00FICT00000000000000",
                                            usageNote: "Fictional value in this sample.",
                                            requirement: .optional
                                        ),
                                    ]
                                ),
                            ]
                        ),
                        ISO20022Field(
                            id: "camt.054-ntfctn-ntry",
                            element: "Ntry",
                            definition: "One notified entry: a single movement of money, with its amount, direction, status and dates, plus details that help match it to a payment.",
                            usageNote: "One block per notified entry. The entry details are what make a notification useful for matching.",
                            requirement: .mandatory,
                            children: [
                                ISO20022Field(
                                    id: "camt.054-ntfctn-ntry-amt",
                                    element: "Amt",
                                    definition: "The entry amount, with the currency carried as an attribute.",
                                    exampleValue: "12500.00 EUR",
                                    usageNote: "Fictional amount in this sample. Read it together with the credit or debit indicator.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "camt.054-ntfctn-ntry-cdtdbtind",
                                    element: "CdtDbtInd",
                                    definition: "Whether the entry is a credit to the account or a debit from it.",
                                    exampleValue: "DBIT",
                                    usageNote: "DBIT means money left the account and CRDT means money arrived. Never read an amount without it.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "camt.054-ntfctn-ntry-sts",
                                    element: "Sts",
                                    definition: "The status of the entry, as a code.",
                                    exampleValue: "BOOK",
                                    usageNote: "BOOK is the widely used code for a booked entry. This explorer does not reproduce code lists.",
                                    requirement: .mandatory
                                ),
                                ISO20022Field(
                                    id: "camt.054-ntfctn-ntry-bookgdt",
                                    element: "BookgDt",
                                    definition: "The booking date: when the entry was booked to the account.",
                                    exampleValue: "2026-11-12",
                                    usageNote: "The booking date can differ from the value date.",
                                    requirement: .optional
                                ),
                                ISO20022Field(
                                    id: "camt.054-ntfctn-ntry-ntrydtls",
                                    element: "NtryDtls",
                                    definition: "Entry details: the breakdown of an entry into its underlying transactions.",
                                    usageNote: "Open this block to see what the entry is made of. One entry can group several transactions.",
                                    requirement: .optional,
                                    children: [
                                        ISO20022Field(
                                            id: "camt.054-ntfctn-ntry-ntrydtls-txdtls",
                                            element: "TxDtls",
                                            definition: "Transaction details for one underlying transaction within the entry.",
                                            usageNote: "This is where the payment references and remittance information live.",
                                            requirement: .optional,
                                            children: [
                                                ISO20022Field(
                                                    id: "camt.054-ntfctn-ntry-ntrydtls-txdtls-rmtinf",
                                                    element: "RmtInf",
                                                    definition: "Remittance information: what the payment is for, so the customer can match the entry to an invoice or account.",
                                                    usageNote: "Match on this text when the entry has no structured reference.",
                                                    requirement: .optional,
                                                    children: [
                                                        ISO20022Field(
                                                            id: "camt.054-ntfctn-ntry-ntrydtls-txdtls-rmtinf-ustrd",
                                                            element: "Ustrd",
                                                            definition: "Unstructured remittance information: free text describing the payment.",
                                                            exampleValue: "Invoice EXAMPLE-INV-1001",
                                                            usageNote: "Use plain text the customer can read.",
                                                            requirement: .optional
                                                        ),
                                                    ]
                                                ),
                                            ]
                                        ),
                                    ]
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            relationships: [
                ISO20022Relationship(
                    relatedMessageID: "camt.052",
                    kind: "Companion to",
                    note: "Intraday reports gather entries into a report; notifications arrive per entry."
                ),
                ISO20022Relationship(
                    relatedMessageID: "camt.053",
                    kind: "Companion to",
                    note: "The statement is the completed record for the period; notifications arrive as entries are booked."
                ),
            ]
        ),
    ]

    /// Find a message by code, case-insensitively. Nil when the code
    /// is not one of the ten covered messages.
    static func message(id: String) -> ISO20022Message? {
        let wanted = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        return messages.first { $0.id.lowercased() == wanted }
    }
}

// MARK: - Follow the payment journey

/// One value shared across the three journey messages. The same
/// fictional values appear in every journey sample, so the learner
/// can see what travels unchanged and what each message adds.
struct ISO20022SharedValue: Identifiable, Hashable {
    let label: String
    let value: String

    var id: String { label }
}

/// One step of the follow-the-payment journey: one message, its
/// part of the story, and its abbreviated sample using the shared
/// fictional values.
struct ISO20022JourneyStep: Identifiable, Hashable {
    /// The message code, for example "pain.001". This is the id.
    let id: String
    let messageID: String
    let stepTitle: String
    let narrative: String
    let sampleXML: String
}

/// The follow-the-payment journey: pain.001 to pacs.008 to pacs.002,
/// using the same fictional values throughout. All values are
/// illustrative and labelled as such in the view.
enum ISO20022Journey {
    static let sharedValues: [ISO20022SharedValue] = [
        ISO20022SharedValue(label: "Amount", value: "EUR 12500.00"),
        ISO20022SharedValue(label: "End-to-end reference", value: "EXAMPLE-E2E-001"),
        ISO20022SharedValue(label: "Instruction reference", value: "EXAMPLE-INSTR-001"),
        ISO20022SharedValue(label: "UETR (illustrative)", value: "123e4567-e89b-42d3-a456-426614174000"),
        ISO20022SharedValue(label: "Debtor (fictional)", value: "Example Buyer BV"),
        ISO20022SharedValue(label: "Creditor (fictional)", value: "Example Seller Ltd"),
    ]

    static let steps: [ISO20022JourneyStep] = [
        ISO20022JourneyStep(
            id: "pain.001",
            messageID: "pain.001",
            stepTitle: "The customer instructs its bank",
            narrative: "Example Buyer BV instructs its bank to pay Example Seller Ltd EUR 12500.00. The instruction carries the end-to-end reference EXAMPLE-E2E-001, which the buyer chose and which must travel with the payment unchanged. The bank will answer this instruction with a pain.002 status report.",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <CstmrCdtTrfInitn>
                    <GrpHdr>
                      <MsgId>EXAMPLE-PAIN001-001</MsgId>
                      <CreDtTm>2026-11-12T09:30:00Z</CreDtTm>
                      <InitgPty>
                        <Nm>Example Buyer BV</Nm>
                      </InitgPty>
                    </GrpHdr>
                    <PmtInf>
                      <PmtInfId>EXAMPLE-PMTINF-001</PmtInfId>
                      <PmtMtd>TRF</PmtMtd>
                      <Dbtr>
                        <Nm>Example Buyer BV</Nm>
                      </Dbtr>
                      <CdtTrfTxInf>
                        <PmtId>
                          <InstrId>EXAMPLE-INSTR-001</InstrId>
                          <EndToEndId>EXAMPLE-E2E-001</EndToEndId>
                        </PmtId>
                        <Amt>
                          <InstdAmt Ccy="EUR">12500.00</InstdAmt>
                        </Amt>
                        <Cdtr>
                          <Nm>Example Seller Ltd</Nm>
                        </Cdtr>
                        <RmtInf>
                          <Ustrd>Invoice EXAMPLE-INV-1001</Ustrd>
                        </RmtInf>
                      </CdtTrfTxInf>
                    </PmtInf>
                  </CstmrCdtTrfInitn>
                </Document>
                """
        ),
        ISO20022JourneyStep(
            id: "pacs.008",
            messageID: "pacs.008",
            stepTitle: "The banks move the payment",
            narrative: "The debtor bank turns the instruction into a bank-to-bank payment. The amount, the end-to-end reference and the instruction reference carry over unchanged, and the payment gains a UETR so every bank in the chain can track the same payment. The debtor and creditor details travel with the payment to the beneficiary bank.",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <FIToFICstmrCdtTrf>
                    <GrpHdr>
                      <MsgId>EXAMPLE-PACS008-001</MsgId>
                      <CreDtTm>2026-11-12T09:32:00Z</CreDtTm>
                    </GrpHdr>
                    <CdtTrfTxInf>
                      <PmtId>
                        <InstrId>EXAMPLE-INSTR-001</InstrId>
                        <EndToEndId>EXAMPLE-E2E-001</EndToEndId>
                        <UETR>123e4567-e89b-42d3-a456-426614174000</UETR>
                      </PmtId>
                      <IntrBkSttlmAmt Ccy="EUR">12500.00</IntrBkSttlmAmt>
                      <InstgAgt>
                        <FinInstnId>
                          <BICFI>FCTNGB2L</BICFI>
                        </FinInstnId>
                      </InstgAgt>
                      <InstdAgt>
                        <FinInstnId>
                          <BICFI>FCTNDEFF</BICFI>
                        </FinInstnId>
                      </InstdAgt>
                      <Dbtr>
                        <Nm>Example Buyer BV</Nm>
                      </Dbtr>
                      <Cdtr>
                        <Nm>Example Seller Ltd</Nm>
                      </Cdtr>
                      <RmtInf>
                        <Ustrd>Invoice EXAMPLE-INV-1001</Ustrd>
                      </RmtInf>
                    </CdtTrfTxInf>
                  </FIToFICstmrCdtTrf>
                </Document>
                """
        ),
        ISO20022JourneyStep(
            id: "pacs.002",
            messageID: "pacs.002",
            stepTitle: "The receiving bank reports back",
            narrative: "The creditor bank reports back on the payment it received. The status report carries no new payment: it points back to the pacs.008 with the same original references, including the original UETR, and says the payment was accepted. The sender matches the report to its payment using those original references.",
            sampleXML: """
                <Document>
                  <!-- Namespace declaration omitted for brevity. Abbreviated sample. Parts omitted. -->
                  <FIToFIPmtStsRpt>
                    <GrpHdr>
                      <MsgId>EXAMPLE-PACS002-001</MsgId>
                      <CreDtTm>2026-11-12T09:40:00Z</CreDtTm>
                    </GrpHdr>
                    <OrgnlGrpInfAndSts>
                      <OrgnlMsgId>EXAMPLE-PACS008-001</OrgnlMsgId>
                      <OrgnlMsgNmId>pacs.008.001.08</OrgnlMsgNmId>
                      <GrpSts>ACCP</GrpSts>
                    </OrgnlGrpInfAndSts>
                    <TxInfAndSts>
                      <OrgnlInstrId>EXAMPLE-INSTR-001</OrgnlInstrId>
                      <OrgnlEndToEndId>EXAMPLE-E2E-001</OrgnlEndToEndId>
                      <OrgnlUETR>123e4567-e89b-42d3-a456-426614174000</OrgnlUETR>
                      <TxSts>ACCP</TxSts>
                      <AccptncDtTm>2026-11-12T09:40:00Z</AccptncDtTm>
                    </TxInfAndSts>
                  </FIToFIPmtStsRpt>
                </Document>
                """
        ),
    ]
}

// MARK: - Mapping workbench

/// One row of the mapping workbench: one concept traced across
/// pain.001, pacs.008 and pacs.002. Paths follow the base schema
/// structures shown in this explorer. The mapping is illustrative:
/// scheme usage guides govern what is required in a live payment.
struct ISO20022MappingRow: Identifiable, Hashable {
    let concept: String
    let pain001: String
    let pacs008: String
    let pacs002: String
    let note: String

    var id: String { concept }
}

enum ISO20022MappingWorkbench {
    static let rows: [ISO20022MappingRow] = [
        ISO20022MappingRow(
            concept: "End-to-end reference",
            pain001: "CdtTrfTxInf / PmtId / EndToEndId",
            pacs008: "CdtTrfTxInf / PmtId / EndToEndId",
            pacs002: "TxInfAndSts / OrgnlEndToEndId",
            note: "The same value travels unchanged. pacs.002 prefixes it with Orgnl because it refers back to the original payment."
        ),
        ISO20022MappingRow(
            concept: "Instruction reference",
            pain001: "CdtTrfTxInf / PmtId / InstrId",
            pacs008: "CdtTrfTxInf / PmtId / InstrId",
            pacs002: "TxInfAndSts / OrgnlInstrId",
            note: "The reference the instructing party gave the instruction. The status report quotes it back as the original instruction reference."
        ),
        ISO20022MappingRow(
            concept: "Payment amount",
            pain001: "CdtTrfTxInf / Amt / InstdAmt",
            pacs008: "CdtTrfTxInf / IntrBkSttlmAmt",
            pacs002: "No new amount. The original amount can be restated inside OrgnlTxRef when that block is present.",
            note: "pain.001 states the amount as instructed. pacs.008 states the amount to settle between banks. A status report does not move money, so it carries no amount of its own."
        ),
        ISO20022MappingRow(
            concept: "Creditor name",
            pain001: "CdtTrfTxInf / Cdtr / Nm",
            pacs008: "CdtTrfTxInf / Cdtr / Nm",
            pacs002: "Not restated. pacs.002 points back to the original payment by reference.",
            note: "Party details travel with the payment instruction. The status report identifies the payment by its references, not by repeating the parties."
        ),
        ISO20022MappingRow(
            concept: "Tracking reference (UETR)",
            pain001: "No UETR element in the pain.001 structure shown here. The end-to-end reference is the link the originator controls.",
            pacs008: "CdtTrfTxInf / PmtId / UETR",
            pacs002: "TxInfAndSts / OrgnlUETR",
            note: "The UETR is the bank-to-bank tracking reference. It appears once the payment moves between banks, and status reports quote it back as the original UETR."
        ),
        ISO20022MappingRow(
            concept: "Dates",
            pain001: "PmtInf / ReqdExctnDt",
            pacs008: "CdtTrfTxInf / IntrBkSttlmDt",
            pacs002: "TxInfAndSts / AccptncDtTm",
            note: "The customer asks for an execution date. The bank-to-bank message carries a settlement date. The status report records when the original was accepted or rejected."
        ),
    ]
}
