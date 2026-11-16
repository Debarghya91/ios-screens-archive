// DesignSystem.swift
// Payments Training Hub iOS - Shared design language.
// Royal blue is the single primary, premium gold sparingly for the main call
// to action and highlights, deep executive navy for headings and authority.
// No em dashes in any user-facing text.

import SwiftUI
import WebKit
import os

/// Diagnostics for thumbnail loading. Thumbnail failures are
/// otherwise silent: a failed raster load shows the placeholder
/// tile and a failed SVG load showed a blank frame, with nothing
/// recorded anywhere. These logs make a failure diagnosable in
/// Console without changing what the learner sees, beyond the
/// fallback tile. Each thumbnail view loads independently: there
/// is no shared thumbnail store, cache, or lock, so one failed
/// fetch can never poison the others or block a row.
enum PFThumbnailLog {
    static let logger = Logger(subsystem: "PaymentsTrainingHub", category: "Thumbnails")
}

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
    /// A darker gold for small text on light backgrounds, for example
    /// the text inside a gold-soft pill. pfGold itself is only for
    /// large icons and accents, never for small text: at caption size
    /// on white it does not read clearly. Use this colour wherever a
    /// pill or label needs gold text on a light surface.
    static let pfGoldText = Color(red: 0.55, green: 0.44, blue: 0.08)
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
    /// Secondary text. Darkened (was 0.39/0.45/0.55,
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
/// @AppStorage("pf.appearance.largerText"). The semantic pf fonts
/// below read that same key and step each style up one Dynamic Type
/// size when the setting is on (for example body becomes title3).
/// The fonts stay semantic text styles, so they still scale with
/// the system Dynamic Type setting as well. The fonts are computed
/// at each read, so any view whose body is re-evaluated after the
/// setting changes picks up the new size.
private enum PFFontScale {
    /// The exact UserDefaults key the Appearance toggle writes. Do not
    /// rename it: the toggle and these helpers must stay in sync.
    /// Deliberately NOT namespaced per account (see
    /// AccountScopedStorage): larger text is a device-level display
    /// preference, not personal learning data. It holds no account
    /// information, it is shared by everyone using this device, and
    /// the toggle in SideDrawerView reads and writes this same raw
    /// key through @AppStorage. Namespacing the read here without
    /// namespacing that toggle would break the setting outright.
    static let largerTextKey = "pf.appearance.largerText"

    /// True when the "Larger text" appearance setting is on. The
    /// semantic pf fonts step up one text style when this is true.
    static var largerText: Bool {
        UserDefaults.standard.bool(forKey: largerTextKey)
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

/// The one spacing scale. Layout spacing uses xs (4), sm (8), md (12),
/// lg (16), xl (24) and xxl (32) only. Corner radii have three roles:
/// cardRadius (18) for cards, cornerRadius (14) for buttons, pills and
/// fields, and smallRadius (12) for small tiles and pressed-row
/// backgrounds. Values outside this scale are local to one component
/// (for example the weekly chart bars) and are not a second scale.
enum PFSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let cornerRadius: CGFloat = 14
    static let cardRadius: CGFloat = 18
    static let smallRadius: CGFloat = 12
    /// Bottom clearance above the floating tab bar pill, for
    /// scrollable lists under the tabs. This is not part of the
    /// xs to xxl layout scale: it is a clearance, like the radii
    /// above. The value is the LessonView bottom padding that
    /// already kept lesson content clear of the pill: the pill
    /// is about 63pt tall and sits about 21pt above the screen
    /// bottom, so its top is about 84pt above the bottom edge,
    /// and 112pt clears it with breathing room even where the
    /// system safe area does not cover the pill. Every tab root
    /// and pushed list uses this one value through
    /// pfTabBarClearance(), never a local spacer height.
    static let tabBarClearance: CGFloat = 112
}

// MARK: - Reusable components

/// Pressed feedback for the shared buttons: the button dims slightly
/// while pressed. No animation and no scale, so it stays correct
/// when Reduce Motion is on.
private struct PFPressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

/// The primary royal-blue call-to-action button. Pass isEnabled false
/// to show the action as unavailable instead of hiding the button;
/// a disabled button is dimmed and does not respond to taps.
struct PFPrimaryButton: View {
    let title: String
    let action: () -> Void
    var isEnabled: Bool = true

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
        .buttonStyle(PFPressedButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}

/// A gold accent button, used sparingly for the single main call to action.
/// Pass isEnabled false to show the action as unavailable instead of
/// hiding the button.
struct PFGoldButton: View {
    let title: String
    let action: () -> Void
    var isEnabled: Bool = true

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
        .buttonStyle(PFPressedButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}

/// A secondary outline button. Same 14-point vertical padding as the
/// primary and gold buttons, so the three read at the same height
/// when placed next to each other. Pass isEnabled false to show the
/// action as unavailable instead of hiding the button.
struct PFSecondaryButton: View {
    let title: String
    let action: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.pfBody).fontWeight(.semibold)
                .foregroundColor(.pfRoyal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.pfRoyal.opacity(0.08))
                .cornerRadius(PFSpacing.cornerRadius)
        }
        .buttonStyle(PFPressedButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
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
                    // Short actions such as "Show all" still get a
                    // full 44-point tap height.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
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
/// NavigationLinks so the app feels responsive. The scale change is
/// instant when Reduce Motion is on.
struct PFCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PFCardPressEffect(isPressed: configuration.isPressed, content: configuration.label)
    }
}

/// The press effect for PFCardButtonStyle, as a view so it can read
/// the Reduce Motion setting, which a button style cannot read
/// directly.
private struct PFCardPressEffect<Content: View>: View {
    let isPressed: Bool
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isPressed)
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
        .accessibilityLabel("Progress")
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
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
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

    /// The VoiceOver announcement: the week total plus every day's
    /// count, so the per-day values are available without sight. The
    /// visual chart shows a blank space for a zero day; the spoken
    /// version says the zero out loud.
    private var accessibilityDescription: String {
        let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let parts = (0..<7).map { index in
            let value = index < values.count ? Int(values[index]) : 0
            return "\(dayNames[index]) \(value)"
        }
        return "Weekly activity, \(Int(values.reduce(0, +))) learning actions in the last 7 days. \(parts.joined(separator: ", "))"
    }

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
        .accessibilityLabel(accessibilityDescription)
    }
}

// MARK: - Loading, empty and error states

/// A shimmer-free skeleton row: a pulsing rounded bar, used while a
/// list is loading so the screen never shows a blank white page.
/// The pulse is a simple opacity animation, no decorative effect.
/// With Reduce Motion on, the bar stays still at full opacity.
struct PFSkeletonView: View {
    var height: CGFloat = 76
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
            .fill(Color.pfNavy.opacity(0.08))
            .frame(height: height)
            .opacity(pulsing ? 0.55 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = !reduceMotion }
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

// MARK: - Accessibility helpers (navigation and search)
//
// Additive only. These helpers are used by the navigation,
// search and accessibility work. They change no existing token,
// colour, font, spacing value or component behaviour, and no
// existing component is modified to use them.

extension View {
    /// Enforces the 44pt minimum touch target: the view grows to
    /// at least 44 by 44pt in layout, with the full rectangle
    /// tappable, so a small icon or text button gains a full-size
    /// tap area. Use on small icon and text buttons whose content
    /// is smaller than 44pt, for example the search clear button,
    /// the bookmark toggle and the filter chips. Do not use on
    /// views that already meet 44pt.
    func pfMinimumTouchTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    /// Marks a decorative view as hidden from assistive technology:
    /// an icon or chevron whose meaning is already carried by
    /// adjacent text or by an explicit accessibility label on the
    /// containing control. Never use on an icon that is the only
    /// carrier of meaning: label that control instead.
    func pfDecorative() -> some View {
        accessibilityHidden(true)
    }

    /// Bottom clearance above the floating tab bar pill, for a
    /// ScrollView or List that scrolls under the tabs. Adds a
    /// clear safe area inset of PFSpacing.tabBarClearance, so
    /// the last row can scroll fully above the pill on every
    /// iPhone size. Use on every tab root list and on pushed
    /// lists where the tab bar stays visible; do not use in
    /// sheets or full screen covers, where there is no tab bar
    /// to clear. The spacer never intercepts a tap: Color.clear
    /// hit tests by default, so the strip is marked
    /// non-interactive, the ProfileView lesson applied app-wide.
    /// One shared modifier, so the clearance can never drift
    /// between tabs again: the 24pt local spacers it replaces
    /// let bottom rows slide under the pill.
    func pfTabBarClearance() -> some View {
        safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: PFSpacing.tabBarClearance)
                .allowsHitTesting(false)
        }
    }

    /// Scroll-to-top on every entry (the owner scroll rule):
    /// every scrollable screen opens at the very top on every
    /// entry, Back lands at the top too, and no scroll position
    /// is ever restored. SwiftUI keeps a pushed view's
    /// ScrollView offset alive across a push/pop and across tab
    /// switches, so without this the learner returns mid-page.
    /// Wraps the ScrollView in a ScrollViewReader and scrolls
    /// to the caller's top anchor (an .id on the first content
    /// element, or on the content container) on appear, without
    /// animation, dispatched async so the scroll lands after
    /// layout. Apply to the ScrollView itself: the reader must
    /// be an ancestor of the ScrollView it scrolls.
    func pfScrollToTopOnAppear(_ anchor: String) -> some View {
        modifier(PFScrollToTopModifier(anchor: anchor, resetToken: 0))
    }

    /// Scroll-to-top on every entry, plus whenever in-place
    /// content changes: the reset token re-runs the same scroll
    /// when a filter, step, question, segment or stage swaps
    /// the content inside one ScrollView, so swapped content
    /// also starts at the top. The token must change exactly
    /// when the content changes: a filter value, a question
    /// index, a step raw value, or a tuple of such values.
    func pfScrollToTopOnAppear<Value: Equatable>(_ anchor: String, resetWhen value: Value) -> some View {
        modifier(PFScrollToTopModifier(anchor: anchor, resetToken: value))
    }
}

/// The scroll-rule mechanism behind pfScrollToTopOnAppear: a
/// ScrollViewReader around the ScrollView, scrolling to the top
/// anchor on appear and whenever the reset token changes.
struct PFScrollToTopModifier<Value: Equatable>: ViewModifier {
    let anchor: String
    let resetToken: Value

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onAppear { scrollToTop(proxy) }
                .onChange(of: resetToken) { _, _ in scrollToTop(proxy) }
        }
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }
}

// MARK: - Long-form body text
//
// One shared paragraph renderer for long text: lesson bodies,
// situations, scenarios, insights, FAQ answers, interview
// answers, test and assessment explanations, studio briefs,
// descriptions and help text. Long text renders as logical
// paragraphs with breathing room, never one wall of text, and
// the wording never changes: splitting only breaks text at
// line breaks and sentence boundaries. The splitting rule is
// the LessonView rule, shared: line breaks mark paragraph
// boundaries first, then a long block splits into sentence
// groups of at most three sentences (about 480 characters).
// Short text renders as a single Text, exactly as before, so
// adopting this renderer is safe for short copy too. The
// Studio's local StudioParagraphsView already uses these same
// metrics (md paragraph spacing, 4pt line spacing) for its
// array-paragraph content and is left unchanged.

// MARK: - Guarded navigation

/// One shared navigation debouncer: a second tap on the same
/// destination within half a second is ignored, so a rapid double
/// tap never pushes the same screen twice. The key is the
/// destination identity (a content id or a unique row title), so
/// tapping two different rows in quick succession still works.
/// Main-actor confined: every check runs on the main thread, so
/// the check and the record cannot interleave.
@MainActor
final class PFNavigationDebouncer: ObservableObject {
    static let shared = PFNavigationDebouncer()
    private var lastKey: String?
    private var lastFire = Date.distantPast

    func allow(key: String) -> Bool {
        let now = Date()
        if key == lastKey, now.timeIntervalSince(lastFire) < 0.5 { return false }
        lastKey = key
        lastFire = now
        return true
    }
}

/// A NavigationLink that ignores double taps: the visible control
/// is a Button guarded by PFNavigationDebouncer, and the push
/// itself runs through a hidden link driven by isActive. Call
/// sites keep their existing buttonStyle on this wrapper: the
/// style propagates to the inner Button, so card rows keep their
/// press effect and text rows keep theirs. This gives the 500ms
/// debounce; true single-top (one destination instance per stack)
/// needs path-based stacks and is a larger refactor.
struct PFGuardedNavigationLink<Destination: View, Label: View>: View {
    let key: String
    let destination: Destination
    let label: Label
    @State private var isActive = false

    init(key: String, @ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.key = key
        self.destination = destination()
        self.label = label()
    }

    var body: some View {
        Button {
            guard PFNavigationDebouncer.shared.allow(key: key) else { return }
            isActive = true
        } label: { label }
        .background(
            NavigationLink(destination: destination, isActive: $isActive) { EmptyView() }
        )
    }
}

/// Splits long text into readable paragraphs without changing
/// any wording. Line breaks mark paragraph boundaries first; a
/// long block is then split into sentence groups (at most three
/// sentences, about 480 characters) so it never renders as one
/// wall of text. Sentence boundaries come from the system
/// sentence enumeration, so abbreviations and decimals do not
/// split sentences.
enum PFParagraphs {
    static func split(_ text: String) -> [String] {
        let blocks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var paragraphs: [String] = []
        for block in blocks {
            paragraphs.append(contentsOf: splitLongBlock(block))
        }
        return paragraphs
    }

    /// Split one long block into sentence groups. Short blocks
    /// come back unchanged.
    private static func splitLongBlock(_ block: String) -> [String] {
        var sentences: [String] = []
        block.enumerateSubstrings(in: block.startIndex..<block.endIndex, options: [.bySentences]) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        guard sentences.count > 3 || block.count > 480 else { return [block] }
        guard sentences.count > 1 else { return [block] }
        var chunks: [String] = []
        var current = ""
        var currentCount = 0
        for sentence in sentences {
            if !current.isEmpty && (currentCount >= 3 || current.count + 1 + sentence.count > 480) {
                chunks.append(current)
                current = ""
                currentCount = 0
            }
            current = current.isEmpty ? sentence : current + " " + sentence
            currentCount += 1
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

/// Renders long text as logical paragraphs: one Text per
/// paragraph, paragraph spacing from the design scale, and
/// comfortable line spacing. Defaults match the Studio and
/// Situations body text (body font, navy, 4pt line spacing,
/// md paragraph spacing); pass font, color or line spacing to
/// match a surface that already uses different values, for
/// example a callout quiz explanation or a secondary
/// description. Empty text renders nothing.
struct PFBodyText: View {
    let text: String
    var font: Font = .pfBody
    var textColor: Color = .pfNavy
    var lineSpacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            ForEach(Array(PFParagraphs.split(text).enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(font)
                    .foregroundColor(textColor)
                    .lineSpacing(lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Agenda block and thumbnails

/// The highlighted agenda block: the "why take it" line for a
/// lesson, chapter, course, or case, in a gold-tinted panel with
/// a gold leading bar so it reads as highlighted, not as body
/// text. Callers render it only when an agenda string exists;
/// there is no empty or placeholder state. Colours are the fixed
/// pf palette (navy text on a gold tint over white), identical
/// in light and dark mode, so the pairing stays legible in both.
struct PFAgendaBlock: View {
    let title: String
    let agenda: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Color.pfGold)
                .frame(width: 4)
                .cornerRadius(2)
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                // Navy title on the gold-tinted panel (15.38:1,
                // AAA): the gold leading bar and panel carry the
                // highlight identity. Gold text on the tint
                // measured 4.28:1, below AA for caption text.
                Text(title)
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(agenda)
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, PFSpacing.md)
            .padding(.leading, PFSpacing.md)
            .padding(.trailing, PFSpacing.md)
            Spacer(minLength: 0)
        }
        .background(Color.pfGoldSoft)
        .cornerRadius(PFSpacing.cornerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(agenda)")
    }
}

/// A thumbnail image beside a title, from a website thumbnail
/// path. Renders nothing when the path is nil, blank, or
/// unresolvable: the caller keeps its icon tile or badge in that
/// case. Raster images load through AsyncImage; SVG images (which
/// AsyncImage cannot render) load through a small non-interactive
/// WKWebView, the same rendering route LessonDiagramView uses
/// for lesson SVGs. While loading, or when a load fails, a
/// neutral tile holds the same frame, so the layout never jumps
/// and no broken image ever shows.
struct PFThumbnailView: View {
    let thumbnailPath: String?
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 12

    private var resolvedURL: URL? {
        PFThumbnailURL.resolve(thumbnailPath, base: ContentService.siteBase)
    }

    /// True when there is a thumbnail to show. Callers that swap
    /// an icon tile for the thumbnail check this first.
    var hasThumbnail: Bool {
        resolvedURL != nil
    }

    var body: some View {
        if let url = resolvedURL {
            Group {
                if PFThumbnailURL.isSVG(url) {
                    PFThumbnailSVGView(url: url)
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure, .empty:
                            thumbnailPlaceholder
                        @unknown default:
                            thumbnailPlaceholder
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
        }
    }

    /// The neutral tile shown while a raster thumbnail loads or
    /// when its load fails: same frame, no broken-image glyph.
    private var thumbnailPlaceholder: some View {
        ZStack {
            Color.pfRoyal.opacity(0.10)
            Image(systemName: "photo")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(.pfRoyal)
        }
        .frame(width: size, height: size)
    }
}

/// Renders one remote SVG thumbnail in a non-interactive web
/// view. The SVG loads as an <img> inside minimal wrapper HTML,
/// so it scales to the frame with object-fit cover and a
/// transparent background. Loads once per URL: updateUIView
/// reloads only when the URL changes, so list scrolling never
/// re-fetches the same thumbnail. A failed image load reports
/// through a script message handler (a subresource failure does
/// not reach WKNavigationDelegate), is logged for diagnosis,
/// and swaps in the neutral fallback tile, so a failed SVG
/// never leaves a blank frame. Each view owns its own web view
/// and handler: failures stay per thumbnail.
private struct PFThumbnailSVGView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(loadedURL: url)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "pfThumbnailFailed")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(Self.wrappedHTML(for: url), baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        context.coordinator.didShowFallback = false
        webView.loadHTMLString(Self.wrappedHTML(for: url), baseURL: nil)
    }

    static func wrappedHTML(for url: URL) -> String {
        let escaped = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
        html, body { margin: 0; padding: 0; background: transparent; }
        img { display: block; width: 100%; height: 100%; object-fit: cover; }
        </style>
        </head>
        <body><img src="\(escaped)" alt="" onerror="window.webkit.messageHandlers.pfThumbnailFailed.postMessage('failed')"></body>
        </html>
        """
    }

    /// The neutral tile shown when the SVG fails to load: the
    /// same royal tint as the raster placeholder, filling the
    /// frame, with no broken-image glyph.
    static func fallbackHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: rgba(23, 64, 140, 0.10); }
        </style>
        </head>
        <body></body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loadedURL: URL
        var didShowFallback = false

        init(loadedURL: URL) {
            self.loadedURL = loadedURL
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "pfThumbnailFailed",
                  let webView = message.webView,
                  !didShowFallback else { return }
            didShowFallback = true
            PFThumbnailLog.logger.error("Thumbnail failed to load: \(self.loadedURL.absoluteString, privacy: .public)")
            webView.loadHTMLString(PFThumbnailSVGView.fallbackHTML(), baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleNavigationFailure(webView: webView, error: error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleNavigationFailure(webView: webView, error: error)
        }

        private func handleNavigationFailure(webView: WKWebView, error: Error) {
            guard !didShowFallback else { return }
            didShowFallback = true
            PFThumbnailLog.logger.error("Thumbnail page failed to load: \(self.loadedURL.absoluteString, privacy: .public) \(error.localizedDescription, privacy: .public)")
            webView.loadHTMLString(PFThumbnailSVGView.fallbackHTML(), baseURL: nil)
        }
    }
}

// MARK: - Numbered pagination

/// One token in a pagination bar: a page number or an ellipsis gap.
enum PFPageItem: Hashable {
    case page(Int)
    case ellipsis
}

/// Pure pagination rules shared by Search and Payment Cases:
/// 20 items per page, numbered pages with Previous and Next, and
/// ellipsis gaps for long ranges, the way learning portals page.
/// Pure, so the rules are pinned by unit tests. No em dashes in
/// any user-facing text.
enum PFPagination {
    static let pageSize = 20

    /// Total pages for a list: 0 when the list is empty.
    static func totalPages(totalCount: Int, pageSize: Int = pageSize) -> Int {
        guard totalCount > 0 else { return 0 }
        return (totalCount + pageSize - 1) / pageSize
    }

    /// Clamp a requested page into 1...totalPages (1 when there
    /// are no pages, so callers never divide by zero).
    static func clampedPage(_ page: Int, totalPages: Int) -> Int {
        guard totalPages > 0 else { return 1 }
        return min(max(page, 1), totalPages)
    }

    /// The items on one page, in order. An out-of-range page
    /// clamps to the nearest real page; an empty list stays empty.
    static func slice<T>(_ items: [T], page: Int, pageSize: Int = pageSize) -> [T] {
        let total = totalPages(totalCount: items.count, pageSize: pageSize)
        let current = clampedPage(page, totalPages: total)
        let start = (current - 1) * pageSize
        guard start < items.count else { return [] }
        return Array(items[start..<min(start + pageSize, items.count)])
    }

    /// The 1-based first and last item numbers shown on one page:
    /// page 1 of 564 reads (1, 20), the last page reads (561, 564).
    /// (0, 0) when the list is empty.
    static func rangeBounds(page: Int, totalCount: Int, pageSize: Int = pageSize) -> (first: Int, last: Int) {
        guard totalCount > 0 else { return (0, 0) }
        let total = totalPages(totalCount: totalCount, pageSize: pageSize)
        let current = clampedPage(page, totalPages: total)
        let first = (current - 1) * pageSize + 1
        return (first, min(current * pageSize, totalCount))
    }

    /// The bar tokens for a page count and current page. Seven or
    /// fewer pages show every number. Longer ranges show the first
    /// page, the last page, and a window around the current page,
    /// with ellipsis gaps: 1 ... 6 7 8 ... 29. Near either end
    /// the window slides to the edge so a gap never hides exactly
    /// one page: 1 2 3 4 5 ... 29, never 1 ... 3.
    static func items(totalPages: Int, currentPage: Int) -> [PFPageItem] {
        guard totalPages > 0 else { return [] }
        let current = clampedPage(currentPage, totalPages: totalPages)
        if totalPages <= 7 {
            return (1...totalPages).map(PFPageItem.page)
        }
        let windowLow: Int
        let windowHigh: Int
        if current <= 4 {
            windowLow = 2
            windowHigh = 5
        } else if current >= totalPages - 3 {
            windowLow = totalPages - 4
            windowHigh = totalPages - 1
        } else {
            windowLow = current - 1
            windowHigh = current + 1
        }
        var tokens: [PFPageItem] = [.page(1)]
        if windowLow > 2 {
            tokens.append(.ellipsis)
        }
        for page in windowLow...windowHigh {
            tokens.append(.page(page))
        }
        if windowHigh < totalPages - 1 {
            tokens.append(.ellipsis)
        }
        tokens.append(.page(totalPages))
        return tokens
    }
}

/// The numbered pagination bar: Previous, page numbers, Next.
/// The current page is filled royal with white text; other pages
/// are bordered chips; gaps read as ellipsis. Previous is
/// disabled on page 1, Next on the last page. Compact enough for
/// phone widths: at most seven tokens between the two ends.
/// Tapping a number jumps straight to that page; the caller owns
/// the page state and the scroll back to the top.
struct PFPaginationBar: View {
    let currentPage: Int
    let totalPages: Int
    let onSelectPage: (Int) -> Void

    private var current: Int {
        PFPagination.clampedPage(currentPage, totalPages: totalPages)
    }

    var body: some View {
        HStack(spacing: PFSpacing.xs) {
            navButton(title: "Previous", enabled: current > 1) {
                onSelectPage(current - 1)
            }
            .accessibilityLabel("Previous page")
            ForEach(PFPagination.items(totalPages: totalPages, currentPage: current), id: \.self) { item in
                switch item {
                case .ellipsis:
                    Text("...")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                        .frame(minWidth: 20, minHeight: 44)
                        .accessibilityHidden(true)
                case .page(let number):
                    Button {
                        onSelectPage(number)
                    } label: {
                        Text("\(number)")
                            .font(.pfCaptionBold)
                            .foregroundColor(number == current ? .white : .pfNavy)
                            .frame(width: 34, height: 34)
                            .background(number == current ? Color.pfRoyal : Color.pfCard)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(number == current ? Color.pfRoyal : Color.pfBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 36, minHeight: 44)
                    .accessibilityLabel(number == current ? "Page \(number), current page" : "Page \(number)")
                }
            }
            navButton(title: "Next", enabled: current < totalPages) {
                onSelectPage(current + 1)
            }
            .accessibilityLabel("Next page")
        }
        .frame(maxWidth: .infinity)
    }

    private func navButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.pfCaptionBold)
                .foregroundColor(.pfRoyal)
                .padding(.horizontal, PFSpacing.sm)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
