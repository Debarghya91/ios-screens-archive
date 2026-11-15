// ProductCatalogue.swift
// Payments Training Hub iOS - the one authoritative product catalogue.
//
// Decided lineup (15 Nov 2026, owner order "DO IT", revised the same
// day to 1-year access for all products and list prices at most 50
// percent above the sale price): 16 products. The 10 courses at
// Rs 399 sale each, BA/PO Studio at Rs 799, Payment Simulator at
// Rs 499, Investigation Lab at Rs 499, Practice Experiences at
// Rs 999, Interview Ready at Rs 1,599, and The Integrated Course at
// Rs 2,999. Every product gives 1 year of access from the verified
// purchase timestamp. Renewal is a separate 1-year auto-renewable
// subscription per product at half the SALE price (parts Rs 200,
// Studio Rs 400, Simulator Rs 250, Lab Rs 250, Practice Rs 500,
// Interview Rs 800, Integrated Rs 1,500). The old 12-product
// division (chapter bundles plus standalone Situations) is shelved
// and its product IDs must not reappear anywhere.
//
// This catalogue supersedes PaymentConfig for StoreManager and
// CheckoutView. PaymentConfig (in SupabaseConfig.swift) now aliases
// this catalogue; the frozen copy it used to carry was replaced in
// the same change. FinalAssessment and LessonView read this
// catalogue. SearchView reads it for its bundle lookup.
// CertificateView reads PaymentConfig for one lookup, which now
// resolves through this catalogue. CourseProduct is the existing
// struct declared in SupabaseConfig.swift and is reused here, not
// redeclared.
//
// Prices: priceINR (sale) and listPriceINR are reference data only.
// They are NEVER shown as a purchase price. The only price a buyer
// ever sees is the StoreKit product displayPrice, shown by
// StoreManager.priceText(for:) once the product has loaded. If the
// StoreKit product has not loaded, the price is shown as unavailable
// and purchase is disabled. App Store Connect (and the local
// PaymentForge.storekit file for DEBUG testing) is the source of
// truth for prices. Store products carry ONE price each: the SALE
// price. The list price is stated-value metadata for the website's
// list-plus-sale display; the app never renders it as a price.
// Renewal prices are halves of the SALE price, never of the list
// price.

import Foundation

/// The one authoritative catalogue of the buyable products.
///
/// 16 purchase products (non-consumable, 1 year of access each)
/// plus 16 renewal subscriptions (auto-renewable, 1 year each).
/// Purchase IDs follow com.paymentforge.app.<product>; renewal IDs
/// append ".renewal". All 32 IDs must match the App Store Connect
/// products and PaymentForge.storekit exactly. The ISO 20022
/// Explorer is free for everyone and has no product.
///
/// Chapter scopes follow the live v1.1 reading-order map exactly:
/// 99 chapters, 874 book lessons. Per-course lesson counts are
/// 49/137/149/71/110/98/37/118/79/26. The held-out ch37 (How 10
/// Large Banks Do Payments) sits in NO product and is never sold.
/// Supplemental lessons (72) follow their chapter's part by ID
/// prefix. Chapter tests belong to their chapters' courses.
///
/// Entitlement rules (enforced by StoreManager, stated here so the
/// offer and the enforcement cannot drift apart):
///   A course unlocks only its own chapters.
///   Studio unlocks the 156 BABOK teaching units and 5 career guides.
///   Simulator unlocks all 10 simulators.
///   Investigation Lab unlocks the full 616-item Investigation Experience.
///   Practice Experiences unlocks the 564 Situations, Practice Mode,
///     Daily Challenge, 10 labs, 14 ISO exercises and 52 weekly cases.
///     The weekly free case stays free for everyone.
///   Interview Ready unlocks the 500 interview questions and 320 FAQ.
///   The Integrated Course unlocks everything above. It does not
///     commercially include the held-out ch37.
///   A product is unlocked while the buyer holds an ACTIVE purchase
///     of that product, an ACTIVE renewal subscription for it, or an
///     ACTIVE Integrated purchase or renewal. Expired entitlements
///     lock again. Ownership means a verified StoreKit transaction
///     on the device, or an active server entitlement row. In
///     Release builds no local flag alone ever unlocks a product.
///   A chapter no course contains maps to no product. The held-out
///     ch37 stays reachable without a purchase: it is never sold,
///     so it is never locked behind a product that does not exist.
///
/// Free samples: 2 per section or product, with a buy prompt after
/// the second, except Interview Ready which keeps 5 free questions.
/// Chapter and lesson outlines plus first-lesson-of-chapter
/// browsing (D77) stay free; the paywall sits on the sequential
/// learning path, not on discovery. Free situations: ABH-01 and
/// JEB-C01 only. The old Rs 2,000 interview-bank unlock rule is
/// retired and must never be implemented; it exists nowhere in code.
///
/// Restore eligibility: every purchase product is a non-consumable,
/// so every purchase is restorable with the same Apple ID on any
/// device (Restore Purchases in CheckoutView). Renewal subscriptions
/// restore through the App Store subscription state. When the buyer
/// is signed in, a verified purchase is also recorded on the server
/// through the record-purchase Edge Function, so the entitlement
/// follows the account to other devices. Refunds and revocations
/// remove the entitlement on the device and on the server.
enum ProductCatalogue {

    /// All 16 buyable products, in shelf order: the Integrated
    /// Course first, then the 10 courses in reading order, then
    /// the standalone products (Studio, Simulator, Investigation
    /// Lab, Practice Experiences, Interview Ready).
    static let products: [CourseProduct] = [
        CourseProduct(
            id: "integrated",
            productID: "com.paymentforge.app.integrated",
            name: "The Integrated Course",
            tagline: "Everything in the academy, in one course.",
            description: "The complete Payments Training Hub academy in one course: all 10 courses, all 99 chapters and all 874 lessons, plus BA/PO Studio, the Payment Simulator, the Investigation Lab, Practice Experiences and Interview Ready. Buy this and every course and every standalone product unlocks for 1 year.",
            priceINR: 2999,
            chapterIDs: ["ch1", "ch2", "ch3", "ch4", "ch64", "ch69", "ch70", "ch9", "ch10", "ch11", "ch12", "ch33", "ch56", "ch57", "ch59", "ch61", "ch62", "ch74", "ch91", "ch92", "ch93", "ch5", "ch6", "ch7", "ch8", "ch38", "ch54", "ch39", "ch50", "ch51", "ch52", "ch53", "ch58", "ch60", "ch67", "ch13", "ch14", "ch15", "ch16", "ch94", "ch49", "ch66", "ch75", "ch17", "ch18", "ch21", "ch71", "ch90", "ch19", "ch20", "ch40", "ch44", "ch76", "ch77", "ch88", "ch89", "ch72", "ch23", "ch24", "ch41", "ch86", "ch87", "ch95", "ch73", "ch78", "ch81", "ch99", "ch22", "ch31", "ch32", "ch34", "ch63", "ch25", "ch26", "ch30", "ch35", "ch36", "ch42", "ch43", "ch46", "ch47", "ch48", "ch65", "ch80", "ch68", "ch79", "ch28", "ch45", "ch82", "ch83", "ch84", "ch29", "ch96", "ch97", "ch98", "ch100", "ch55", "ch27", "ch85"],
            situationCount: 0,
            listPriceINR: 4499,
            renewalPriceINR: 1500,
            lessonCount: 874
        ),
        CourseProduct(
            id: "part-1",
            productID: "com.paymentforge.app.part-1",
            name: "Course 1: Foundations of Money and Payments",
            tagline: "Speak the language of payments, from zero.",
            description: "Start here. What a payment is, payment instruments and types, the payment ecosystem, the end-to-end lifecycle, cheques and paper instruments, what money is, and accounts and balances. For anyone starting from zero who wants the ground floor solid before touching messages or rails.",
            priceINR: 399,
            chapterIDs: ["ch1", "ch2", "ch3", "ch4", "ch64", "ch69", "ch70"],
            situationCount: 0,
            listPriceINR: 599,
            renewalPriceINR: 200,
            lessonCount: 49
        ),
        CourseProduct(
            id: "part-2",
            productID: "com.paymentforge.app.part-2",
            name: "Course 2: How Payments Move: Rails, Schemes and Systems",
            tagline: "India, US, Europe and UK rails, plus TARGET and TIPS.",
            description: "How money actually moves in each market. India (UPI, IMPS, NEFT, RTGS), US (Fedwire, FedNow, ACH, CHIPS), Europe (SEPA and T2), UK (Faster Payments, CHAPS, BACS), the Indian payments deep dive, TARGET services, TIPS in depth, the SEPA deep dives, and global instant systems.",
            priceINR: 399,
            chapterIDs: ["ch9", "ch10", "ch11", "ch12", "ch33", "ch56", "ch57", "ch59", "ch61", "ch62", "ch74", "ch91", "ch92", "ch93"],
            situationCount: 0,
            listPriceINR: 599,
            renewalPriceINR: 200,
            lessonCount: 137
        ),
        CourseProduct(
            id: "part-3",
            productID: "com.paymentforge.app.part-3",
            name: "Course 3: Messages: SWIFT MT, ISO 20022 and Standards",
            tagline: "MT and MX messages, field by field, with real examples.",
            description: "The messaging course. SWIFT MT messages, ISO 20022 fundamentals, the pacs.008 deep dive, MT to MX migration and CBPR+, the payment data model and mapping, SWIFT fundamentals, the complete ISO 20022 catalogue, MT101, documentary collections, SWIFT reporting messages, MT103 optional fields, reject and return in CBPR+, pain.001 and pain.002, and ISO 20022 technical implementation.",
            priceINR: 399,
            chapterIDs: ["ch5", "ch6", "ch7", "ch8", "ch38", "ch54", "ch39", "ch50", "ch51", "ch52", "ch53", "ch58", "ch60", "ch67"],
            situationCount: 0,
            listPriceINR: 599,
            renewalPriceINR: 200,
            lessonCount: 149
        ),
        CourseProduct(
            id: "part-4",
            productID: "com.paymentforge.app.part-4",
            name: "Course 4: Cross-Border Payments and Correspondent Banking",
            tagline: "How international payments really work, end to end.",
            description: "The cross-border course. Correspondent banking and nostro/vostro, serial versus cover payments, charges, FX and gpi tracking, cross-border exceptions, cross-border payments in depth, standby letters of credit, trade finance, and cross-border investigations.",
            priceINR: 399,
            chapterIDs: ["ch13", "ch14", "ch15", "ch16", "ch94", "ch49", "ch66", "ch75"],
            situationCount: 0,
            listPriceINR: 599,
            renewalPriceINR: 200,
            lessonCount: 71
        ),
        CourseProduct(
            id: "part-5",
            productID: "com.paymentforge.app.part-5",
            name: "Course 5: Clearing, Settlement, Liquidity and Reconciliation",
            tagline: "Clearing is not settlement. Learn the difference properly.",
            description: "Run the settlement day. Clearing concepts and netting, settlement models, card authorisation, clearing and settlement, ledger posting and reconciliation, ledger systems inside banks, liquidity management, settlement risk, payment reconciliation, payment operations, cash management, settlement design and failure, and how clearing systems work.",
            priceINR: 399,
            chapterIDs: ["ch17", "ch18", "ch21", "ch71", "ch90", "ch19", "ch20", "ch40", "ch44", "ch76", "ch77", "ch88", "ch89"],
            situationCount: 0,
            listPriceINR: 599,
            renewalPriceINR: 200,
            lessonCount: 110
        ),
        CourseProduct(
            id: "part-6",
            productID: "com.paymentforge.app.part-6",
            name: "Course 6: Exceptions, Investigations, Returns and Claims",
            tagline: "Run an investigation to closure, and prove the control worked.",
            description: "The control course. Lifecycle timelines and failure modes, sanctions screening, AML, KYC and fraud prevention, payment exceptions and investigations, regulatory compliance, the controls that keep payments safe, screening, fraud and sanctions operations in detail, claims, enquiries and case management, cards compliance and acquiring, GDPR, BSA/AML and operational resilience, and AI governance, risk and control.",
            priceINR: 399,
            chapterIDs: ["ch72", "ch23", "ch24", "ch41", "ch86", "ch87", "ch95", "ch73", "ch78", "ch81", "ch99"],
            situationCount: 0,
            listPriceINR: 599,
            renewalPriceINR: 200,
            lessonCount: 98
        ),
        CourseProduct(
            id: "part-7",
            productID: "com.paymentforge.app.part-7",
            name: "Course 7: Cards and Customer Payments",
            tagline: "From tap to settlement, wallets and POS included.",
            description: "The cards course. 3D Secure, tokenization and chargebacks, card networks (Visa and Mastercard), digital wallets and POS systems, recurring payments and 3RI, and the card payments deep dive.",
            priceINR: 399,
            chapterIDs: ["ch22", "ch31", "ch32", "ch34", "ch63"],
            situationCount: 0,
            listPriceINR: 599,
            renewalPriceINR: 200,
            lessonCount: 37
        ),
        CourseProduct(
            id: "part-8",
            productID: "com.paymentforge.app.part-8",
            name: "Course 8: Architecture, APIs, Hubs and Engineering",
            tagline: "Hubs, platforms, gateways and integration, the engineering view.",
            description: "The architecture course. Payment hub architecture, API banking and open banking, payment gateway architecture, payment platform architecture, system design deep dive, payment testing and certification, payment security, real-time payments architecture, banking integration patterns, the payment hub enterprise architecture, open banking, PSD2 and PSD3, API design standards and integration patterns, payment operations architecture, and payment engine internals and observability.",
            priceINR: 399,
            chapterIDs: ["ch25", "ch26", "ch30", "ch35", "ch36", "ch42", "ch43", "ch46", "ch47", "ch48", "ch65", "ch80", "ch68", "ch79"],
            situationCount: 0,
            listPriceINR: 599,
            renewalPriceINR: 200,
            lessonCount: 118
        ),
        CourseProduct(
            id: "part-9",
            productID: "com.paymentforge.app.part-9",
            name: "Course 9: The Business Analyst at Work",
            tagline: "Do the BA job end to end, and deliver the capstone.",
            description: "The BA course. The BA practical workshop, payment product management, product strategy and business models, scheme onboarding and build versus buy, BA practice depth, the capstone project, AI foundations for the payments BA and PO, AI-assisted BA work, AI product ownership, and AI in payments operations and capstone. BA/PO Studio teaching is sold separately as its own product.",
            priceINR: 399,
            chapterIDs: ["ch28", "ch45", "ch82", "ch83", "ch84", "ch29", "ch96", "ch97", "ch98", "ch100"],
            situationCount: 0,
            listPriceINR: 599,
            renewalPriceINR: 200,
            lessonCount: 79
        ),
        CourseProduct(
            id: "part-10",
            productID: "com.paymentforge.app.part-10",
            name: "Course 10: Emerging Payments and the Future",
            tagline: "CBDCs, stablecoins, embedded finance, and where payments goes next.",
            description: "The future course. Payments in 2025 and beyond, CBDCs, stablecoins and AI in payments, and embedded finance and ISO 20022 data analytics. Small in volume, current in subject: the value here is currency, not lesson count.",
            priceINR: 399,
            chapterIDs: ["ch55", "ch27", "ch85"],
            situationCount: 0,
            listPriceINR: 599,
            renewalPriceINR: 200,
            lessonCount: 26
        ),
        CourseProduct(
            id: "studio",
            productID: "com.paymentforge.app.studio",
            name: "BA/PO Studio",
            tagline: "BABOK teaching for the payments BA and PO, plus career guides.",
            description: "The Studio teaches how to do BA and product work: 156 teaching units covering BABOK key concepts, knowledge areas and tasks, techniques, competencies and perspectives, with worked examples and practice inside each unit, plus 5 career guides. Sold on its own; it is not included in any course.",
            priceINR: 799,
            chapterIDs: [],
            situationCount: 0,
            listPriceINR: 1199,
            renewalPriceINR: 400,
            contentsSummary: "156 teaching units and 5 career guides"
        ),
        CourseProduct(
            id: "simulator",
            productID: "com.paymentforge.app.simulator",
            name: "Payment Simulator",
            tagline: "Run a payment yourself, and watch it move.",
            description: "All 10 simulators: run a payment through its lifecycle, drive a payment hub, work T2 and TIPS, post the accounting, investigate an exception, step the state machine, run scenarios, play with the API, trace a cross-border payment, and explore messages hands on.",
            priceINR: 499,
            chapterIDs: [],
            situationCount: 0,
            listPriceINR: 749,
            renewalPriceINR: 250,
            contentsSummary: "All 10 simulators"
        ),
        CourseProduct(
            id: "investigation-lab",
            productID: "com.paymentforge.app.investigation-lab",
            name: "Investigation Lab",
            tagline: "Investigate real payment incidents, briefing to report.",
            description: "The full Investigation Experience: 616 investigation items. Trace a case, check the message evidence, test hypotheses, make decisions, and diagnose the root cause, from briefing to report.",
            priceINR: 499,
            chapterIDs: [],
            situationCount: 0,
            listPriceINR: 749,
            renewalPriceINR: 250,
            contentsSummary: "616 investigation cases"
        ),
        CourseProduct(
            id: "practice",
            productID: "com.paymentforge.app.practice",
            name: "Practice Experiences",
            tagline: "End-to-end payments knowledge, one real situation at a time.",
            description: "The doing product: 564 situational items sequenced from foundations to advanced, each explained with a visual, plus the full Practice Mode pool, the full Daily Challenge, 10 labs, 14 ISO exercises, and 52 weekly cases. The weekly free case stays free for everyone.",
            priceINR: 999,
            chapterIDs: [],
            situationCount: 564,
            listPriceINR: 1499,
            renewalPriceINR: 500,
            contentsSummary: "564 situations, practice, labs and cases"
        ),
        CourseProduct(
            id: "interview",
            productID: "com.paymentforge.app.interview",
            name: "Interview Ready",
            tagline: "Walk into a payments interview able to answer.",
            description: "500 interview questions across every payments domain, each with a model answer in plain language, plus the 320-item FAQ bank as backup. For active job seekers preparing for a payments interview.",
            priceINR: 1599,
            chapterIDs: [],
            situationCount: 0,
            listPriceINR: 2399,
            renewalPriceINR: 800,
            contentsSummary: "500 questions and 320 FAQs"
        ),
    ]

    /// All 16 purchase product IDs, in catalogue order.
    static let allProductIDs: [String] = products.map { $0.productID }

    /// All 16 renewal subscription IDs, in catalogue order.
    static let allRenewalProductIDs: [String] = products.map { $0.renewalProductID }

    /// All 32 store product IDs (purchases plus renewals), in
    /// catalogue order. StoreKit fetches this full set; the server
    /// record-purchase allowlist must hold the same 32 IDs.
    static let allStoreProductIDs: [String] = allProductIDs + allRenewalProductIDs

    /// The Integrated Course product ID: it unlocks every product.
    static let integratedProductID = "com.paymentforge.app.integrated"

    /// Alias kept for existing call sites: the full course is The
    /// Integrated Course.
    static let fullCourseProductID = integratedProductID

    /// The Practice Experiences product ID.
    static let practiceProductID = "com.paymentforge.app.practice"

    /// The BA/PO Studio product ID.
    static let studioProductID = "com.paymentforge.app.studio"

    /// The Payment Simulator product ID.
    static let simulatorProductID = "com.paymentforge.app.simulator"

    /// The Investigation Lab product ID.
    static let investigationLabProductID = "com.paymentforge.app.investigation-lab"

    /// The Interview Ready product ID.
    static let interviewProductID = "com.paymentforge.app.interview"

    /// The 10 courses, in reading order.
    static var partProducts: [CourseProduct] {
        products.filter { $0.id.hasPrefix("part-") }
    }

    /// Chapters held outside every product: kept and reachable,
    /// never sold. Currently only ch37.
    static let heldOutChapterIDs: Set<String> = ["ch37"]

    /// True when this chapter sits in no product and is never sold.
    static func isHeldOutChapter(_ chapterID: String) -> Bool {
        heldOutChapterIDs.contains(chapterID)
    }

    /// The free sample situations, open without any purchase. Free
    /// sample lessons also exist: the first lesson of each chapter
    /// is free (D77, decided 12 Nov 2026), plus the first 2 lessons
    /// of each part in reading order (see FreeSampleRules). This
    /// list mirrors ContentService.freeSampleIDs, which is the
    /// runtime source used by SituationsView; keep the two in step.
    static let freeSampleSituationIDs: [String] = [
        "ABH-01", "JEB-C01"
    ]

    /// The product for a purchase product ID, nil when unknown.
    /// Renewal IDs do not resolve here; use productForStoreID.
    static func product(for productID: String) -> CourseProduct? {
        products.first { $0.productID == productID }
    }

    /// True when this store ID is a renewal subscription ID.
    static func isRenewalProductID(_ storeID: String) -> Bool {
        storeID.hasSuffix(".renewal")
    }

    /// The renewal subscription ID for a purchase product ID.
    static func renewalProductID(for productID: String) -> String {
        productID + ".renewal"
    }

    /// The purchase product ID behind a store ID: the ID itself for
    /// a purchase, the base ID for a renewal ID. Nil when the store
    /// ID belongs to no catalogue product.
    static func baseProductID(forStoreID storeID: String) -> String? {
        if isRenewalProductID(storeID) {
            let base = String(storeID.dropLast(".renewal".count))
            return product(for: base) == nil ? nil : base
        }
        return product(for: storeID) == nil ? nil : storeID
    }

    /// The product for any store ID: a purchase ID resolves to its
    /// product, a renewal ID resolves to the product it renews.
    /// Nil when unknown.
    static func productForStoreID(_ storeID: String) -> CourseProduct? {
        guard let base = baseProductID(forStoreID: storeID) else { return nil }
        return product(for: base)
    }

    /// The course that contains this chapter, not counting the
    /// Integrated Course (which contains every chapter). Nil when
    /// no course contains it; such a chapter maps to no product.
    static func productContaining(chapterID: String) -> CourseProduct? {
        products.first { $0.productID != integratedProductID && $0.chapterIDs.contains(chapterID) }
    }

    /// The product for a catalogue id (for example "part-1",
    /// "studio", "integrated"), nil when unknown. Unknown ids
    /// resolve to nothing: there are no legacy aliases, so an
    /// abolished bundle id can never silently map to a product.
    static func product(forBundleID bundleID: String) -> CourseProduct? {
        products.first { $0.id == bundleID }
    }
}

// MARK: - Validity

/// The 1-year access rule, shared by the device and server
/// entitlement paths. Pure date arithmetic, covered by unit tests.
enum EntitlementValidity {

    /// Access validity in days, for every product: 1 year.
    static let validityDays = 365

    /// The expiry date for a purchase made at this timestamp:
    /// 365 days later, by calendar days.
    static func expiryDate(forPurchaseAt purchaseDate: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: validityDays, to: purchaseDate)
            ?? purchaseDate.addingTimeInterval(TimeInterval(validityDays) * 24 * 60 * 60)
    }

    /// True when an entitlement with this expiry is active at this
    /// moment. A nil expiry means no expiry was recorded, which
    /// happens only for DEBUG-seeded cache state in tests: it
    /// counts as active there, and never occurs in Release, where
    /// every entitlement path records an expiry.
    static func isActive(expiry: Date?, at now: Date = Date()) -> Bool {
        guard let expiry else { return true }
        return expiry > now
    }
}

// MARK: - Free samples

/// The free-sample counts and the sequential lesson samples, shared
/// by the lesson, Studio, simulator, interview and FAQ gates. Pure
/// logic over the reading-order map, covered by unit tests.
enum FreeSampleRules {

    /// Sequential free lessons per course, in reading order,
    /// in addition to the D77 first-lesson-of-chapter rule.
    static let sequentialSamplesPerPart = 2

    /// Free interview questions, in bank order.
    static let interviewFreeQuestionCount = 5

    /// Free Studio teaching units, in Studio order.
    static let studioFreeLessonCount = 2

    /// Free Studio career guides, in guide order.
    static let studioFreeGuideCount = 2

    /// Free simulator runs before the buy prompt.
    static let simulatorFreeRuns = 2

    /// Free FAQ answers, in catalogue order.
    static let faqFreeCount = 5

    /// Free labs, in catalogue order.
    static let labFreeCount = 2

    /// The first 2 lesson IDs of one course in reading-order-map
    /// order. Empty when the map has no lesson lists loaded (the
    /// hardcoded fallback), in which case only D77 samples apply
    /// and nothing extra opens.
    static func sequentialSampleLessonIDs(forPartNumber partNumber: Int) -> [String] {
        let lessons = PFBookModeReadingOrder.orderedLessons.filter { lessonID in
            guard let number = PFChapterHelper.chapterNumber(from: lessonID) else { return false }
            return PFBookModeReadingOrder.part(forInternalNumber: number)?.number == partNumber
        }
        return Array(lessons.prefix(sequentialSamplesPerPart))
    }

    /// The 0-based position of a lesson within its course's
    /// sequential samples, or nil when it is not one of them.
    /// Position 1 is the second (last) free sample: the buy
    /// prompt goes with it.
    static func sequentialSampleIndex(forLessonID lessonID: String) -> Int? {
        guard let number = PFChapterHelper.chapterNumber(from: lessonID),
              let part = PFBookModeReadingOrder.part(forInternalNumber: number) else { return nil }
        return sequentialSampleLessonIDs(forPartNumber: part.number).firstIndex(of: lessonID)
    }

    /// True when this lesson is one of its course's sequential free
    /// samples.
    static func isSequentialSampleLesson(_ lessonID: String) -> Bool {
        sequentialSampleIndex(forLessonID: lessonID) != nil
    }
}
