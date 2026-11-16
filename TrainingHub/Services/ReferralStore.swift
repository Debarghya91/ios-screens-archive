// ReferralStore.swift
// Payments Training Hub iOS - The signed-in user's OWN referral code and
// credit balance, for display and sharing only. APP RULE (decided):
// the app shows the code with a share affordance and shows the
// credit balance, and states plainly that referral discount
// redemption is website-only, because Apple In-App Purchase cannot
// take an external discount. Nothing in this file touches
// StoreManager or any purchase path: no discount is ever wired into
// IAP, and no referral code entry exists in the app signup flow.
// The code is derived deterministically from the account id (SHA-256
// over a fixed prefix plus the id, mapped onto the shared alphabet),
// so it is stable across devices for the same account without a
// server round trip. LIMIT: there is no referral read endpoint in
// the fixed contract, so this locally derived code is provisional
// until the server issues referral codes through an endpoint; the
// website validates every code at redemption, so a code the server
// does not know is refused there with REFERRAL_INVALID. The credit
// balance is likewise local-only until a referral read endpoint
// exists: it starts at 0 and the UI says credits are confirmed on
// the website. Neither value is ever presented as server-confirmed.
// No em dashes in any user-facing text.

import Foundation
import Combine
import CryptoKit

@MainActor
final class ReferralStore: ObservableObject {
    static let shared = ReferralStore()

    private static let creditBalanceBaseKey = "pf.referral.creditBalance.v1"

    /// The locally recorded referral credit balance for the current
    /// account. Namespaced per account, so deletion removes it with
    /// the namespace. See the file header: local-only until a
    /// referral read endpoint exists.
    @Published private(set) var creditBalance: Int = 0

    /// The signed-in user's own referral code: 8 uppercase characters
    /// from the shared alphabet. Nil for a guest: a guest has no
    /// account for a code to belong to.
    var referralCode: String? {
        guard let userID = AuthService.shared.currentUser?.id else { return nil }
        return Self.code(forUserID: userID)
    }

    /// Derive the referral code for an account id. Deterministic:
    /// the same id always yields the same code, on every device.
    static func code(forUserID userID: String) -> String {
        let digest = SHA256.hash(data: Data("pf-referral:\(userID)".utf8))
        let alphabet = Array(PFCodeAlphabet.characters)
        var code = ""
        for byte in digest.prefix(8) {
            code.append(alphabet[Int(byte) % alphabet.count])
        }
        return code
    }

    init() {
        reloadForCurrentAccount()
    }

    /// Reload the credit balance for the current namespace. Called on
    /// every identity transition through AuthService.reloadAllStores.
    func reloadForCurrentAccount() {
        creditBalance = UserDefaults.standard.integer(forKey: AccountScopedStorage.currentKey(Self.creditBalanceBaseKey))
    }

    /// The share text for the user's own code. It names the website
    /// as the place a referral discount is applied, and promises no
    /// discount inside the app. Empty when there is no code (guest).
    var shareText: String {
        guard let code = referralCode else { return "" }
        return [
            "I am learning payments with Payments Training Hub.",
            "My referral code is \(code).",
            "Referral discounts are applied on the website: \(SupabaseConfig.siteBaseURL.absoluteString)"
        ].joined(separator: "\n")
    }
}

// MARK: - Referral and promo rules

/// The decided referral and promo rules, encoded in one place so
/// every surface states the same terms. These rules are
/// WEBSITE-VALIDATED: the website checks every code at redemption,
/// and Apple In-App Purchase cannot take an external discount, so
/// nothing here is wired into any purchase path. The referral code
/// issuer itself is still unbuilt queued work: the code shown in
/// the app is locally derived and provisional (see the file
/// header), and no invite or share text promises a credit.
enum ReferralRules {

    /// The credit the referrer earns, in rupees, when a referred
    /// person buys a qualifying product. Referrer only: the
    /// referred person gets no credit.
    static let referrerCreditINR = 100

    /// Minimum sale price for a product to qualify for referral
    /// credit: Rs 999. In the current catalogue that is Practice
    /// Experiences, Interview Ready, and The Integrated Course.
    static let minimumQualifyingSalePriceINR = 999

    /// The launch promo code. It applies as the coupon layer on
    /// sale prices for parts and standalone items only, never on
    /// The Integrated Course, and never stacked with a referral.
    static let launchPromoCode = "FIRSTLAUNCH25"

    /// True when this product qualifies for referral credit: its
    /// sale price is Rs 999 or more. The credit is earned only
    /// when the referred person buys.
    static func qualifiesForReferralCredit(_ product: CourseProduct) -> Bool {
        product.priceINR >= minimumQualifyingSalePriceINR
    }

    /// The products that qualify for referral credit, in catalogue
    /// order.
    static var qualifyingProducts: [CourseProduct] {
        ProductCatalogue.products.filter(qualifiesForReferralCredit)
    }

    /// True when the launch promo applies to this product: every
    /// product except The Integrated Course. It never stacks with
    /// a referral.
    static func promoApplies(to product: CourseProduct) -> Bool {
        product.productID != ProductCatalogue.integratedProductID
    }

    /// One rules line for the referrals section, in the
    /// website-validated framing the app already uses.
    static var rulesLine: String {
        "Refer a friend: you earn Rs. 100 when they buy Practice Experiences, Interview Ready, or The Integrated Course. Promo code FIRSTLAUNCH25 does not apply to The Integrated Course and cannot be combined with a referral. All referral and promo terms are confirmed on the website."
    }
}
