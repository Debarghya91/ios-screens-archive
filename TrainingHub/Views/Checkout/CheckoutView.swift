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
// (the 10 courses plus BA/PO Studio, Payment Simulator,
// Investigation Lab, Practice Experiences, Interview Ready, and
// The Integrated Course), each buyable on its own: a part unlocks
// only its own chapters, a standalone product unlocks only its own
// content, and the Integrated Course unlocks everything. Every
// purchase gives 1 year of access from the verified purchase date.
// Every product also has a renewal subscription: 1 more year at
// half the sale price, for buyers who already own the product.
// Prices come only from the App Store product when loaded; when a
// price has not loaded, the price is shown as unavailable and the
// Buy button stays disabled. Counts come from ContentManifest,
// never from hardcoded literals.
//
// D101 decided (hard-gate, v69): SituationsView gates locked
// situation detail, so Practice Experiences access is
// buyer-exclusive except for the free samples and the weekly free
// case. The copy below states what buying gives (1 year of access,
// renewal, restore, cross-device sync when signed in). Do not
// change any gating from this file.

import SwiftUI
import UIKit
import StoreKit

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var storeManager: StoreManager
    @EnvironmentObject private var contentService: ContentService
    @ObservedObject private var finalAssessmentStore = FinalAssessmentStore.shared

    @State private var showTransactionHistory = false

    /// Purchase results show in the single purchase alert owned
    /// by the tab view, so no alert or banner is kept here: one
    /// message, one presenter, no double display.

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
        }
    }

    // MARK: - My Purchases tab

    private var myPurchasesTab: some View {
        VStack(alignment: .leading, spacing: PFSpacing.xl) {
            catalogueIntroCard
            freeVsPaidSection
            productListSection
            actionRowsSection
            paymentMethodsSection
        }
    }

    // MARK: - Catalogue intro

    /// What buying means: one part unlocks only its own chapters,
    /// a standalone product unlocks only its own content, and the
    /// Integrated Course unlocks everything. Every purchase gives
    /// 1 year of access, renewable for 1 more year at half price.
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
                        Text("Products")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("Buy a course to unlock its chapters, or a standalone product to unlock its content. The Integrated Course unlocks everything. Every purchase gives 1 year of access.")
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
                PFBodyText(text: StoreManager.buildPhaseBuyOpensContent ? "For now, Buy opens the course on this device. No payment is taken." : "Each product gives 1 year of access from purchase, and can be renewed for 1 more year at half the sale price. The Integrated Course includes every course and every standalone product. Purchases restore with the same Apple ID, and sync to your account when you are signed in.")
                if storeManager.productLoadFailed || storeManager.productLoadIncomplete {
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
    /// chapter, plus the sequential samples, the free sample
    /// situations, the weekly free case, and the free ISO 20022
    /// Explorer), and paid content from each product's own scope.
    /// No price appears here: prices live only on the product
    /// cards, from StoreKit.
    ///
    /// D101 decided (hard-gate, v69): the Practice row below states
    /// that the set is included in the Integrated Course and is
    /// also buyable on its own, and that locked situation detail
    /// is buyer-exclusive except for the free samples and the
    /// weekly free case.
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
                            text: "The first lesson of each of the \(ContentManifest.chapterCount) chapters, plus the first 2 lessons of each course in reading order. Every other lesson needs its course or the Integrated Course."
                        )
                        comparisonRow(
                            icon: "checkmark",
                            text: "The \(ProductCatalogue.freeSampleSituationIDs.count) free sample situations, and the weekly free case."
                        )
                        comparisonRow(
                            icon: "checkmark",
                            text: "The first 2 BA/PO Studio units, the first 2 career guides, the first 2 simulator runs, the first 5 interview answers, the first 5 FAQ answers, and the first 2 labs."
                        )
                        comparisonRow(
                            icon: "checkmark",
                            text: "The ISO 20022 Explorer, free for everyone."
                        )
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("What buying unlocks")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        comparisonRow(
                            icon: "checkmark",
                            text: "A course unlocks only its own chapters, with all lessons in those chapters. There are \(chapterParts.count) courses."
                        )
                        comparisonRow(
                            icon: "checkmark",
                            text: "Each standalone product unlocks only its own content: BA/PO Studio, the Payment Simulator, the Investigation Lab, Practice Experiences, and Interview Ready."
                        )
                        comparisonRow(
                            icon: "checkmark",
                            text: "The Integrated Course unlocks everything: all \(ContentManifest.chapterCount) chapters, all \(ContentManifest.lessonCount) lessons, and every standalone product."
                        )
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("How to choose")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        comparisonRow(icon: "arrow.right", text: "One area only: buy that part.")
                        comparisonRow(icon: "arrow.right", text: "Only one kind of practice: buy that standalone product.")
                        comparisonRow(icon: "arrow.right", text: "Everything: buy the Integrated Course.")
                        comparisonRow(icon: "arrow.right", text: "Each product is bought on its own at its App Store price, shown on its card below.")
                    }
                    if partChaptersDoNotOverlap {
                        Text("Each chapter sits in exactly one course, so courses never overlap. Buying two courses never buys the same chapter twice.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Every purchase gives 1 year of access, and can be renewed for 1 more year at half the sale price. Purchases restore with the same Apple ID. Expired access locks again until renewed.")
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The courses: every catalogue product with chapters
    /// except the Integrated Course. Standalone products have no
    /// chapters and are excluded by the chapterIDs check.
    private var chapterParts: [CourseProduct] {
        ProductCatalogue.products.filter {
            $0.productID != ProductCatalogue.fullCourseProductID
                && !$0.chapterIDs.isEmpty
        }
    }

    /// True when no chapter appears in more than one part.
    /// Computed from the catalogue at runtime, so the no-overlap
    /// sentence is shown only while the catalogue really has no
    /// overlap. The 10 part chapter lists are disjoint and cover
    /// the 99 in-book chapters; the held-out ch37 sits in no part.
    private var partChaptersDoNotOverlap: Bool {
        var seen: Set<String> = []
        for part in chapterParts {
            for chapterID in part.chapterIDs {
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
            PFSectionHeader(title: "All products")
            ForEach(ProductCatalogue.products) { course in
                productCard(for: course)
            }
        }
    }

    /// One buyable product: name, short description, what the buyer
    /// receives, price, and a Buy button, or an Owned pill plus the
    /// access-until date and a Renew button when it is already
    /// unlocked. The price comes only from the App Store product
    /// when loaded; when it has not loaded, the price is shown as
    /// unavailable and the Buy button stays disabled, so a purchase
    /// is never offered at a hardcoded price.
    private func productCard(for course: CourseProduct) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(alignment: .top, spacing: PFSpacing.md) {
                    // The course thumbnail sits beside the name
                    // when the website exposes one for the course.
                    if let thumbnailPath = PFChapterHelper.courseThumbnailPath(for: course, in: contentService) {
                        PFThumbnailView(thumbnailPath: thumbnailPath, size: 52, cornerRadius: 12)
                    }
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(course.name)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(course.tagline)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if !course.audience.isEmpty {
                            Text(course.audience)
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: PFSpacing.sm)
                    if storeManager.isProductUnlocked(course.productID) {
                        PFPill(
                            text: storeManager.isProductOwned(course.productID) ? "Owned" : "Included",
                            background: Color.pfSuccess.opacity(0.12),
                            foreground: .pfSuccess
                        )
                    }
                }
                HStack(spacing: PFSpacing.sm) {
                    Text(course.contentsText)
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                    Text(course.validityText)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                    Spacer(minLength: 0)
                    Text(storeManager.isPriceAvailable(for: course.productID) ? storeManager.priceText(for: course.productID) : "Price unavailable")
                        .font(.pfCardTitle)
                        .foregroundColor(storeManager.isPriceAvailable(for: course.productID) ? .pfNavy : .pfSecondaryText)
                }
                includedDetailsView(for: course)
                if course.productID == ProductCatalogue.fullCourseProductID {
                    Text("Unlocks everything: all \(ContentManifest.chapterCount) chapters, all \(ContentManifest.lessonCount) lessons, and every standalone product.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if storeManager.isProductUnlocked(course.productID) {
                    if let expiry = storeManager.expiryDate(for: course.productID) {
                        Text("Access until \(Self.displayDateFormatter.string(from: expiry)).")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(unlockedNote(for: course))
                        .font(.pfBody)
                        .foregroundColor(.pfSuccess)
                        .fixedSize(horizontal: false, vertical: true)
                    if storeManager.isProductOwned(course.productID) {
                        renewButton(for: course)
                    }
                    if !course.chapterIDs.isEmpty {
                        finalAssessmentRow(for: course)
                    }
                } else {
                    // Buy with Apple In-App Purchase (StoreKit 2). The
                    // price comes only from the App Store product;
                    // while there is no App Store Connect product yet
                    // it comes from the local TrainingHub.storekit
                    // file in DEBUG builds. When the price has not
                    // loaded, the button stays disabled. Every
                    // purchase gives 1 year of access.
                    PFGoldButton(title: buyButtonTitle(for: course)) {
                        // Clear any stale store message, so the
                        // tab view's purchase alert shows only
                        // this tap's result.
                        storeManager.clearStatusMessage()
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
    /// chapters and lessons from the catalogue, or the standalone
    /// product's own contents summary, plus the access and renewal
    /// terms. Counts come from the catalogue and ContentManifest,
    /// never from invented numbers.
    private func includedDetails(for course: CourseProduct) -> [String] {
        if course.productID == ProductCatalogue.fullCourseProductID {
            return [
                "All \(ContentManifest.chapterCount) chapters",
                "All \(ContentManifest.lessonCount) lessons",
                "Every standalone product: Studio, Simulator, Investigation Lab, Practice Experiences, Interview Ready",
                "1 year of access, renewable for 1 more year at half price",
                "Restores with the same Apple ID"
            ]
        }
        if !course.contentsSummary.isEmpty {
            return [
                course.contentsSummary,
                "1 year of access, renewable for 1 more year at half price",
                "Restores with the same Apple ID"
            ]
        }
        return [
            "\(course.chapterIDs.count) chapters, \(course.lessonCount) lessons",
            "All lessons in those chapters",
            "1 year of access, renewable for 1 more year at half price",
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

    /// The Renew button for a directly owned product: 1 more year
    /// at half the sale price, through the renewal subscription.
    /// Shown only when the buyer directly owns the product, never
    /// when access comes through the Integrated Course.
    private func renewButton(for course: CourseProduct) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFSecondaryButton(title: renewButtonTitle(for: course)) {
                storeManager.clearStatusMessage()
                Task {
                    await storeManager.purchaseRenewal(for: course.productID)
                }
            }
            .disabled(renewButtonDisabled(for: course))
            .opacity(renewButtonDisabled(for: course) ? 0.5 : 1)
            if !storeManager.isPriceAvailable(for: course.renewalProductID) {
                Text("The renewal price is not available yet. Check your connection, then try again.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Renewal adds 1 more year at half the sale price. It is a 1-year auto-renewable subscription; manage or cancel it in the App Store account settings.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The Renew button title: the real renewal StoreKit price when
    /// loaded, a wait message while busy, and "Renewal price
    /// unavailable" when the renewal product has not loaded.
    private func renewButtonTitle(for course: CourseProduct) -> String {
        if storeManager.isBusy { return "Please wait..." }
        if storeManager.isPriceAvailable(for: course.renewalProductID) {
            return "Renew for \(storeManager.priceText(for: course.renewalProductID))"
        }
        return "Renewal price unavailable"
    }

    /// The Renew button stays disabled while busy, and whenever the
    /// renewal StoreKit price has not loaded.
    private func renewButtonDisabled(for course: CourseProduct) -> Bool {
        storeManager.isBusy || !storeManager.isPriceAvailable(for: course.renewalProductID)
    }

    private func unlockedNote(for course: CourseProduct) -> String {
        if course.productID == ProductCatalogue.fullCourseProductID {
            return "Everything is unlocked on this device."
        }
        if storeManager.isProductOwned(course.productID) {
            return "\(course.name) is unlocked on this device."
        }
        return "\(course.name) is unlocked through The Integrated Course."
    }

    /// Final Assessment entry for an owned course: the certificate
    /// when earned, attempts left when open, or a locked note when
    /// all attempts were used without a pass. Standalone products
    /// have no chapters and no assessment, so they never reach here.
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
                            Text("You own the Integrated Course: everything is unlocked, all \(ContentManifest.chapterCount) chapters, all \(ContentManifest.lessonCount) lessons and every standalone product.")
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
                        Task { await storeManager.purchase(productID: ProductCatalogue.fullCourseProductID) }
                    }
                    .disabled(integratedCourseDisabled())
                }
            }
        }
    }

    /// The Integrated Course action-row subtitle: what the buyer
    /// receives, the real StoreKit price when loaded, and the clear
    /// statement that everything is included. No hardcoded price
    /// is ever shown.
    private func integratedCourseSubtitle() -> String {
        if storeManager.isPriceAvailable(for: ProductCatalogue.fullCourseProductID) {
            return "Unlock everything: all \(ContentManifest.chapterCount) chapters, all \(ContentManifest.lessonCount) lessons and every standalone product, for \(storeManager.priceText(for: ProductCatalogue.fullCourseProductID)), with 1 year of access."
        }
        return "Unlock everything: all \(ContentManifest.chapterCount) chapters, all \(ContentManifest.lessonCount) lessons and every standalone product, with 1 year of access. The App Store price is not available yet."
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
                                    Text(transactionDisplayName(for: transaction))
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                    Text(ProductCatalogue.isRenewalProductID(transaction.productID) ? "Renewal subscription" : "App Store purchase")
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
                            detailRow(label: "Access until", value: Self.displayDateFormatter.string(from: transactionAccessUntil(transaction)))
                            detailRow(label: "Transaction ID", value: String(transaction.id))
                            detailRow(label: "Product", value: transaction.productID)
                        }
                    }
                }
            }
        }
    }

    /// The display name for one transaction row: the base product
    /// name, with a renewal marker for renewal subscriptions, so a
    /// renewal row never shows a bare store ID.
    private func transactionDisplayName(for transaction: StoreKit.Transaction) -> String {
        let baseName = ProductCatalogue.productForStoreID(transaction.productID)?.name ?? transaction.productID
        if ProductCatalogue.isRenewalProductID(transaction.productID) {
            return "\(baseName) (renewal)"
        }
        return baseName
    }

    /// The date one transaction's access runs until: the
    /// subscription expiry for a renewal, else the purchase date
    /// plus 1 year.
    private func transactionAccessUntil(_ transaction: StoreKit.Transaction) -> Date {
        if let expiration = transaction.expirationDate { return expiration }
        return EntitlementValidity.expiryDate(forPurchaseAt: transaction.purchaseDate)
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
