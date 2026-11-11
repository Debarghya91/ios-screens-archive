// DesignSystem.swift
// PaymentForge iOS - Shared design language.
// Royal blue is the single primary, premium gold sparingly for the main call
// to action and highlights, deep executive navy for headings and authority.
// No em dashes in any user-facing text.

import SwiftUI

// MARK: - Colors

extension Color {
    /// Royal blue, the single primary color.
    static let pfRoyal = Color(red: 0.09, green: 0.25, blue: 0.55)
    /// A lighter royal blue for secondary accents and selected states.
    static let pfRoyalLight = Color(red: 0.16, green: 0.36, blue: 0.68)
    /// Premium gold, used sparingly for the main call to action and highlights.
    static let pfGold = Color(red: 0.79, green: 0.64, blue: 0.15)
    /// A soft gold tint for backgrounds behind gold highlights.
    static let pfGoldSoft = Color(red: 0.79, green: 0.64, blue: 0.15).opacity(0.12)
    /// Deep executive navy for headings and authority.
    static let pfNavy = Color(red: 0.05, green: 0.11, blue: 0.22)
    /// Deepest navy, the top of the hero gradient.
    static let pfNavyDeep = Color(red: 0.02, green: 0.06, blue: 0.14)
    /// Soft navy for card backgrounds on light screens.
    static let pfNavySoft = Color(red: 0.05, green: 0.11, blue: 0.22).opacity(0.06)
    /// Warm off-white page background.
    static let pfBackground = Color(red: 0.96, green: 0.97, blue: 0.98)
    /// Card background.
    static let pfCard = Color.white
    /// Hairline border for cards and fields.
    static let pfBorder = Color(red: 0.91, green: 0.93, blue: 0.96)
    /// Secondary text. Darkened in Phase 7 (was 0.39/0.45/0.55,
    /// about 4.5:1 on white) so body-adjacent secondary text reads
    /// at roughly 7:1 on white and on pfBackground in light mode.
    /// The app's pf surfaces stay light even when the dark-mode
    /// toggle is on (pfCard is white, pfBackground is off-white),
    /// so this darker value is also what dark mode shows.
    static let pfSecondaryText = Color(red: 0.28, green: 0.34, blue: 0.43)
    /// Success green for correct quiz answers and completed states.
    static let pfSuccess = Color(red: 0.13, green: 0.55, blue: 0.32)
    /// Error red for incorrect quiz answers.
    static let pfError = Color(red: 0.78, green: 0.20, blue: 0.22)
}

// MARK: - Gradients

extension Color {
    /// Hero gradient: deepest navy at the top, through navy, to royal
    /// blue at the bottom. White text sits on it. Gradients are used
    /// ONLY on the hero and premium sections, never on every card.
    static var pfHeroGradient: LinearGradient {
        LinearGradient(
            colors: [.pfNavyDeep, .pfNavy, .pfRoyal],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Text-size scaling for the "Larger text" appearance setting.
/// The toggle in AppearanceSettingsView writes the key below via
/// @AppStorage("pf.appearance.largerText"). These helpers read that same
/// key directly from UserDefaults, so every font below scales by 1.2x
/// when the setting is on and stays at its base size when it is off.
/// The fonts are computed at each read, so any view whose body is
/// re-evaluated after the setting changes picks up the new size.
private enum PFFontScale {
    /// The exact UserDefaults key the Appearance toggle writes. Do not
    /// rename it: the toggle and these helpers must stay in sync.
    static let largerTextKey = "pf.appearance.largerText"

    /// 1.2 when larger text is on, 1.0 when it is off.
    static var factor: CGFloat {
        UserDefaults.standard.bool(forKey: largerTextKey) ? 1.2 : 1.0
    }

    /// True when the "Larger text" appearance setting is on. The
    /// semantic pf fonts step up one text style when this is true.
    static var largerText: Bool {
        UserDefaults.standard.bool(forKey: largerTextKey)
    }

    static func scaled(_ base: CGFloat) -> CGFloat {
        base * factor
    }
}

extension Notification.Name {
    /// Posted by AppearanceSettingsView when the larger-text setting
    /// changes. Views that observe it can rebuild and re-read the
    /// scaled fonts immediately.
    static let pfLargerTextChanged = Notification.Name("pf.largerTextChanged")
}

extension Font {
    // Semantic text styles, so Dynamic Type scales every label and
    // nothing clips at larger sizes. The "Larger text" appearance
    // setting steps each style up one size instead of multiplying a
    // fixed point size, which would not scale with Dynamic Type.
    // Contrast: pfNavy body text on white/pfBackground, and white
    // text only on pfNavy/pfRoyal, both meet contrast; pfGold is
    // never used for body text, only for large icons and accents
    // on navy, where its large size keeps it legible.
    static var pfHeroTitle: Font {
        .system(PFFontScale.largerText ? .largeTitle : .title, design: .default).weight(.bold)
    }
    static var pfScreenTitle: Font {
        .system(PFFontScale.largerText ? .title : .title2, design: .default).weight(.bold)
    }
    static var pfSectionTitle: Font {
        .system(PFFontScale.largerText ? .title2 : .title3, design: .default).weight(.semibold)
    }
    static var pfCardTitle: Font {
        .system(PFFontScale.largerText ? .title3 : .headline, design: .default).weight(.semibold)
    }
    static var pfBody: Font {
        .system(PFFontScale.largerText ? .title3 : .body, design: .default).weight(.regular)
    }
    static var pfCallout: Font {
        .system(PFFontScale.largerText ? .body : .callout, design: .default).weight(.regular)
    }
    static var pfCaption: Font {
        .system(PFFontScale.largerText ? .callout : .caption, design: .default).weight(.regular)
    }
    static var pfCaptionBold: Font {
        .system(PFFontScale.largerText ? .callout : .caption, design: .default).weight(.semibold)
    }
}

// MARK: - Spacing

enum PFSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let cornerRadius: CGFloat = 14
    static let cardRadius: CGFloat = 18
}

// MARK: - Reusable components

/// The primary gold call-to-action button.
struct PFPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.pfCardTitle)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.pfRoyal)
                .cornerRadius(PFSpacing.cornerRadius)
                .shadow(color: Color.pfRoyal.opacity(0.35), radius: 10, x: 0, y: 4)
        }
    }
}

/// A gold accent button, used sparingly for the single main call to action.
struct PFGoldButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.pfCardTitle)
                .foregroundColor(.pfNavy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.pfGold)
                .cornerRadius(PFSpacing.cornerRadius)
                .shadow(color: Color.pfGold.opacity(0.45), radius: 10, x: 0, y: 4)
        }
    }
}

/// A secondary outline button.
struct PFSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.pfBody).fontWeight(.semibold)
                .foregroundColor(.pfRoyal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.pfRoyal.opacity(0.08))
                .cornerRadius(PFSpacing.cornerRadius)
        }
    }
}

/// A small pill badge, for example for a lesson type or a level.
struct PFPill: View {
    let text: String
    var background: Color = Color.pfRoyal.opacity(0.10)
    var foreground: Color = Color.pfRoyal

    var body: some View {
        Text(text)
            .font(.pfCaptionBold)
            .foregroundColor(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(background)
            .clipShape(Capsule())
    }
}

/// A section header with a title and an optional trailing link.
struct PFSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.pfCallout).fontWeight(.semibold)
                    .foregroundColor(.pfRoyal)
            }
        }
    }
}

/// A card container with the standard look: white, rounded, a hairline
/// border and a layered shadow so it lifts off the page.
struct PFCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(PFSpacing.lg)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                    .stroke(Color.pfBorder, lineWidth: 1)
            )
            .shadow(color: Color.pfNavy.opacity(0.10), radius: 16, x: 0, y: 8)
            .shadow(color: Color.pfNavy.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

/// A coloured icon tile: a rounded square with a soft light-blue
/// background and a royal SF Symbol. Used at the leading edge of
/// rows so a list reads as designed cards, not plain text. No
/// gradient here: gradients are reserved for the hero and premium
/// sections.
struct PFIconTile: View {
    let systemImage: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundColor(.pfRoyal)
            .frame(width: size, height: size)
            .background(Color.pfRoyal.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
            // Decorative tile: VoiceOver reads the row's own label.
            .accessibilityHidden(true)
    }
}

/// A button style that gives cards a subtle press: the card shrinks
/// to 0.98 while pressed, then springs back. Applied to card
/// NavigationLinks so the app feels responsive.
struct PFCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A thin progress bar used for course and weekly goal progress.
/// The fill is a royal gradient with a soft glow, so progress reads
/// as a designed element, not a default control.
struct PFProgressBar: View {
    var progress: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.pfNavy.opacity(0.10))
                    .frame(height: height)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.pfRoyal)
                    .frame(width: max(0, min(1, progress)) * geometry.size.width, height: height)
                    .shadow(color: Color.pfRoyal.opacity(0.35), radius: 4, x: 0, y: 1)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress, \(Int((max(0, min(1, progress)) * 100).rounded())) percent")
        .accessibilityValue("\(Int((max(0, min(1, progress)) * 100).rounded())) percent complete")
    }
}

// MARK: - Home, Courses and Dashboard components

/// A circular progress ring with a % label in the centre. Royal blue
/// arc on a light track; pass .pfGold for achievements such as the
/// weekly goal ring.
struct PFProgressRing: View {
    var progress: Double
    var size: CGFloat = 120
    var lineWidth: CGFloat = 10
    var color: Color = .pfRoyal

    private var clamped: Double { max(0, min(1, progress)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.pfNavy.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((clamped * 100).rounded()))%")
                .font(.system(.title3, design: .default).weight(.bold))
                .foregroundColor(.pfNavy)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(Int((clamped * 100).rounded())) percent complete")
    }
}

/// A selectable chip for filters and interests. Selected is a royal
/// blue fill with white text; unselected is white with a hairline border.
struct PFChip: View {
    let text: String
    var isSelected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.pfCaptionBold)
                .foregroundColor(isSelected ? .white : .pfNavy)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.pfRoyal : Color.pfCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.pfRoyal : Color.pfBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// A level pill for a learning pathway. Foundation reads royal,
/// Intermediate reads gold, Advanced reads navy.
struct PFLevelPill: View {
    let text: String

    private var colors: (background: Color, foreground: Color) {
        switch text.lowercased() {
        case "foundation":
            return (Color.pfRoyal.opacity(0.10), .pfRoyal)
        case "intermediate":
            return (Color.pfGoldSoft, .pfNavy)
        case "advanced":
            return (Color.pfNavy.opacity(0.08), .pfNavy)
        default:
            return (Color.pfRoyal.opacity(0.10), .pfRoyal)
        }
    }

    var body: some View {
        Text(text)
            .font(.pfCaptionBold)
            .foregroundColor(colors.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(colors.background)
            .clipShape(Capsule())
    }
}

/// A stat card: an icon tile, a big number and a label, with an
/// optional small caption underneath (for example an honest note
/// about how the number was calculated).
struct PFStatCard: View {
    let value: String
    let label: String
    let systemImage: String
    var caption: String? = nil

    var body: some View {
        VStack(spacing: PFSpacing.xs) {
            PFIconTile(systemImage: systemImage, size: 40)
            Text(value)
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let caption {
                Text(caption)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PFSpacing.md)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
        .shadow(color: Color.pfNavy.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

/// A simple 7-bar chart for Mon-Sun activity. Royal bars; today is
/// the full royal bar while the other days are a lighter royal, and
/// the today label is bold royal. Values are counts, so a zero value
/// draws a minimal bar, never a fabricated height.
struct PFWeeklyBarChart: View {
    var values: [Double]
    var labels: [String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Index of today in a Monday-first week. Calendar weekday is
    /// Sunday 1 through Saturday 7, so shift by 5 and wrap.
    private var todayIndex: Int {
        (Calendar.current.component(.weekday, from: Date()) + 5) % 7
    }

    private var maxValue: Double { max(values.max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: PFSpacing.sm) {
            ForEach(0..<7, id: \.self) { index in
                let value = index < values.count ? values[index] : 0
                VStack(spacing: PFSpacing.xs) {
                    Text(value > 0 ? "\(Int(value))" : " ")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index == todayIndex ? Color.pfRoyal : Color.pfRoyal.opacity(0.30))
                        .frame(height: max(6, CGFloat(value / maxValue) * 96))
                    Text(index < labels.count ? labels[index] : "")
                        .font(.pfCaption)
                        .fontWeight(index == todayIndex ? .semibold : .regular)
                        .foregroundColor(index == todayIndex ? .pfRoyal : .pfSecondaryText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly activity, \(Int(values.reduce(0, +))) learning actions in the last 7 days")
    }
}

// MARK: - Loading, empty and error states

/// A shimmer-free skeleton row: a pulsing rounded bar, used while a
/// list is loading so the screen never shows a blank white page.
/// The pulse is a simple opacity animation, no decorative effect.
struct PFSkeletonView: View {
    var height: CGFloat = 76
    @State private var pulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
            .fill(Color.pfNavy.opacity(0.08))
            .frame(height: height)
            .opacity(pulsing ? 0.55 : 1.0)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
            .accessibilityLabel("Loading")
    }
}

/// A loading row: spinner plus a message, for screens whose content
/// is still arriving.
struct PFLoadingView: View {
    let message: String

    var body: some View {
        HStack(spacing: PFSpacing.sm) {
            ProgressView()
            Text(message)
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(message)
    }
}

/// An empty state: icon, title, honest message and one real action.
/// Never used to hide a missing feature; the action always goes
/// somewhere that exists.
struct PFEmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        PFCard {
            VStack(alignment: .center, spacing: PFSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(.title, design: .default))
                    .foregroundColor(.pfRoyal)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    PFPrimaryButton(title: actionTitle, action: action)
                        .padding(.top, PFSpacing.sm)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A small offline banner shown when a screen is displaying cached
/// content because the live fetch failed. Never a blank screen: the
/// cached content stays visible underneath, with this note on top.
struct PFOfflineBanner: View {
    var body: some View {
        HStack(spacing: PFSpacing.sm) {
            Image(systemName: "wifi.slash")
                .foregroundColor(.pfNavy)
                .accessibilityHidden(true)
            Text("You are offline. Showing saved content.")
                .font(.pfCaptionBold)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PFSpacing.md)
        .padding(.vertical, PFSpacing.sm)
        .background(Color.pfGoldSoft)
        .cornerRadius(PFSpacing.cornerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You are offline. Showing saved content.")
    }
}

/// An error state: icon, title, the real error text and a retry
/// button that calls the supplied action.
struct PFErrorStateView: View {
    let title: String
    let message: String
    let retryTitle: String
    let onRetry: () -> Void

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text(message)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFPrimaryButton(title: retryTitle, action: onRetry)
            }
        }
    }
}
