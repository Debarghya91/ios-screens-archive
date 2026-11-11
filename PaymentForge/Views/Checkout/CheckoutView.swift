// CheckoutView.swift
// PaymentForge iOS - Purchases and Entitlements.
// Two tabs: My Purchases (the 12 course products, transaction
// history, restore, upgrade) and Payment Claims (the UPI claim flow).
// No account or sign-in is needed to buy or restore: StoreKit
// purchases are tied to the Apple ID, so guests can buy and restore.
// When the user is signed in, the coordinator associates the
// entitlement with the account for cross-device sync, but sign-in
// never blocks a purchase or a restore.
// Payment methods that work: Apple In-App Purchase, and UPI by claim.
// Card, Net banking and Wallet are NOT available in this version and
// are shown disabled, never as working options.
// UPI claims are PENDING until verified. Submitting a UTR never
// unlocks premium content. Only a verified payment grants access.
// No link to any external website payment page.
// Adaptive layout: flexible stacks, no fixed widths, safe on the small
// iPhone SE through to a Pro Max, in portrait and landscape.
//
// My Purchases lists all 12 products from PaymentConfig (the 11
// chapter bundles plus Payment Situations), each buyable on its own:
// a bundle unlocks only its own chapters, the Integrated Course
// unlocks everything, and Situations unlocks the 500 situations
// (or the Integrated Course does). One-time purchases, no tiers,
// no subscription. Prices come from the App Store product when loaded,
// otherwise from PaymentConfig.

import SwiftUI
import UIKit

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var storeManager: StoreManager
    @ObservedObject private var finalAssessmentStore = FinalAssessmentStore.shared

    private enum PurchasesTab: String, CaseIterable, Identifiable {
        case myPurchases = "My Purchases"
        case paymentClaims = "Payment Claims"

        var id: String { rawValue }
    }

    // Payment configuration (product ID, price, UPI ID) lives in
    // PaymentConfig (SupabaseConfig.swift); nothing is hardcoded here.

    @State private var selectedTab: PurchasesTab = .myPurchases
    @State private var payerName = ""
    @State private var utr = ""
    @State private var copied = false
    @State private var payAppOpened = false
    @State private var payAppFailed = false
    @State private var confirmationMessage: String? = nil
    @State private var showTransactionHistory = false

    /// The product a UPI claim is for, picked in the Payment Claims
    /// tab. Situations is the default, matching the previous
    /// single-product behaviour.
    @State private var selectedClaimProductID = PaymentConfig.situationsProductID

    /// The product the current UPI claim is for.
    private var selectedClaimProduct: CourseProduct {
        PaymentConfig.product(for: selectedClaimProductID) ?? PaymentConfig.product(for: PaymentConfig.situationsProductID)!
    }

    /// The claim on screen, only when it is for the selected product.
    /// A claim for another product is never shown under this
    /// product's name.
    private var claimForSelectedProduct: UPIClaim? {
        guard let claim = storeManager.upiClaim,
              claim.productID == selectedClaimProductID else { return nil }
        return claim
    }

    private var canSubmit: Bool {
        !payerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !utr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let claimDateFormatter: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    private func formattedClaimDate(_ isoString: String) -> String {
        guard let date = Self.claimDateFormatter.date(from: isoString) else {
            return isoString
        }
        return Self.displayDateFormatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Purchases", selection: $selectedTab) {
                    ForEach(PurchasesTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, PFSpacing.lg)
                .padding(.top, PFSpacing.md)
                .padding(.bottom, PFSpacing.sm)

                ScrollView {
                    VStack(alignment: .leading, spacing: PFSpacing.xl) {
                        if selectedTab == .myPurchases {
                            myPurchasesTab
                        } else {
                            paymentClaimsTab
                        }
                        footerNote
                    }
                    .padding(PFSpacing.lg)
                }
                .background(Color.pfBackground)
            }
            .background(Color.pfBackground)
            .navigationTitle("Purchases")
            .navigationBarTitleDisplayMode(.inline)
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
            productListSection
            actionRowsSection
            paymentMethodsSection
        }
    }

    // MARK: - Catalogue intro

    /// What buying means: one bundle unlocks only its own chapters,
    /// the Integrated Course unlocks everything, and Situations is
    /// a separate product.
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
                        Text("Buy a course to unlock its chapters. The Integrated Course unlocks everything.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: PFSpacing.sm)
                    PFPill(
                        text: storeManager.unlockedProductCount == PaymentConfig.products.count ? "All owned" : "\(storeManager.unlockedProductCount) of \(PaymentConfig.products.count) owned",
                        background: Color.pfSuccess.opacity(0.12),
                        foreground: .pfSuccess
                    )
                }
                Text("Each course is a one-time purchase, no subscription. Payment Situations is a separate product: only its buyers, and Integrated Course buyers, can open the 564 situations.")
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Product list

    private var productListSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "All courses")
            ForEach(PaymentConfig.products) { course in
                productCard(for: course)
            }
        }
    }

    /// One buyable product: name, short description, contents, price,
    /// and a Buy button, or an Owned pill when it is already unlocked.
    /// The price comes from the App Store product when loaded,
    /// otherwise from PaymentConfig.
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
                    Text(storeManager.priceText(for: course.productID))
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                }
                if course.productID == PaymentConfig.fullCourseProductID {
                    Text("Unlocks all 100 chapters and all 564 situations.")
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
                    // price comes from the App Store product; while
                    // there is no App Store Connect product yet it
                    // comes from the local PaymentForge.storekit file.
                    // One-time purchase, no subscription.
                    PFGoldButton(title: storeManager.isBusy ? "Please wait..." : "Buy for \(storeManager.priceText(for: course.productID))") {
                        Task { await storeManager.purchase(productID: course.productID) }
                    }
                    .disabled(storeManager.isBusy)
                    .opacity(storeManager.isBusy ? 0.5 : 1)
                    Text("Pay securely with your Apple ID, the same way you pay in any App Store app. No account needed. You can also pay by UPI from the Payment Claims tab.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func unlockedNote(for course: CourseProduct) -> String {
        if course.productID == PaymentConfig.fullCourseProductID {
            return "Everything is unlocked on this device."
        }
        if course.productID == PaymentConfig.situationsProductID {
            return "Payment Situations is unlocked on this device."
        }
        return "\(course.name) is unlocked on this device."
    }

    /// Final Assessment entry for an owned course: the certificate
    /// when earned, attempts left when open, or a locked note when
    /// all 3 attempts were used without a pass. Situations has no
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
    /// honest empty state when there is none. UPI claims are not App
    /// Store transactions; they are listed under Payment Claims.
    private var actionRowsSection: some View {
        PFCard {
            VStack(spacing: 0) {
                actionRowButton(
                    icon: "arrow.counterclockwise.circle.fill",
                    title: "Restore Purchases",
                    subtitle: "Already bought it on another iPhone or after reinstalling? Restore it with the same Apple ID. No account needed."
                ) {
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
                if storeManager.isProductUnlocked(PaymentConfig.fullCourseProductID) {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "crown.fill")
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("The Integrated Course")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            Text("You own everything: all 100 chapters and all 564 situations.")
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
                        subtitle: "Unlock everything, all 100 chapters and all 564 situations, for \(storeManager.priceText(for: PaymentConfig.fullCourseProductID)), one-time payment."
                    ) {
                        Task { await storeManager.purchase(productID: PaymentConfig.fullCourseProductID) }
                    }
                    .disabled(storeManager.isBusy)
                }
            }
        }
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
    /// there are none, an honest empty state, never a fake list.
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
                            Text("No App Store purchase has been made on this Apple ID yet. UPI claims are listed under Payment Claims.")
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
                                    Text(PaymentConfig.product(for: transaction.productID)?.name ?? transaction.productID)
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                    Text("App Store, \(storeManager.priceText(for: transaction.productID))")
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

    /// Payment methods audit: only Apple In-App Purchase and UPI
    /// (by claim) work. Card, Net banking and Wallet are not switched
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
                        note: "Pay with your Apple ID. Courses from Rs. 999 to Rs. 9,999.",
                        state: "Available",
                        available: true
                    )
                    Divider()
                    paymentMethodRow(
                        icon: "indianrupeesign.circle.fill",
                        name: "UPI",
                        note: "Pay by UPI, then submit your UTR. Claims need manual verification.",
                        state: "Claim",
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

    // MARK: - Payment Claims tab (UPI)

    private var paymentClaimsTab: some View {
        VStack(alignment: .leading, spacing: PFSpacing.xl) {
            claimProductPicker
            claimStatusCard
            payByUPICard
            submitUTRCard
        }
        .task(id: selectedClaimProductID) {
            await storeManager.refreshUPIClaimStatus(for: selectedClaimProductID)
        }
    }

    /// Pick which product the UPI payment is for. The claim, the
    /// amount and the UPI deep link below all follow this choice.
    private var claimProductPicker: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Product")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Picker("Product", selection: $selectedClaimProductID) {
                        ForEach(PaymentConfig.products) { course in
                            Text("\(course.name), \(course.priceText)").tag(course.productID)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(selectedClaimProduct.tagline)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if storeManager.isProductUnlocked(selectedClaimProductID) {
                        Text("\(selectedClaimProduct.name) is already unlocked on this device.")
                            .font(.pfBody)
                            .foregroundColor(.pfSuccess)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var claimStatus: UPIClaimStatus? {
        claimForSelectedProduct?.status
    }

    private var claimStatusCard: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Claim status")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    if let claim = claimForSelectedProduct, let status = claimStatus {
                        HStack(spacing: PFSpacing.md) {
                            PFIconTile(systemImage: statusIcon(for: status))
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text("UPI claim \(status.rawValue.lowercased())")
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                Text(statusExplanation(for: status))
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: PFSpacing.sm)
                            claimStatusPill(status)
                        }
                        Divider()
                        detailRow(label: "Product", value: selectedClaimProduct.name)
                        detailRow(label: "Name", value: claim.payerName)
                        detailRow(label: "UTR", value: claim.utr)
                        detailRow(label: "Amount", value: storeManager.priceText(for: selectedClaimProductID))
                        detailRow(label: "Submitted", value: formattedClaimDate(claim.submittedAt))
                    } else {
                        HStack(spacing: PFSpacing.md) {
                            PFIconTile(systemImage: "doc.text.fill")
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text("No claim submitted yet")
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                Text("Pay \(storeManager.priceText(for: selectedClaimProductID)) by UPI below, then submit your UTR. Your claim will show as Pending until the payment is verified.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text("UPI claims are pending manual verification and do not unlock \(selectedClaimProduct.name) until verified. Submitting a UTR never unlocks access on its own.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(PFSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.pfGoldSoft)
                        .cornerRadius(PFSpacing.cardRadius)
                    PFSecondaryButton(title: "Refresh claim status") {
                        Task { await storeManager.refreshUPIClaimStatus(for: selectedClaimProductID) }
                    }
                    Text("Refresh checks the server for the latest verification status. Only a verified payment unlocks \(selectedClaimProduct.name).")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func statusIcon(for status: UPIClaimStatus) -> String {
        switch status {
        case .pending: return "clock.fill"
        case .verified: return "checkmark.seal.fill"
        case .rejected: return "xmark.seal.fill"
        }
    }

    private func statusExplanation(for status: UPIClaimStatus) -> String {
        switch status {
        case .pending:
            return "Your payment is waiting for manual verification. Access is granted after the payment is confirmed, usually within one working day."
        case .verified:
            return "Your UPI payment has been verified. \(selectedClaimProduct.name) is unlocked."
        case .rejected:
            return "This claim could not be verified. Check the UTR and submit it again, or buy with Apple In-App Purchase instead."
        }
    }

    private func claimStatusPill(_ status: UPIClaimStatus) -> some View {
        switch status {
        case .pending:
            return PFPill(text: "Pending", background: Color.pfGoldSoft, foreground: .pfGold)
        case .verified:
            return PFPill(text: "Verified", background: Color.pfSuccess.opacity(0.12), foreground: .pfSuccess)
        case .rejected:
            return PFPill(text: "Rejected", background: Color.pfError.opacity(0.12), foreground: .pfError)
        }
    }

    private var payByUPICard: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Pay by UPI")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("Pay to this UPI ID")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    HStack(alignment: .center, spacing: PFSpacing.md) {
                        Text(PaymentConfig.upiID)
                            .font(.pfSectionTitle.weight(.bold))
                            .foregroundColor(.pfNavy)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = PaymentConfig.upiID
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.pfRoyal)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: PFSpacing.md) {
                        Text("Amount")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                        Text(storeManager.priceText(for: selectedClaimProductID))
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Spacer(minLength: 0)
                        Text("One-time payment")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    }
                    PFPrimaryButton(title: "Pay \(storeManager.priceText(for: selectedClaimProductID)) with a UPI app") {
                        openUPIApp()
                    }
                    if payAppFailed {
                        Text("No UPI app opened automatically. Open your UPI app and pay \(storeManager.priceText(for: selectedClaimProductID)) to \(PaymentConfig.upiID), then submit your UTR below.")
                            .font(.pfBody)
                            .foregroundColor(.pfError)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if payAppOpened {
                        Text("Your UPI app should now be open. After paying, come back here and submit your UTR below.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Pay \(storeManager.priceText(for: selectedClaimProductID)) to this UPI ID from any UPI app, then submit your UTR below for manual verification.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func openUPIApp() {
        guard let url = PaymentConfig.upiPaymentURL(for: selectedClaimProductID) else {
            payAppFailed = true
            return
        }
        UIApplication.shared.open(url) { success in
            payAppOpened = success
            payAppFailed = !success
        }
    }

    private var submitUTRCard: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Submit your UTR")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("Your name")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    TextField("Name used for the payment", text: $payerName)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                    Text("UTR (transaction reference)")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    TextField("For example, 123456789012", text: $utr)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.none)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    PFPrimaryButton(title: "Submit UTR for verification") {
                        submitClaim()
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)
                    if let confirmationMessage {
                        Text(confirmationMessage)
                            .font(.pfBody)
                            .foregroundColor(.pfSuccess)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Submitting a UTR records a claim for manual verification. It does not unlock \(selectedClaimProduct.name). Access is granted only after the payment is verified.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func submitClaim() {
        let name = payerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = utr.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await storeManager.submitUPIClaim(productID: selectedClaimProductID, payerName: name, utr: reference)
            let pendingUpload = storeManager.hasPendingClaimUpload
            if pendingUpload {
                confirmationMessage = "Thank you. Your UTR is recorded as Pending, but it has not been sent yet. Sign in so it can be sent for verification. Access is granted only after the payment is confirmed."
            } else {
                confirmationMessage = "Thank you. Your UTR has been recorded as Pending verification. Access is granted only after the payment is confirmed, usually within one working day."
            }
        }
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("No account is needed. Purchases are tied to your Apple ID, and progress stays on this device. If you have questions, email debarghya.092008@gmail.com.")
            .font(.pfBody)
            .foregroundColor(.pfSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
