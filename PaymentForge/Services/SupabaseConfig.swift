// SupabaseConfig.swift
// Payments Training Hub iOS - Supabase configuration.
// Live project: paymentforge (eofsotgclhwsdwvbbtib), ap-south-1 (Mumbai),
// Free plan, status Healthy, organisation account. Wired to the live project
// URL and publishable key below; a bundled Config.plist still overrides
// them when present (add Config.plist to the Xcode target with
// SUPABASE_URL and SUPABASE_ANON_KEY to use different values).
// NEVER put a service-role key in the app. The publishable (anon) key is
// safe to ship: row level security on the server decides what it can
// touch. The legacy anon JWT is not used (it retires early 2027).
// No em dashes in any user-facing text.

import Foundation

/// Supabase project configuration for the Payments Training Hub app.
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
/// One buyable product in the decided 16-product lineup (see
/// ProductCatalogue.swift, the one authoritative catalogue). A
/// book part's chapters are the chapters it unlocks; standalone
/// products (Studio, Simulator, Investigation Lab, Practice
/// Experiences, Interview Ready) have no chapters and unlock their
/// own content instead. Prices are INR reference data only: the
/// sale price is what the buyer pays, the list price is stated
/// value metadata for the website's list-plus-sale display, and
/// the renewal price is half the sale price for a 1-year renewal
/// subscription. No price here is ever shown as a purchase price:
/// StoreKit displayPrice is the only shown price.
/// Product IDs follow com.paymentforge.app.<product>, matching the
/// App Store Connect products and PaymentForge.storekit. Renewal
/// subscription IDs append ".renewal".
///
struct CourseProduct: Identifiable, Hashable {
    /// Catalogue id, for example "part-1" or "studio".
    let id: String
    /// The App Store Connect purchase product ID.
    let productID: String
    /// Display name, for example "Part 1: Foundations of Money and Payments".
    let name: String
    /// Short description shown on the Purchases screen.
    let tagline: String
    /// Full description.
    let description: String
    /// Sale price in rupees: what the buyer pays. Reference data
    /// only; never shown as a purchase price.
    let priceINR: Int
    /// The chapters this product unlocks. Empty for standalone products.
    let chapterIDs: [String]
    /// Number of situations, 564 for Practice Experiences, 0 otherwise.
    let situationCount: Int
    /// List (stated regular) price in rupees, at most 50 percent
    /// above the sale price. Metadata only: list-plus-sale display
    /// is website-only, and the store product carries the sale price.
    let listPriceINR: Int
    /// Renewal subscription price in rupees: half the sale price,
    /// round-half-up, for 1 more year of access.
    let renewalPriceINR: Int
    /// Access validity in days from the verified purchase
    /// timestamp. 365 (1 year) for every product.
    let validityDays: Int
    /// Book lessons in this product's chapters (parts and the
    /// Integrated Course). 0 for standalone products.
    let lessonCount: Int
    /// Contents line override for standalone products. Empty means
    /// the contents line is derived from chapters or situations.
    let contentsSummary: String

    init(
        id: String,
        productID: String,
        name: String,
        tagline: String,
        description: String,
        priceINR: Int,
        chapterIDs: [String],
        situationCount: Int,
        listPriceINR: Int = 0,
        renewalPriceINR: Int = 0,
        validityDays: Int = EntitlementValidity.validityDays,
        lessonCount: Int = 0,
        contentsSummary: String = ""
    ) {
        self.id = id
        self.productID = productID
        self.name = name
        self.tagline = tagline
        self.description = description
        self.priceINR = priceINR
        self.chapterIDs = chapterIDs
        self.situationCount = situationCount
        self.listPriceINR = listPriceINR
        self.renewalPriceINR = renewalPriceINR
        self.validityDays = validityDays
        self.lessonCount = lessonCount
        self.contentsSummary = contentsSummary
    }

    /// The renewal subscription product ID for this product.
    var renewalProductID: String { productID + ".renewal" }

    /// "Rs. 399" style display price for the sale price. Reference
    /// data only; never shown as a purchase price.
    var priceText: String { PaymentConfig.priceText(for: priceINR) }

    /// "Rs. 399, 1 year of access" style detail line.
    var priceDetailText: String { "\(priceText), \(validityText)" }

    /// "1 year of access" for the standard 365-day validity.
    var validityText: String {
        if validityDays == EntitlementValidity.validityDays { return "1 year of access" }
        return "\(validityDays) days of access"
    }

    /// Short contents line for the Purchases screen: "7 chapters,
    /// 49 lessons" for a part, "99 chapters, 874 lessons" for the
    /// Integrated Course, the contents summary for a standalone
    /// product, "564 situations" when only a situation count exists.
    var contentsText: String {
        if !contentsSummary.isEmpty { return contentsSummary }
        if !chapterIDs.isEmpty, lessonCount > 0 {
            let chapterWord = chapterIDs.count == 1 ? "chapter" : "chapters"
            return "\(chapterIDs.count) \(chapterWord), \(lessonCount) lessons"
        }
        if situationCount > 0 { return "\(situationCount) situations" }
        if !chapterIDs.isEmpty {
            let chapterWord = chapterIDs.count == 1 ? "chapter" : "chapters"
            return "\(chapterIDs.count) \(chapterWord)"
        }
        return ""
    }
}

///
/// All payment configuration lives in ProductCatalogue; this enum
/// is a thin alias layer over it, kept so the one remaining
/// PaymentConfig call site (CertificateView) and the shared price
/// formatter keep working. The frozen 12-product copy this enum
/// used to carry was replaced in the v90 catalogue change: the old
/// division is shelved, and no old product ID may reappear here.
/// Payment is In-App Purchase only. There are no secrets, admin
/// credentials or service-role keys anywhere in the app.
///
enum PaymentConfig {

    /// All 16 buyable products, from ProductCatalogue.
    static var products: [CourseProduct] { ProductCatalogue.products }

    /// All 16 purchase product IDs.
    static var allProductIDs: [String] { ProductCatalogue.allProductIDs }

    /// The Integrated Course product ID: it unlocks everything.
    static let fullCourseProductID = "com.paymentforge.app.integrated"

    /// The product for an App Store product ID, nil when unknown.
    static func product(for productID: String) -> CourseProduct? {
        ProductCatalogue.product(for: productID)
    }

    /// The product for a catalogue id (for example "part-1"), nil
    /// when unknown.
    static func product(forBundleID bundleID: String) -> CourseProduct? {
        ProductCatalogue.product(forBundleID: bundleID)
    }

    /// The part that contains this chapter, not counting the
    /// Integrated Course (which contains every chapter). Nil when
    /// no part contains it.
    static func productContaining(_ chapterID: String) -> CourseProduct? {
        ProductCatalogue.productContaining(chapterID: chapterID)
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
}
