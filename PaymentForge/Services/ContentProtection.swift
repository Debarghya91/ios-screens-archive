// ContentProtection.swift
// PaymentForge iOS - Copy protection for lesson content.
//
// Three layers, all local, no network calls and no keys:
//   1. Text selection off: lesson text cannot be selected, so the
//      long-press Copy menu never appears. This is the same
//      .textSelection(.disabled) approach FinalAssessmentView
//      already uses for exam questions.
//   2. Screen recording / mirroring guard: while the screen is being
//      recorded or mirrored (AirPlay), the content is blurred and a
//      notice is shown. It comes back the moment recording stops.
//      A single still screenshot cannot be intercepted on iOS (the
//      system only reports it after the image is taken), so the
//      watermark below is the trace for that case.
//   3. Faint diagonal watermark: the signed-in learner's email, or
//      "Payments Training Hub" for guests, repeated faintly across
//      the content, so a leaked copy traces back to an account.
//
// Apply with .pfProtectedContent() on a lesson content ScrollView.
// The watermark never intercepts touches, and the blur never blocks
// buttons: the audio keeps playing and the close button still works
// while recording is on. Text fields are never inside a protected
// ScrollView, so notes and search stay editable.

import SwiftUI
import Combine

// MARK: - Screen capture monitor

/// True while the screen is being recorded or mirrored to another
/// display. Observed from UIScreen.capturedDidChangeNotification;
/// the initial value is read live so a view opened mid-recording
/// starts hidden.
final class PFScreenCaptureMonitor: ObservableObject {
    static let shared = PFScreenCaptureMonitor()

    @Published private(set) var isCaptured: Bool = UIScreen.main.isCaptured

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(captureChanged),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
    }

    @objc private func captureChanged() {
        // The notification is posted on the main thread, but guard
        // anyway: the published value drives SwiftUI state.
        let captured = UIScreen.main.isCaptured
        if Thread.isMainThread {
            isCaptured = captured
        } else {
            DispatchQueue.main.async { self.isCaptured = captured }
        }
    }
}

// MARK: - Watermark text

/// The watermark string: the signed-in learner's email when there
/// is one, so a leaked copy traces back to an account; the product
/// name for guests.
enum PFWatermark {
    @MainActor
    static func text(for authService: AuthService) -> String {
        if let email = authService.currentUser?.email,
           !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return email
        }
        return "Payments Training Hub"
    }
}

/// Diagonal repeating watermark, faint enough not to hurt reading.
/// It never intercepts touches, so taps, buttons and scrolling all
/// pass straight through it.
struct PFWatermarkOverlay: View {
    @ObservedObject private var authService = AuthService.shared

    var body: some View {
        GeometryReader { geometry in
            let text = PFWatermark.text(for: authService)
            // Tiles sized for a long email address at 13pt; one extra
            // row and column each side so the rotated grid still
            // covers the corners.
            let tileWidth: CGFloat = 220
            let tileHeight: CGFloat = 110
            let columns = max(1, Int(geometry.size.width / tileWidth) + 2)
            let rows = max(1, Int(geometry.size.height / tileHeight) + 2)
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<columns, id: \.self) { _ in
                            Text(text)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.pfNavy)
                                .opacity(0.055)
                                .lineLimit(1)
                                .frame(width: tileWidth, height: tileHeight)
                        }
                    }
                    .offset(x: row % 2 == 0 ? 0 : tileWidth / 2)
                }
            }
            .rotationEffect(.degrees(-30))
            .scaleEffect(1.4)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Protected content modifier

/// Makes a lesson content view non-copyable and guards it against
/// screen recording. Apply to the content ScrollView of a lesson,
/// situation, guide, FAQ, search excerpt, practice or revision
/// screen. Do not apply to a view that contains a text field.
struct PFProtectedContentModifier: ViewModifier {
    @ObservedObject private var captureMonitor = PFScreenCaptureMonitor.shared

    func body(content: Content) -> some View {
        content
            // No selection, so no long-press Copy menu on any text.
            .textSelection(.disabled)
            // While recording or mirroring, the content blurs out.
            // Buttons and the audio keep working under the blur.
            .blur(radius: captureMonitor.isCaptured ? 24 : 0)
            .overlay {
                ZStack {
                    // Faint identity watermark over the content.
                    PFWatermarkOverlay()
                    // Recording veil: frosted panel plus a plain
                    // notice. It never intercepts touches, so the
                    // learner can still pause audio or close the
                    // screen while recording is on.
                    if captureMonitor.isCaptured {
                        Color.pfBackground.opacity(0.55)
                        VStack(spacing: PFSpacing.sm) {
                            Image(systemName: "eye.slash.fill")
                                .font(.pfSectionTitle)
                                .foregroundColor(.pfNavy)
                            Text("Content hidden while screen recording is on")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .multilineTextAlignment(.center)
                            Text("It comes back as soon as recording stops.")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(PFSpacing.lg)
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Copy protection for lesson content: no text selection, a
    /// faint identity watermark, and a blur veil while the screen
    /// is being recorded or mirrored.
    func pfProtectedContent() -> some View {
        modifier(PFProtectedContentModifier())
    }
}
