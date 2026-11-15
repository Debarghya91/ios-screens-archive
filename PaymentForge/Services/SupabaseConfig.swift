// SupabaseConfig.swift
// PaymentForge iOS - Supabase configuration.
// Live project: paymentforge (eofsotgclhwsdwvbbtib), ap-south-1 (Mumbai),
// Free plan, status Healthy, organisation Deba. Wired to the live project
// URL and publishable key below; a bundled Config.plist still overrides
// them when present (add Config.plist to the Xcode target with
// SUPABASE_URL and SUPABASE_ANON_KEY to use different values).
// NEVER put a service-role key in the app. The publishable (anon) key is
// safe to ship: row level security on the server decides what it can
// touch. The legacy anon JWT is not used (it retires early 2027).
// No em dashes in any user-facing text.

import Foundation

/// Supabase project configuration for the PaymentForge app.
enum SupabaseConfig {

    /// Live project URL.
    static let projectURL = "https://eofsotgclhwsdwvbbtib.supabase.co"

    /// Live publishable (anon) key. Safe to ship in the app; RLS on the
    /// server decides what it can touch. Never a service-role key.
    static let publishableKey = "sb_publishable_4d5gOEpkTOMp7NadcV9ErA_Ujcc2ahU"

    /// The project URL: Config.plist first, live project otherwise.
    static var url: String {
        value(forKey: "SUPABASE_URL") ?? projectURL
    }

    /// The anon key: Config.plist first, live publishable key otherwise.
    static var anonKey: String {
        value(forKey: "SUPABASE_ANON_KEY") ?? publishableKey
    }

    /// True only when real values are present. Everything that talks to
    /// Supabase checks this first and becomes a graceful no-op when it
    /// is false, so the app never crashes and never blocks a guest.
    static var isConfigured: Bool {
        let urlValue = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyValue = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlValue.isEmpty, !keyValue.isEmpty else { return false }
        guard urlValue.hasPrefix("https://"), urlValue.contains(".supabase.co") else { return false }
        return true
    }

    /// The REST base URL, for example https://eofsotgclhwsdwvbbtib.supabase.co/rest/v1.
    static var restBaseURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: url + "/rest/v1")
    }

    /// The Auth base URL, for example https://eofsotgclhwsdwvbbtib.supabase.co/auth/v1.
    static var authBaseURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: url + "/auth/v1")
    }

    /// The Storage base URL, for example https://eofsotgclhwsdwvbbtib.supabase.co/storage/v1.
    static var storageBaseURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: url + "/storage/v1")
    }

    /// The Edge Functions base URL, for example
    /// https://eofsotgclhwsdwvbbtib.supabase.co/functions/v1.
    /// Used only for server-side writes the app may not do directly
    /// (record-purchase, delete-account). The functions run with the
    /// service-role key in their own environment, never in the app.
    static var functionsBaseURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: url + "/functions/v1")
    }

    // MARK: - Auth redirect (OAuth and magic link callbacks)

    /// The custom URL scheme the app uses for Supabase Auth callbacks
    /// (Google sign-in and magic links). The callback URL is
    /// com.paymentforge.app://auth-callback. The scheme is registered
    /// in Info.plist (CFBundleURLSchemes) and PaymentForgeApp
    /// forwards incoming URLs to
    /// AuthService.shared.handleAuthCallback(url:). Also add
    /// com.paymentforge.app://auth-callback to the Redirect URLs in
    /// the Supabase dashboard under Authentication > URL Configuration.
    static let authRedirectScheme = "com.paymentforge.app"

    /// The full callback URL sent as redirect_to to Supabase Auth.
    static var authRedirectURL: URL? {
        URL(string: "\(authRedirectScheme)://auth-callback")
    }

    // MARK: - Website links

    /// The live learning website.
    static let siteBaseURL = URL(string: "https://www.paymentstraininghub.com")!

    /// TODO (owner): confirm these pages exist on the live website and
    /// publish them if they do not. The links below assume the usual
    /// /privacy and /terms paths; do not ship the app with dead links.
    static let privacyPolicyURL = URL(string: "https://www.paymentstraininghub.com/privacy")!
    static let termsURL = URL(string: "https://www.paymentstraininghub.com/terms")!

    // MARK: - Private

    private static func value(forKey key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let raw = plist[key] as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Payment configuration (single source of truth)

///
/// One buyable course product: a bundle from bundles.json
/// (~/workspace/paymentforge-v2/content/bundles.json). The 12 products
/// are the 11 chapter bundles plus Payment Situations. A bundle's
/// chapters are the chapters it unlocks; Situations has no chapters
/// and unlocks the 500 situations instead. Prices are the INR prices
/// from bundles.json, as set on 11 Nov 2026.
/// Product IDs follow com.paymentforge.app.<bundle-id>, matching the
/// App Store Connect products and PaymentForge.storekit.
///
struct CourseProduct: Identifiable, Hashable {
    /// Bundle id from bundles.json, for example "foundations".
    let id: String
    /// The App Store Connect product ID.
    let productID: String
    /// Display name, for example "Payment Foundations".
    let name: String
    /// Short description shown on the Purchases screen.
    let tagline: String
    /// Full description from bundles.json.
    let description: String
    /// One-time price in rupees.
    let priceINR: Int
    /// The chapters this product unlocks. Empty for Situations.
    let chapterIDs: [String]
    /// Number of situations, 500 for Situations, 0 otherwise.
    let situationCount: Int

    /// "Rs. 1,499" style display price.
    var priceText: String { PaymentConfig.priceText(for: priceINR) }

    /// "Rs. 1,499, one-time payment" style detail line.
    var priceDetailText: String { "\(priceText), one-time payment" }

    /// Short contents line for the Purchases screen: "10 chapters"
    /// for a bundle, "All 100 chapters" for the full course,
    /// "500 situations" for Situations.
    var contentsText: String {
        if situationCount > 0 { return "\(situationCount) situations" }
        if chapterIDs.count == 100 { return "All 100 chapters" }
        return "\(chapterIDs.count) chapters"
    }
}

///
/// All payment configuration lives here, so no view or service
/// hardcodes a product ID or a price. The 12 products below are the
/// single source of truth for the catalogue; change a price only with
/// explicit approval, in this one place. Payment is
/// In-App Purchase only. There are no secrets, admin credentials or
/// service-role keys anywhere in the app.
///
enum PaymentConfig {

    /// All 12 buyable products, in bundles.json order: the full
    /// course first, then the 10 chapter bundles, then Situations.
    static let products: [CourseProduct] = [
        CourseProduct(
            id: "full",
            productID: "com.paymentforge.app.full",
            name: "The Integrated Course",
            tagline: "The flagship. Everything in the academy, all 15 domains.",
            description: "The complete Payments Training Hub academy in one course: all 100 chapters and all 881 narrated lessons, from what a payment is to payment hub architecture, ISO 20022 and SWIFT messaging, clearing and settlement, cards, compliance, APIs, exceptions, reconciliation and AI product ownership for payments. Buy this and every chapter unlocks.",
            priceINR: 9999,
            chapterIDs: (1...100).map { "ch\($0)" },
            situationCount: 0
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
            description: "Five hundred situational and factual items, sequenced for learning from foundations to advanced, each explained with a visual: a flow diagram that reveals step by step, a stacked chart for a comparison, or a labelled diagram for one concept. No multiple choice, no question and answer drills. For someone who needs end-to-end knowledge of how payments actually work.",
            priceINR: 4999,
            chapterIDs: [],
            situationCount: 500
        ),
    ]

    /// All 12 product IDs.
    static let allProductIDs: [String] = products.map { $0.productID }

    /// The Integrated Course product ID: it unlocks everything,
    /// all chapters and all Payment Situations.
    static let fullCourseProductID = "com.paymentforge.app.full"

    /// The product for an App Store product ID, nil when unknown.
    static func product(for productID: String) -> CourseProduct? {
        products.first { $0.productID == productID }
    }

    /// The product for a bundle id (for example "foundations"), nil
    /// when unknown. The situations bundle id in bundles.json is
    /// "situations-500"; the app's product id is "situations", and
    /// both spellings resolve to the situations product.
    static func product(forBundleID bundleID: String) -> CourseProduct? {
        if bundleID == "situations-500" {
            return product(for: situationsProductID)
        }
        return products.first { $0.id == bundleID }
    }

    /// The chapter bundle that contains this chapter, not counting
    /// the full course (which contains every chapter). Nil when no
    /// bundle contains it; such a chapter is never locked.
    static func productContaining(_ chapterID: String) -> CourseProduct? {
        products.first { $0.productID != fullCourseProductID && $0.chapterIDs.contains(chapterID) }
    }

    /// "Rs. 1,499" style display price for a rupee amount. All
    /// catalogue prices are below one lakh, so a single thousands
    /// separator is the correct Indian grouping for every price here.
    static func priceText(for amountINR: Int) -> String {
        if amountINR >= 1000 {
            return "Rs. \(amountINR / 1000),\(String(format: "%03d", amountINR % 1000))"
        }
        return "Rs. \(amountINR)"
    }

    /// The App Store Connect product ID for Payment Situations.
    /// Non-consumable, one-time purchase.
    static let situationsProductID = "com.paymentforge.app.situations"

    /// The price in rupees. Fixed at Rs. 4,999.
    static let priceAmountINR = 4999

    /// The display price, used when StoreKit has not loaded the
    /// product yet. Never changes the price itself.
    static let priceText = "Rs. 4,999"

    /// The price as shown on the Purchases detail row.
    static let priceDetailText = "Rs. 4,999, one-time payment"
}
