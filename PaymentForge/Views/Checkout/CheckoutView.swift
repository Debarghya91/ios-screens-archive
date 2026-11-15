// CheckoutView.swift
// Payments Training Hub iOS - Purchases and Entitlements.
// My Purchases: the catalogue products, transaction history,
// restore and upgrade. In-App Purchase only.
// No account or sign-in is needed to buy or restore: StoreKit
// purchases are tied to the Apple ID, so guests can buy and restore.
// When the user is signed in, a verified purchase is also recorded
// on the server for cross-device sync, but sign-in never blocks a
// purchase or a restore.
// Payment method: Apple In-App Purchase only. Card, Net banking
// and Wallet are NOT available in this version and are shown
// disabled, never as working options.
// No link to any external website payment page.
// Adaptive layout: flexible stacks, no fixed widths, safe on the small
// iPhone SE through to a Pro Max, in portrait and landscape.
//
// My Purchases lists all catalogue products from ProductCatalogue
// (the chapter bundles plus Payment Situations), each buyable on its
// own: a bundle unlocks only its own chapters, the Integrated Course
// unlocks all chapter products and includes all Payment Situations,
// and Payment Situations is also buyable on its own. One-time
// purchases, no tiers,
// no subscription. Prices come only from the App Store product when
// loaded; when a price has not loaded, the price is shown as
// unavailable and the Buy button stays disabled. Counts come from
// ContentManifest, never from hardcoded literals.
//
// D101 decided (hard-gate, v69): SituationsView gates locked
// situation detail, so Situations access is buyer-exclusive
// except for the free samples and the weekly free case. The copy
// below states what buying gives (ownership, restore,
// cross-device sync when signed in). Do not change any gating
// from this file.

import SwiftUI
import UIKit

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var storeManager: StoreManager
    @ObservedObject private var finalAssessmentStore = FinalAssessmentStore.shared

    @State private var showTransactionHistory = false
    /// Arms the Purchase alert: it only ever shows a store message
    /// that follows the learner's own Buy or Restore tap in this
    /// view, mirroring the gated alert in LessonView. The
    /// launch-time product load also writes to statusMessage, and
    /// without this gate its failure would pop a Purchase alert
    /// unprompted. The status banner at the top of this screen
    /// already shows the same message, but it can sit above the
    /// visible scroll area when a Buy button below is tapped, so
    /// the alert is the confirmation the learner always sees.
    @State private var showPurchaseAlert = false

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    // Payment configuration (product IDs and catalogue data) lives in
    // ProductCatalogue (Models/ProductCatalogue.swift); nothing is
    // hardcoded here. Prices come only from StoreKit.

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: PFSpacing.xl) {
                        myPurchasesTab
                        footerNote
                    }
                    .padding(PFSpacing.lg)
                    .id("checkoutTop")
                }
                .pfScrollToTopOnAppear("checkoutTop")
                .background(Color.pfBackground)
            }
            .background(Color.pfBackground)
            .navigationTitle("Purchases")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // The launch product load may still be in flight or
                // may have failed; retry once when Purchases opens
                // so the Buy buttons enable without a relaunch.
                // loadProducts() ignores a concurrent fetch, so this
                // never stacks a duplicate request.
                if !storeManager.allProductsLoaded {
                    await storeManager.loadProducts()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert(
                "Purchase",
                isPresented: Binding(
                    get: { showPurchaseAlert && storeManager.statusMessage != nil },
                    set: {
                        if !$0 {
                            storeManager.clearStatusMessage()
                            showPurchaseAlert = false
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(storeManager.statusMessage ?? "")
            }
        }
    }

    // MARK: - My Purchases tab

    private var myPurchasesTab: some View {
        VStack(alignment: .leading, spacing: PFSpacing.xl) {
            if let message = storeManager.statusMessage {
                Text(message)
                    .font(.pfBody)
                    .foregroundColor(storeManager.isPurchased ? .pfSuccess : .pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(PFSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.pfNavySoft)
                    .cornerRadius(PFSpacing.cardRadius)
            }
            catalogueIntroCard
            freeVsPaidSection
            productListSection
            actionRowsSection
            paymentMethodsSection
        }
    }

    // MARK: - Catalogue intro

    /// What buying means: one bundle unlocks only its own chapters,
    /// the Integrated Course unlocks all chapter products and
    /// includes all Payment Situations, and Payment Situations is
    /// also buyable on its own.
    private var catalogueIntroCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(alignment: .top, spacing: PFSpacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.pfGoldSoft)
                            .frame(width: 52, height: 52)
                        Image(systemName: "crown.fill")
                            .font(.pfSectionTitle.weight(.semibold))
                            .foregroundColor(.pfGold)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Courses")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("Buy a course to unlock its chapters. The Integrated Course unlocks all chapters and includes all Payment Situations. Payment Situations is also sold on its own.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: PFSpacing.sm)
                    PFPill(
                        text: storeManager.unlockedProductCount == ProductCatalogue.products.count ? "All owned" : "\(storeManager.unlockedProductCount) of \(ProductCatalogue.products.count) owned",
                        background: Color.pfSuccess.opacity(0.12),
                        foreground: .pfSuccess
                    )
                }
                // D101 decided (hard-gate, v69): this text states
                // what buying gives: ownership of the set, restore,
                // and sync when signed in. See the file header.
                PFBodyText(text: StoreManager.buildPhaseBuyOpensContent ? "For now, Buy opens the course on this device. No payment is taken." : "Each course is a one-time purchase, no subscription. The Integrated Course includes the full set of \(ContentManifest.situationCount) Payment Situations. Payment Situations is also sold on its own for learners who want only the situations set. Purchases restore with the same Apple ID, and sync to your account when you are signed in.")
                if storeManager.productLoadFailed {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Prices could not be loaded from the App Store. Check your connection, then try again. No purchase can be made until the price loads.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry loading prices") {
                            Task { await storeManager.loadProducts() }
                        }
                        .disabled(storeManager.isBusy)
                    }
                }
            }
        }
    }

    // MARK: - Free vs paid comparison (Item 28)

    /// Free vs paid, driven by ProductCatalogue and ContentManifest,
    /// so the comparison cannot drift from the catalogue: free
    /// content from the settled D77 model (the first lesson of each
    /// chapter, plus the free sample situations), and paid content
    /// from each product's own chapter list. No price appears here:
    /// prices live only on the product cards, from StoreKit.
    ///
    /// D101 PENDING: the Situations row below states that the set is
    /// included in the Integrated Course and is also buyable on its
    /// own. It deliberately makes no buyer-exclusivity claim,
    /// because SituationsView currently shows the full detail when
    /// locked. See the file header. Do not add a buyer-exclusivity
    /// claim here until the D101 owner decision lands.
    /// D77 settled: the first lesson of each chapter is free; the
    /// old framing that denied the free samples (D118) must not be
    /// repeated in this section.
    private var freeVsPaidSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Free vs paid")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Free, no purchase needed")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        comparisonRow(
                            icon: "checkmark",
                            text: "The first lesson of each of the \(ContentManifest.chapterCount) chapters. Every other lesson needs its chapter bundle or the Integrated Course."
                        )
                        comparisonRow(
                            icon: "checkmark",
                            text: "The \(ProductCatalogue.freeSampleSituationIDs.count) free sample situations."
                        )
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("What buying unlocks")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        comparisonRow(
                            icon: "checkmark",
                            text: "A chapter bundle unlocks only its own chapters, with all lessons in those chapters. There are \(chapterBundles.count) bundles."
                        )
                        comparisonRow(
                            icon: "checkmark",
                            text: "The Integrated Course unlocks all \(ContentManifest.chapterCount) chapters, all \(ContentManifest.lessonCount) lessons and all \(ContentManifest.situationCount) Payment Situations."
                        )
                        comparisonRow(
                            icon: "checkmark",
                            text: "Payment Situations is also available as a one-time purchase on its own for the full set of \(ContentManifest.situationCount) situations, for learners who want only the situations set."
                        )
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("How to choose")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        comparisonRow(icon: "arrow.right", text: "One area only: buy that bundle.")
                        comparisonRow(icon: "arrow.right", text: "Every chapter and all situations: buy the Integrated Course.")
                        comparisonRow(icon: "arrow.right", text: "Only the situations set: buy Payment Situations on its own.")
                        comparisonRow(icon: "arrow.right", text: "Each product is bought on its own at its App Store price, shown on its card below.")
                    }
                    if bundleChaptersDoNotOverlap {
                        Text("Each chapter sits in exactly one bundle, so bundles never overlap. Buying two bundles never buys the same chapter twice.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Every purchase is a one-time payment. There is no subscription and nothing renews. Purchases restore with the same Apple ID.")
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The chapter bundles: every catalogue product except the
    /// Integrated Course and Payment Situations.
    private var chapterBundles: [CourseProduct] {
        ProductCatalogue.products.filter {
            $0.productID != ProductCatalogue.fullCourseProductID
                && $0.productID != ProductCatalogue.situationsProductID
        }
    }

    /// True when no chapter appears in more than one bundle.
    /// Computed from the catalogue at runtime, so the no-overlap
    /// sentence is shown only while the catalogue really has no
    /// overlap. Verified against the v61 catalogue: the 10 bundle
    /// chapter lists are disjoint and cover all 100 chapters.
    private var bundleChaptersDoNotOverlap: Bool {
        var seen: Set<String> = []
        for bundle in chapterBundles {
            for chapterID in bundle.chapterIDs {
                if seen.contains(chapterID) { return false }
                seen.insert(chapterID)
            }
        }
        return true
    }

    private func comparisonRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: PFSpacing.sm) {
            Image(systemName: icon)
                .font(.pfCaptionBold)
                .foregroundColor(.pfSuccess)
                .accessibilityHidden(true)
            Text(text)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Product list

    private var productListSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "All courses")
            ForEach(ProductCatalogue.products) { course in
                productCard(for: course)
            }
        }
    }

    /// One buyable product: name, short description, what the buyer
    /// receives, price, and a Buy button, or an Owned pill when it is
    /// already unlocked. The price comes only from the App Store
    /// product when loaded; when it has not loaded, the price is
    /// shown as unavailable and the Buy button stays disabled, so a
    /// purchase is never offered at a hardcoded price.
    private func productCard(for course: CourseProduct) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(alignment: .top, spacing: PFSpacing.md) {
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(course.name)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(course.tagline)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: PFSpacing.sm)
                    if storeManager.isProductUnlocked(course.productID) {
                        PFPill(
                            text: "Owned",
                            background: Color.pfSuccess.opacity(0.12),
                            foreground: .pfSuccess
                        )
                    }
                }
                HStack(spacing: PFSpacing.sm) {
                    Text(course.contentsText)
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                    Text("One-time payment")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                    Spacer(minLength: 0)
                    Text(storeManager.isPriceAvailable(for: course.productID) ? storeManager.priceText(for: course.productID) : "Price unavailable")
                        .font(.pfCardTitle)
                        .foregroundColor(storeManager.isPriceAvailable(for: course.productID) ? .pfNavy : .pfSecondaryText)
                }
                includedDetailsView(for: course)
                if course.productID == ProductCatalogue.fullCourseProductID {
                    Text("Unlocks all \(ContentManifest.chapterCount) chapters, all \(ContentManifest.lessonCount) lessons and all \(ContentManifest.situationCount) Payment Situations.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if storeManager.isProductUnlocked(course.productID) {
                    Text(unlockedNote(for: course))
                        .font(.pfBody)
                        .foregroundColor(.pfSuccess)
                        .fixedSize(horizontal: false, vertical: true)
                    if !course.chapterIDs.isEmpty {
                        finalAssessmentRow(for: course)
                    }
                } else {
                    // Buy with Apple In-App Purchase (StoreKit 2). The
                    // price comes only from the App Store product;
                    // while there is no App Store Connect product yet
                    // it comes from the local PaymentForge.storekit
                    // file in DEBUG builds. When the price has not
                    // loaded, the button stays disabled. One-time
                    // purchase, no subscription.
                    PFGoldButton(title: buyButtonTitle(for: course)) {
                        // Clear any stale store message and arm the
                        // alert, so only this tap's result can pop
                        // the Purchase alert.
                        storeManager.clearStatusMessage()
                        showPurchaseAlert = true
                        Task {
                            await storeManager.purchase(productID: course.productID)
                        }
                    }
                    .disabled(buyButtonDisabled(for: course))
                    .opacity(buyButtonDisabled(for: course) ? 0.5 : 1)
                    if !storeManager.isPriceAvailable(for: course.productID) {
                        Text("The App Store price is not available yet. Check your connection, then try again.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(StoreManager.buildPhaseBuyOpensContent ? "For now, Buy opens the course on this device. No payment is taken." : "Pay securely with your Apple ID, the same way you pay in any App Store app. No account needed.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// What the buyer receives for one product, shown before purchase:
    /// chapters, lessons or situations from the catalogue and the
    /// shared content counts. Per-bundle lesson counts are not stored
    /// anywhere, so bundles state "all lessons in those chapters"
    /// without inventing a number.
    private func includedDetails(for course: CourseProduct) -> [String] {
        if course.productID == ProductCatalogue.fullCourseProductID {
            return [
                "All \(ContentManifest.chapterCount) chapters",
                "All \(ContentManifest.lessonCount) lessons",
                "All \(ContentManifest.situationCount) Payment Situations",
                "One-time purchase, no subscription",
                "Restores with the same Apple ID"
            ]
        }
        if course.productID == ProductCatalogue.situationsProductID {
            return [
                "All \(ContentManifest.situationCount) situations",
                "The \(ProductCatalogue.freeSampleSituationIDs.count) free sample situations stay free",
                "One-time purchase, no subscription",
                "Restores with the same Apple ID"
            ]
        }
        return [
            "\(course.chapterIDs.count) chapters",
            "All lessons in those chapters",
            "One-time purchase, no subscription",
            "Restores with the same Apple ID"
        ]
    }

    private func includedDetailsView(for course: CourseProduct) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.xs) {
            ForEach(includedDetails(for: course), id: \.self) { detail in
                HStack(alignment: .top, spacing: PFSpacing.sm) {
                    Image(systemName: "checkmark")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSuccess)
                    Text(detail)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The Buy button title: the real StoreKit price when loaded, a
    /// wait message while busy, and "Price unavailable" when the
    /// product has not loaded. A hardcoded price is never shown.
    private func buyButtonTitle(for course: CourseProduct) -> String {
        if storeManager.isBusy { return "Please wait..." }
        if storeManager.isPriceAvailable(for: course.productID) {
            return "Buy for \(storeManager.priceText(for: course.productID))"
        }
        return "Price unavailable"
    }

    /// The Buy button stays disabled while busy, and whenever the
    /// StoreKit price has not loaded.
    private func buyButtonDisabled(for course: CourseProduct) -> Bool {
        storeManager.isBusy || !storeManager.isPriceAvailable(for: course.productID)
    }

    private func unlockedNote(for course: CourseProduct) -> String {
        if course.productID == ProductCatalogue.fullCourseProductID {
            return "All chapters and all Payment Situations are unlocked on this device."
        }
        if course.productID == ProductCatalogue.situationsProductID {
            return "Payment Situations is unlocked on this device."
        }
        return "\(course.name) is unlocked on this device."
    }

    /// Final Assessment entry for an owned course: the certificate
    /// when earned, attempts left when open, or a locked note when
    /// all attempts were used without a pass. Situations has no
    /// chapters and no assessment, so it never reaches here.
    private func finalAssessmentRow(for course: CourseProduct) -> some View {
        let certificate = finalAssessmentStore.certificate(for: course.productID)
        let remaining = finalAssessmentStore.attemptsRemaining(for: course.productID)
        let used = finalAssessmentStore.attemptsUsedCount(for: course.productID)
        return VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Divider()
            if let certificate {
                NavigationLink(destination: CourseCertificateView(certificate: certificate)) {
                    HStack(spacing: PFSpacing.sm) {
                        Image(systemName: "seal.fill")
                            .foregroundColor(.pfGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Certificate earned")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.pfNavy)
                            Text("\(certificate.courseName) - \(certificate.scoreText) (\(Int(certificate.scorePercent.rounded()))%)")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.pfSecondaryText)
                    }
                }
                .buttonStyle(.plain)
            } else if remaining > 0 {
                NavigationLink(destination: FinalAssessmentView(course: course)) {
                    HStack(spacing: PFSpacing.sm) {
                        Image(systemName: "list.clipboard.fill")
                            .foregroundColor(.pfRoyal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Final Assessment")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.pfNavy)
                            Text("20 questions, pass above 70%. \(used) of \(FinalAssessmentStore.maxAttempts) attempts used.")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.pfSecondaryText)
                    }
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.pfSecondaryText)
                    Text("Final Assessment locked. All \(FinalAssessmentStore.maxAttempts) attempts used. Contact Payments Training Hub support for another attempt.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: PFSpacing.md) {
            Text(label)
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Action rows (mockup Screen 10)

    /// Restore Purchases, Transaction History and Upgrade / Renew as
    /// icon, label and chevron rows in one card. Transaction History
    /// expands inline to show the real App Store transaction, or an
    /// honest empty state when there is none.
    private var actionRowsSection: some View {
        PFCard {
            VStack(spacing: 0) {
                actionRowButton(
                    icon: "arrow.counterclockwise.circle.fill",
                    title: "Restore Purchases",
                    subtitle: "Already bought it on another iPhone or after reinstalling? Restore it with the same Apple ID. No account needed."
                ) {
                    storeManager.clearStatusMessage()
                    showPurchaseAlert = true
                    Task { await storeManager.restorePurchases() }
                }
                .disabled(storeManager.isBusy)
                Divider()
                    .padding(.leading, 56)
                actionRowButton(
                    icon: "receipt.fill",
                    title: "Transaction History",
                    subtitle: storeManager.latestTransaction == nil
                        ? "No App Store purchase on this Apple ID yet."
                        : "App Store purchase on this Apple ID."
                ) {
                    withAnimation {
                        showTransactionHistory.toggle()
                    }
                }
                if showTransactionHistory {
                    Divider()
                        .padding(.leading, 56)
                    transactionHistoryDetail
                        .padding(.top, PFSpacing.md)
                }
                Divider()
                    .padding(.leading, 56)
                if storeManager.isProductUnlocked(ProductCatalogue.fullCourseProductID) {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "crown.fill")
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("The Integrated Course")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            Text("You own the Integrated Course: all \(ContentManifest.chapterCount) chapters, all \(ContentManifest.lessonCount) lessons and all \(ContentManifest.situationCount) Payment Situations.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: PFSpacing.sm)
                        PFPill(
                            text: "Owned",
                            background: Color.pfSuccess.opacity(0.12),
                            foreground: .pfSuccess
                        )
                    }
                    .padding(.vertical, PFSpacing.md)
                } else {
                    actionRowButton(
                        icon: "crown.fill",
                        title: "The Integrated Course",
                        subtitle: integratedCourseSubtitle()
                    ) {
                        storeManager.clearStatusMessage()
                        showPurchaseAlert = true
                        Task { await storeManager.purchase(productID: ProductCatalogue.fullCourseProductID) }
                    }
                    .disabled(integratedCourseDisabled())
                }
            }
        }
    }

    /// The Integrated Course action-row subtitle: what the buyer
    /// receives, the real StoreKit price when loaded, and the clear
    /// statement that Situations is included. No hardcoded price
    /// is ever shown.
    private func integratedCourseSubtitle() -> String {
        if storeManager.isPriceAvailable(for: ProductCatalogue.fullCourseProductID) {
            return "Unlock all \(ContentManifest.chapterCount) chapters, all \(ContentManifest.lessonCount) lessons and all \(ContentManifest.situationCount) Payment Situations for \(storeManager.priceText(for: ProductCatalogue.fullCourseProductID)), one-time payment."
        }
        return "Unlock all \(ContentManifest.chapterCount) chapters, all \(ContentManifest.lessonCount) lessons and all \(ContentManifest.situationCount) Payment Situations, one-time payment. The App Store price is not available yet."
    }

    private func integratedCourseDisabled() -> Bool {
        storeManager.isBusy || !storeManager.isPriceAvailable(for: ProductCatalogue.fullCourseProductID)
    }

    /// One action row: icon tile, title and subtitle, chevron on the
    /// right. The whole row is the button, so the tap target is wide.
    private func actionRowButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: icon)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text(subtitle)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PFSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.pfCaption.weight(.semibold))
                    .foregroundColor(.pfSecondaryText)
            }
            .padding(.vertical, PFSpacing.md)
        }
        .buttonStyle(.plain)
    }

    /// The App Store entitlement transactions, latest first. When
    /// there are none, an honest empty state, never a fake list. No
    /// price is shown per transaction: the transaction record holds
    /// no price, and the current display price may differ from the
    /// price paid.
    private var transactionHistoryDetail: some View {
        Group {
            if storeManager.ownedTransactions.isEmpty {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "receipt")
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("No transactions yet")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            Text("No App Store purchase has been made on this Apple ID yet.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: PFSpacing.xl) {
                    ForEach(storeManager.ownedTransactions, id: \.id) { transaction in
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            HStack(spacing: PFSpacing.md) {
                                PFIconTile(systemImage: "receipt.fill")
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(ProductCatalogue.product(for: transaction.productID)?.name ?? transaction.productID)
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                    Text("App Store purchase")
                                        .font(.pfBody)
                                        .foregroundColor(.pfSecondaryText)
                                }
                                Spacer(minLength: PFSpacing.sm)
                                PFPill(
                                    text: "Active",
                                    background: Color.pfSuccess.opacity(0.12),
                                    foreground: .pfSuccess
                                )
                            }
                            Divider()
                            detailRow(label: "Date", value: Self.displayDateFormatter.string(from: transaction.purchaseDate))
                            detailRow(label: "Transaction ID", value: String(transaction.id))
                            detailRow(label: "Product", value: transaction.productID)
                        }
                    }
                }
            }
        }
    }

    /// Payment methods audit: only Apple In-App Purchase works.
    /// Card, Net banking and Wallet are not switched
    /// on and are shown disabled with Not available, never presented
    /// as a working option and never selectable.
    private var paymentMethodsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Payment methods")
            PFCard {
                VStack(spacing: PFSpacing.md) {
                    paymentMethodRow(
                        icon: "apple.logo",
                        name: "In-App Purchase",
                        note: "Pay with your Apple ID. Each course shows its App Store price.",
                        state: "Available",
                        available: true
                    )
                    Divider()
                    paymentMethodRow(
                        icon: "creditcard.fill",
                        name: "Card",
                        note: "Card payments are not switched on in this version.",
                        state: "Not available",
                        available: false
                    )
                    Divider()
                    paymentMethodRow(
                        icon: "building.columns.fill",
                        name: "Net banking",
                        note: "Net banking is not switched on in this version.",
                        state: "Not available",
                        available: false
                    )
                    Divider()
                    paymentMethodRow(
                        icon: "wallet.pass.fill",
                        name: "Wallet",
                        note: "Wallet payments are not switched on in this version.",
                        state: "Not available",
                        available: false
                    )
                }
            }
        }
    }

    private func paymentMethodRow(icon: String, name: String, note: String, state: String, available: Bool) -> some View {
        HStack(alignment: .top, spacing: PFSpacing.md) {
            PFIconTile(systemImage: icon)
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                Text(name)
                    .font(.pfCardTitle)
                    .foregroundColor(available ? .pfNavy : .pfSecondaryText)
                Text(note)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: PFSpacing.sm)
            PFPill(
                text: state,
                background: available ? Color.pfSuccess.opacity(0.12) : Color.pfSecondaryText.opacity(0.12),
                foreground: available ? .pfSuccess : .pfSecondaryText
            )
        }
        .opacity(available ? 1 : 0.7)
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("No account is needed. Purchases are tied to your Apple ID. When you are signed in, your progress syncs across your devices. If you have questions, email support@paymentstraininghub.com.")
            .font(.pfBody)
            .foregroundColor(.pfSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
