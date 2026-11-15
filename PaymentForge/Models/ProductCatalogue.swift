// ProductCatalogue.swift
// PaymentForge iOS - the one authoritative product catalogue.
//
// This catalogue supersedes PaymentConfig for StoreManager and
// CheckoutView. PaymentConfig (in SupabaseConfig.swift) is frozen and
// was not edited: it still carries the stale Situations count of 500
// and must no longer be consulted by the store or the Purchases
// screen. FinalAssessment and LessonView were migrated to this
// catalogue. SearchView was migrated to this catalogue for its
// bundle lookup. CertificateView still reads PaymentConfig for
// one lookup; migrating it is a follow-up, not part of the
// catalogue migration.
// CourseProduct is the existing struct declared in SupabaseConfig.swift
// and is reused here, not redeclared.
//
// Prices: priceINR is reference data only, copied from PaymentConfig
// for record keeping. It is NEVER shown as a purchase price. The only
// price a buyer ever sees is the StoreKit product displayPrice, shown
// by StoreManager.priceText(for:) once the product has loaded. If the
// StoreKit product has not loaded, the price is shown as unavailable
// and purchase is disabled. App Store Connect (and the local
// PaymentForge.storekit file for DEBUG testing) is the source of
// truth for prices.

import Foundation

/// The one authoritative catalogue of the buyable course products.
///
/// The catalogue holds the 12 non-consumable, one-time products: the
/// Integrated Course, the 10 chapter bundles, and Payment Situations.
/// Product IDs follow com.paymentforge.app.<bundle-id> and must match
/// the App Store Connect products and PaymentForge.storekit exactly.
///
/// Included content per product (chapters from each product's
/// chapterIDs; lesson and situation totals from ContentManifest):
///   The Integrated Course: all chapters, all lessons, and all
///     Payment Situations.
///   Payment Foundations: 10 chapters, all lessons in those chapters.
///   ISO 20022 and SWIFT Messaging: 11 chapters, all lessons in
///     those chapters.
///   Global Payment Rails: 14 chapters, all lessons in those chapters.
///   Cross-Border and Correspondent Banking: 10 chapters, all lessons
///     in those chapters.
///   Clearing, Settlement and Liquidity: 7 chapters, all lessons in
///     those chapters.
///   Cards and Domestic Payments: 7 chapters, all lessons in those
///     chapters.
///   Compliance, Risk, Operations and Reconciliation: 13 chapters,
///     all lessons in those chapters.
///   Payment Architecture and APIs: 10 chapters, all lessons in those
///     chapters.
///   AI Product Owner and Product Manager for Payments: 13 chapters,
///     all lessons in those chapters.
///   Emerging Technologies and the Future: 5 chapters, all lessons in
///     those chapters.
///   Payment Situations: no chapters and no lessons; all situations.
/// Per-bundle lesson counts are not stored in this catalogue and are
/// never stated per bundle; only the Integrated Course states the
/// full lesson total, taken from ContentManifest.
///
/// Free samples: 6 free sample situations stay free without any
/// purchase. Their IDs are freeSampleSituationIDs below. The first
/// lesson of each chapter is also free (settled D77). The runtime
/// gate for the free samples lives in ContentService.freeSampleIDs
/// and SituationsView; the list here mirrors it for documentation
/// and must be kept in step with it.
///
/// Entitlement rules (enforced by StoreManager, stated here so the
/// offer and the enforcement cannot drift apart):
///   A chapter bundle unlocks only its own chapters.
///   The Integrated Course unlocks all chapter products and all
///     Payment Situations.
///   Payment Situations is also sold standalone: its own purchase,
///     or an active server entitlement for the signed-in user,
///     unlocks it without the full course.
///   Ownership means a verified StoreKit transaction on the device,
///     or an active server entitlement row. In Release builds no
///     local flag alone ever unlocks a product.
///   A chapter no bundle contains maps to no product.
///
/// Restore eligibility: every product is a non-consumable one-time
/// purchase, so every purchase is restorable with the same Apple ID
/// on any device (Restore Purchases in CheckoutView). When the buyer
/// is signed in, a verified purchase is also recorded on the server
/// through the record-purchase Edge Function, so the entitlement
/// follows the account to other devices. Refunds and revocations
/// remove the entitlement on the device and on the server.
enum ProductCatalogue {

    /// All 12 buyable products, in PaymentConfig order: the full
    /// course first, then the 10 chapter bundles, then Situations.
    /// Data copied from PaymentConfig with two corrections: the
    /// Situations product carries 564 situations, not the stale 500
    /// in PaymentConfig, and its description states 564; and the
    /// full-course description states that the course includes all
    /// Payment Situations. All other fields are copied unchanged.
    static let products: [CourseProduct] = [
        CourseProduct(
            id: "full",
            productID: "com.paymentforge.app.full",
            name: "The Integrated Course",
            tagline: "The flagship. Everything in the academy, all 15 domains.",
            description: "The complete Payments Training Hub academy in one course: all 100 chapters and all 881 narrated lessons, from what a payment is to payment hub architecture, ISO 20022 and SWIFT messaging, clearing and settlement, cards, compliance, APIs, exceptions, reconciliation and AI product ownership for payments, plus all Payment Situations. Buy this and every chapter and every situation unlocks.",
            priceINR: 9999,
            chapterIDs: (1...100).map { "ch\($0)" },
            situationCount: 0 // Stays 0: contentsText shows the situation count instead of the chapter count when set, so the full-course card would lose "All 100 chapters". Inclusion is stated in the description.
        ),
        CourseProduct(
            id: "foundations",
            productID: "com.paymentforge.app.foundations",
            name: "Payment Foundations",
            tagline: "What a payment is, and how the ecosystem fits together.",
            description: "Start here. What a payment is, payment instruments and types, the payment ecosystem, the end-to-end lifecycle, and cheques and paper instruments. For anyone new to payments who wants the ground floor solid before touching messages or rails. It also covers what money is, accounts and balances, ledger posting and reconciliation, lifecycle timelines and failure modes, and ledger systems inside banks.",
            priceINR: 1499,
            chapterIDs: ["ch1", "ch2", "ch3", "ch4", "ch64", "ch69", "ch70", "ch71", "ch72", "ch90"],
            situationCount: 0
        ),
        CourseProduct(
            id: "messaging",
            productID: "com.paymentforge.app.messaging",
            name: "ISO 20022 and SWIFT Messaging",
            tagline: "MT and MX messages, field by field, with real examples.",
            description: "The messaging bundle. SWIFT MT messages, ISO 20022 fundamentals, the pacs.008 deep dive, MT to MX migration and CBPR+, the complete ISO 20022 catalogue, MT101, SWIFT reporting messages, MT103 optional fields, SWIFT fundamentals, pain.001 and pain.002, and ISO 20022 technical implementation.",
            priceINR: 2999,
            chapterIDs: ["ch5", "ch6", "ch7", "ch8", "ch39", "ch50", "ch52", "ch53", "ch54", "ch60", "ch67"],
            situationCount: 0
        ),
        CourseProduct(
            id: "rails",
            productID: "com.paymentforge.app.rails",
            name: "Global Payment Rails",
            tagline: "India, US, Europe and UK rails, plus TARGET and TIPS.",
            description: "How money actually moves in each market. India (UPI, IMPS, NEFT, RTGS), US (Fedwire, FedNow, ACH, CHIPS), Europe (SEPA and TARGET2), UK (Faster Payments, CHAPS, BACS), the Indian payments deep dive, TARGET services, addressing in T2, TIPS in depth, and the SEPA credit transfer and direct debit deep dives. It also covers global instant systems, and the UK, US and SEPA systems in depth.",
            priceINR: 2499,
            chapterIDs: ["ch9", "ch10", "ch11", "ch12", "ch33", "ch56", "ch57", "ch59", "ch61", "ch62", "ch74", "ch91", "ch92", "ch93"],
            situationCount: 0
        ),
        CourseProduct(
            id: "crossborder",
            productID: "com.paymentforge.app.crossborder",
            name: "Cross-Border and Correspondent Banking",
            tagline: "How international payments really work, end to end.",
            description: "The cross-border bundle. Correspondent banking and nostro/vostro, serial versus cover payments, charges, FX and gpi tracking, cross-border exceptions, standby letters of credit, documentary collections and SWIFT category 4, and trade finance. It also covers cross-border investigations, cash management, and cross-border payments in depth.",
            priceINR: 1999,
            chapterIDs: ["ch13", "ch14", "ch15", "ch16", "ch49", "ch51", "ch66", "ch75", "ch76", "ch94"],
            situationCount: 0
        ),
        CourseProduct(
            id: "clearing",
            productID: "com.paymentforge.app.clearing",
            name: "Clearing, Settlement and Liquidity",
            tagline: "Clearing is not settlement. Learn the difference properly.",
            description: "The plumbing underneath every payment. Clearing concepts and netting, settlement models, liquidity management and settlement risk. Short, focused, and the difference between a BA who guesses and one who knows. It also covers settlement design and failure, clearing and settlement mechanisms, and how clearing systems work.",
            priceINR: 999,
            chapterIDs: ["ch17", "ch18", "ch19", "ch20", "ch77", "ch88", "ch89"],
            situationCount: 0
        ),
        CourseProduct(
            id: "cards",
            productID: "com.paymentforge.app.cards",
            name: "Cards and Domestic Payments",
            tagline: "Authorisation, clearing, settlement, wallets and POS.",
            description: "The card bundle. Card authorisation, clearing and settlement, 3D Secure, tokenization and chargebacks, card networks (Visa and Mastercard), digital wallets and POS systems, recurring payments and 3RI, and the card payments deep dive. It also covers cards compliance and acquiring.",
            priceINR: 1499,
            chapterIDs: ["ch21", "ch22", "ch31", "ch32", "ch34", "ch63", "ch78"],
            situationCount: 0
        ),
        CourseProduct(
            id: "compliance-ops",
            productID: "com.paymentforge.app.compliance-ops",
            name: "Compliance, Risk, Operations and Reconciliation",
            tagline: "Sanctions, AML, exceptions, returns and the daily ops grind.",
            description: "The control and operations bundle. Sanctions screening, AML, KYC and fraud prevention, payment security, payment reconciliation, payment exceptions and investigations, payment operations, reject and return in CBPR+, and payment operations architecture. It also covers claims, enquiries and case management, GDPR, BSA/AML and operational resilience, regulatory compliance in payments, the controls that keep payments safe, and screening, fraud and sanctions operations in detail.",
            priceINR: 1999,
            chapterIDs: ["ch23", "ch24", "ch43", "ch40", "ch41", "ch44", "ch58", "ch68", "ch73", "ch81", "ch86", "ch87", "ch95"],
            situationCount: 0
        ),
        CourseProduct(
            id: "architecture-apis",
            productID: "com.paymentforge.app.architecture-apis",
            name: "Payment Architecture and APIs",
            tagline: "Hubs, platforms, gateways and integration, the engineering view.",
            description: "The architecture bundle. Payment hub architecture, API banking and open banking, payment gateway architecture, payment platform architecture, system design deep dive, payment data model and mapping, the payment hub enterprise architecture, and open banking, PSD2 and PSD3. It also covers payment engine internals and observability, and API design standards and integration patterns.",
            priceINR: 2499,
            chapterIDs: ["ch25", "ch30", "ch35", "ch36", "ch38", "ch48", "ch26", "ch65", "ch79", "ch80"],
            situationCount: 0
        ),
        CourseProduct(
            id: "ba-practice",
            productID: "com.paymentforge.app.ba-practice",
            name: "AI Product Owner and Product Manager for Payments",
            tagline: "AI for the payments BA and PO: foundations, assisted work, product ownership, governance and the capstone.",
            description: "The AI Product Owner and Product Manager (AI POPM) bundle for payments. AI foundations for the payments BA and PO, AI-assisted BA work, AI product ownership, AI governance, risk and control, and AI in payments operations, ending in a capstone where you design and specify an AI-assisted payments feature end to end. For learners who want to work as a payments BA, Product Owner or Product Manager in the age of AI. It also covers the BA practical workshop, the capstone project, payment testing and certification, and payment product management.",
            priceINR: 1999,
            chapterIDs: ["ch28", "ch29", "ch42", "ch45", "ch47", "ch82", "ch83", "ch84", "ch96", "ch97", "ch98", "ch99", "ch100"],
            situationCount: 0
        ),
        CourseProduct(
            id: "emerging",
            productID: "com.paymentforge.app.emerging",
            name: "Emerging Technologies and the Future",
            tagline: "CBDCs, stablecoins, AI, and where payments goes next.",
            description: "The future bundle. CBDCs, stablecoins and AI in payments, real-time payments architecture, payments in 2025 and beyond, and how 10 large banks do payments. It also covers embedded finance and ISO 20022 data analytics.",
            priceINR: 999,
            chapterIDs: ["ch27", "ch46", "ch55", "ch37", "ch85"],
            situationCount: 0
        ),
        CourseProduct(
            id: "situations",
            productID: "com.paymentforge.app.situations",
            name: "Payment Situations",
            tagline: "End-to-end payments knowledge, one real situation at a time.",
            description: "564 situational and factual items, sequenced for learning from foundations to advanced, each explained with a visual: a flow diagram that reveals step by step, a stacked chart for a comparison, or a labelled diagram for one concept. No multiple choice, no question and answer drills. For someone who needs end-to-end knowledge of how payments actually work.",
            priceINR: 4999,
            chapterIDs: [],
            situationCount: 564
        ),
    ]

    /// All product IDs, in catalogue order.
    static let allProductIDs: [String] = products.map { $0.productID }

    /// The Integrated Course product ID: it unlocks all chapter
    /// products and all Payment Situations.
    static let fullCourseProductID = "com.paymentforge.app.full"

    /// The App Store Connect product ID for Payment Situations.
    /// Non-consumable, one-time purchase.
    static let situationsProductID = "com.paymentforge.app.situations"

    /// The free sample situations, open without any purchase. Free
    /// sample lessons also exist: the first lesson of each chapter
    /// is free (D77, decided 12 Nov 2026). This list mirrors
    /// ContentService.freeSampleIDs, which is the runtime source used
    /// by SituationsView; keep the two in step.
    static let freeSampleSituationIDs: [String] = [
        "ABH-01", "JEB-C01", "ABH-03", "SCN-21", "RUN4-008", "INS-099"
    ]

    /// The product for an App Store product ID, nil when unknown.
    static func product(for productID: String) -> CourseProduct? {
        products.first { $0.productID == productID }
    }

    /// The chapter bundle that contains this chapter, not counting
    /// the full course (which contains every chapter). Nil when no
    /// bundle contains it; such a chapter maps to no product.
    static func productContaining(chapterID: String) -> CourseProduct? {
        products.first { $0.productID != fullCourseProductID && $0.chapterIDs.contains(chapterID) }
    }

    /// The product for a bundle id (for example "foundations"), nil
    /// when unknown. The situations bundle id in bundles.json is
    /// "situations-500"; that spelling is a real bundle id and must
    /// NOT be renamed. It resolves to the situations product, whose
    /// situation count is 564.
    static func product(forBundleID bundleID: String) -> CourseProduct? {
        if bundleID == "situations-500" {
            return product(for: situationsProductID)
        }
        return products.first { $0.id == bundleID }
    }
}
