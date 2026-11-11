// FloatingChatAssistant.swift
// PaymentForge iOS - Clippy-style floating chat assistant.
// An original paperclip mascot drawn with SwiftUI shapes (not
// Microsoft artwork). It floats over every main tab, bottom right
// just above the tab bar, and snaps back there after a drag.
// Dragging it to the bottom edge hides it; a small gold dot
// brings it back. The mascot blinks, floats gently, glances
// around and dances when tapped, like Word 97's Clippy. A small
// transparent greeting bubble appears once per tab per session,
// a few seconds after the learner lands there, with a greeting
// that fits the tab; tapping the bubble or the mascot opens the
// chat as a small floating window inside the same page, never a
// full-screen sheet. Tapping the dimmed backdrop or Done closes
// it. The chat itself is the existing ChatAssistantView, so
// answers, source links and follow-ups work exactly as before.
// The mascot position is always bottom right; it is never saved
// anywhere, so it can never end up covering lesson content or
// the tab bar. No em dashes in any user-facing text.

import SwiftUI

/// The mascot's face: neutral most of the time, eyes up while it
/// is thinking of an answer, a big smile while it dances, and a
/// concerned look for explaining something that went wrong. The
/// drawing code reads this and moves the pupils, eyebrows and
/// mouth. It is a plain value, so any view that shows the mascot
/// can pick the face that fits the moment.
enum MascotExpression {
    case neutral
    case thinking
    case happy
    case concerned
}

/// The friendly paperclip mascot: an original drawing made only
/// from SwiftUI shapes, in the spirit of Microsoft Word 97's
/// Clippy. A silver wire bent into the classic paperclip shape
/// (a tall outer loop with a shorter inner loop and the wire
/// doubling back at the top), tilted the way Clippy leans, with
/// Clippy's odd face on the upper loop: two big googly eyes, one
/// set slightly higher than the other, pupils turned toward each
/// other, raised surprised eyebrows, and a lopsided smile. The
/// face is big on purpose, so it reads at 56pt and at the small
/// chat-avatar size. No Microsoft artwork is used. It sits in a
/// white circle with a thin gold ring and a faint blue inner ring,
/// and a soft blue glow behind the disc. The eyes blink on their
/// own every few seconds.
struct PaperclipMascot: View {
    var size: CGFloat = 64
    var expression: MascotExpression = .neutral

    var body: some View {
        ZStack {
            // Soft blue glow behind the disc.
            Circle()
                .fill(Color.pfRoyal.opacity(0.10))
                .frame(width: size + 8, height: size + 8)
                .blur(radius: 5)
            Circle()
                .fill(Color.white)
                .frame(width: size, height: size)
                .shadow(color: Color.pfNavy.opacity(0.18), radius: 10, x: 0, y: 4)
            Circle()
                .stroke(Color.pfGold, lineWidth: 2)
                .frame(width: size, height: size)
            // Faint blue inner ring: the blue-and-gold detailing
            // that marks the premium fintech companion.
            Circle()
                .stroke(Color.pfRoyal.opacity(0.30), lineWidth: 1)
                .frame(width: size - 6, height: size - 6)
            // The paperclip itself, drawn in a fixed 100 x 140 box
            // and scaled to the circle.
            ClippyClip(expression: expression)
                .frame(width: 100, height: 140)
                .scaleEffect((size * 0.72) / 140)
                .rotationEffect(.degrees(10))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The paperclip wire with Clippy's odd face, drawn in a fixed
/// 100 x 140 box. The wire is a metallic silver gradient; the
/// face is drawn on top of the wire, the way Clippy's face sits
/// on the clip. The eyes blink every few seconds and the pupils
/// glance around from time to time, so the mascot feels alive
/// without ever moving constantly. The face follows the
/// expression: thinking looks up, happy smiles wide, concerned
/// frowns a little.
private struct ClippyClip: View {
    var expression: MascotExpression = .neutral

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBlinking = false
    @State private var glanceOffset: CGSize = .zero
    @State private var blinkCount = 0

    private var wireGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.95, blue: 0.97),
                Color(red: 0.72, green: 0.76, blue: 0.81),
                Color(red: 0.52, green: 0.56, blue: 0.62),
                Color(red: 0.80, green: 0.83, blue: 0.87)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            // Outer loop of the wire.
            RoundedRectangle(cornerRadius: 30)
                .stroke(wireGradient, lineWidth: 7)
                .frame(width: 60, height: 124)
                .shadow(color: Color.black.opacity(0.15), radius: 2, x: 1, y: 2)
            // A thin highlight along the upper-left of the outer
            // loop: the metallic sheen.
            Capsule()
                .fill(Color.white.opacity(0.55))
                .frame(width: 3, height: 34)
                .position(x: 24, y: 28)
                .rotationEffect(.degrees(8))
            // The wire doubling back down inside (top fold).
            Capsule()
                .fill(wireGradient)
                .frame(width: 6, height: 54)
                .position(x: 50, y: 35)
            // Inner loop of the wire.
            RoundedRectangle(cornerRadius: 12)
                .stroke(wireGradient, lineWidth: 6)
                .frame(width: 24, height: 48)
                .offset(y: 16)
                .shadow(color: Color.black.opacity(0.15), radius: 2, x: 1, y: 2)
            // Small gold tip where the inner wire ends.
            Circle()
                .fill(Color.pfGold)
                .frame(width: 7, height: 7)
                .position(x: 50, y: 110)
                .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
            // Face: two big googly eyes, the right one set slightly
            // higher, pupils turned toward each other.
            clippyEye(at: CGPoint(x: 36, y: 40), pupilOffset: pupilOffset(base: CGSize(width: 2, height: 3)))
            clippyEye(at: CGPoint(x: 64, y: 36), pupilOffset: pupilOffset(base: CGSize(width: -3, height: 3)))
            // Raised, surprised eyebrows.
            leftBrow
                .stroke(Color.pfNavy, lineWidth: 3)
                .frame(width: 100, height: 140)
            rightBrow
                .stroke(Color.pfNavy, lineWidth: 3)
                .frame(width: 100, height: 140)
            // The mouth, which changes with the expression.
            mouth
                .stroke(Color.pfNavy, lineWidth: 3.5)
                .frame(width: 100, height: 140)
        }
        .frame(width: 100, height: 140)
        .task {
            // Blink every few seconds, and glance around every
            // fourth blink. The loop sleeps almost all the time,
            // so it costs nothing. Reduced motion means no blink
            // and no glance at all.
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                let wait = Double.random(in: 3...6)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled else { break }
                blinkCount += 1
                if blinkCount % 4 == 0 {
                    glanceOffset = CGSize(
                        width: CGFloat.random(in: -2...2),
                        height: CGFloat.random(in: -1...1)
                    )
                }
                isBlinking = true
                try? await Task.sleep(nanoseconds: 140_000_000)
                isBlinking = false
            }
        }
    }

    /// The pupil position for one eye: the base cross-eyed look,
    /// plus the slow glance drift, plus the expression. Thinking
    /// looks up; the rest keep the pupils where they are.
    private func pupilOffset(base: CGSize) -> CGSize {
        var offset = base
        offset.width += glanceOffset.width
        offset.height += glanceOffset.height
        if expression == .thinking {
            offset.height -= 4
        }
        return offset
    }

    /// One googly eye: a big white oval with a dark outline and a
    /// black pupil set off-centre, so the eyes look toward each
    /// other like Clippy's. A blink scales the eye shut for a
    /// moment; the pupil scales with it.
    private func clippyEye(at center: CGPoint, pupilOffset: CGSize) -> some View {
        ZStack {
            Ellipse()
                .fill(Color.white)
                .frame(width: 24, height: 28)
                .overlay(Ellipse().stroke(Color.pfNavy.opacity(0.65), lineWidth: 1.5))
            Circle()
                .fill(Color.pfNavy)
                .frame(width: 8, height: 8)
                .offset(pupilOffset)
                .animation(.easeInOut(duration: 0.4), value: pupilOffset)
        }
        .scaleEffect(x: 1, y: isBlinking ? 0.08 : 1, anchor: .center)
        .animation(.easeInOut(duration: 0.1), value: isBlinking)
        .position(center)
    }

    private var leftBrow: Path {
        var path = Path()
        switch expression {
        case .thinking:
            path.move(to: CGPoint(x: 25, y: 24))
            path.addQuadCurve(to: CGPoint(x: 47, y: 20), control: CGPoint(x: 36, y: 12))
        case .concerned:
            path.move(to: CGPoint(x: 25, y: 30))
            path.addQuadCurve(to: CGPoint(x: 47, y: 24), control: CGPoint(x: 36, y: 18))
        case .happy, .neutral:
            path.move(to: CGPoint(x: 25, y: 28))
            path.addQuadCurve(to: CGPoint(x: 47, y: 24), control: CGPoint(x: 36, y: 16))
        }
        return path
    }

    private var rightBrow: Path {
        var path = Path()
        switch expression {
        case .thinking:
            path.move(to: CGPoint(x: 55, y: 16))
            path.addQuadCurve(to: CGPoint(x: 76, y: 14), control: CGPoint(x: 65, y: 6))
        case .concerned:
            path.move(to: CGPoint(x: 55, y: 22))
            path.addQuadCurve(to: CGPoint(x: 76, y: 18), control: CGPoint(x: 65, y: 12))
        case .happy, .neutral:
            path.move(to: CGPoint(x: 55, y: 20))
            path.addQuadCurve(to: CGPoint(x: 76, y: 18), control: CGPoint(x: 65, y: 10))
        }
        return path
    }

    private var mouth: Path {
        var path = Path()
        switch expression {
        case .thinking:
            // A small flat line: thinking, not smiling.
            path.move(to: CGPoint(x: 42, y: 64))
            path.addLine(to: CGPoint(x: 58, y: 64))
        case .happy:
            // A wide open smile.
            path.move(to: CGPoint(x: 33, y: 58))
            path.addQuadCurve(to: CGPoint(x: 67, y: 58), control: CGPoint(x: 50, y: 84))
        case .concerned:
            // A slight frown.
            path.move(to: CGPoint(x: 38, y: 66))
            path.addQuadCurve(to: CGPoint(x: 62, y: 66), control: CGPoint(x: 50, y: 56))
        case .neutral:
            path.move(to: CGPoint(x: 36, y: 60))
            path.addQuadCurve(to: CGPoint(x: 64, y: 58), control: CGPoint(x: 50, y: 76))
        }
        return path
    }
}

/// The values one happy dance animates: a rotation wobble and a
/// vertical bounce. Driven by `danceTick` through keyframeAnimator,
/// so the dance plays once per trigger and always settles back
/// to the mascot's resting pose.
private struct DanceValues {
    var rotation: CGFloat = 0
    var bounce: CGFloat = 0
}

/// The floating assistant overlay. Place it once in MainTabView so
/// it floats over all five main tabs. It owns the mascot and the
/// greeting bubble; the in-page chat window is owned by
/// MainTabView through the showChat binding. The mascot lives
/// only at the bottom right, just above the tab bar: it can be
/// dragged around while held, but it always snaps back there on
/// release, so it can never be left covering lesson content or
/// the tab bar. Dragging it to the bottom edge hides it; a small
/// gold dot brings it back.
struct FloatingChatAssistant: View {
    @Binding var selectedTab: Int
    @Binding var isHidden: Bool
    @Binding var showChat: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The drag offset from the bottom-right spot. It is
    /// transient only: on release the mascot springs back to
    /// bottom right, so nothing is ever saved.
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var isDragging = false

    /// The greeting bubble: shown once per tab per session, a
    /// few seconds after the learner lands on a tab, never while
    /// the chat is open, and never again for that tab once it
    /// has been shown or dismissed.
    @State private var bubbleVisible = false
    @State private var bubbleShownTabs: Set<Int> = []
    @State private var bubbleTask: Task<Void, Never>?

    /// The happy dance, like Word 97's Clippy: incremented to
    /// play the dance once (on tap, and when a drag settles).
    @State private var danceTick = 0
    /// The wiggle while dragging: a rotation wobble and a bounce
    /// driven by how far the mascot has been dragged, so it
    /// wobbles playfully instead of sliding stiffly.
    @State private var wiggleAngle: CGFloat = 0
    @State private var wiggleBounce: CGFloat = 0
    /// The mascot's face during the dance: a big smile while it
    /// bounces, back to neutral when it settles.
    @State private var isCelebrating = false
    /// The gentle idle float: the mascot drifts a few points up
    /// and down while it waits.
    @State private var idleFloat: CGFloat = 0

    private let mascotSize: CGFloat = 64
    private let defaultTrailing: CGFloat = 16
    private let defaultBottomGap: CGFloat = 16
    private let tabBarHeight: CGFloat = 49
    /// Dragging the mascot down this far hides it, like dragging
    /// the website assistant to the bottom edge.
    private let hideDragDown: CGFloat = 55

    private var mascotExpression: MascotExpression {
        isCelebrating ? .happy : .neutral
    }

    /// The greeting for the tab the learner is on.
    private var greetingText: String {
        switch selectedTab {
        case 0:
            return "Hello! Ready to master payments today?"
        case 1:
            return "Need help understanding a payment concept?"
        case 2:
            return "Looking for something? I can help explain it."
        case 3:
            return "Want to explore a real-world payment scenario?"
        case 4:
            return "Let's see how far you've progressed!"
        default:
            return "How can I help you?"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                if isHidden {
                    // The gold dot that brings the assistant back.
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isHidden = false
                        }
                    } label: {
                        Circle()
                            .fill(Color.pfGold)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .shadow(color: Color.pfNavy.opacity(0.25), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show chat assistant")
                    .accessibilityHint("Brings back the floating chat assistant")
                    .padding(.trailing, 22)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + tabBarHeight + 24)
                } else {
                    VStack(alignment: .trailing, spacing: 8) {
                        if bubbleVisible {
                            greetingBubble
                                .transition(
                                    .scale(scale: 0.85, anchor: .bottomTrailing)
                                        .combined(with: .opacity)
                                )
                        }
                        Button {
                            // A short happy dance, like Clippy, then
                            // the chat opens as the dance finishes.
                            celebrate()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                showChat = true
                            }
                        } label: {
                            PaperclipMascot(expression: mascotExpression)
                                // Wiggle while dragging, driven by
                                // how far the mascot has moved.
                                .rotationEffect(.degrees(wiggleAngle))
                                .offset(y: wiggleBounce)
                                // Happy dance on tap and on settling
                                // after a drag: a rotation wobble and
                                // a bounce, under half a second.
                                .keyframeAnimator(initialValue: DanceValues(), trigger: danceTick) { content, value in
                                    content
                                        .rotationEffect(.degrees(value.rotation))
                                        .offset(y: value.bounce)
                                } keyframes: { _ in
                                    KeyframeTrack(\.rotation) {
                                        CubicKeyframe(-12, duration: 0.1)
                                        CubicKeyframe(10, duration: 0.1)
                                        CubicKeyframe(-6, duration: 0.1)
                                        CubicKeyframe(0, duration: 0.15)
                                    }
                                    KeyframeTrack(\.bounce) {
                                        CubicKeyframe(-10, duration: 0.12)
                                        CubicKeyframe(0, duration: 0.12)
                                        CubicKeyframe(-6, duration: 0.1)
                                        CubicKeyframe(0, duration: 0.12)
                                    }
                                }
                                // Gentle idle float while waiting.
                                .offset(y: idleFloat)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Chat Assistant")
                        .accessibilityHint("Opens the chat assistant. Drag to move it, drag it to the bottom edge to hide it.")
                        .simultaneousGesture(dragGesture(in: geometry))
                    }
                    .padding(.trailing, defaultTrailing)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + tabBarHeight + defaultBottomGap)
                    .offset(dragOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .onAppear {
            scheduleBubble(for: selectedTab)
            startIdleFloat()
        }
        .onDisappear {
            bubbleTask?.cancel()
            bubbleTask = nil
        }
        .onChange(of: selectedTab) { _, newTab in
            // The bubble is per tab: hide it at once, then offer
            // the new tab's greeting after a few seconds, but
            // only if that tab has not had its greeting yet.
            if reduceMotion {
                bubbleVisible = false
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    bubbleVisible = false
                }
            }
            scheduleBubble(for: newTab)
        }
        .onChange(of: showChat) { _, isOpen in
            // Never show the greeting while the chat is open.
            if isOpen {
                bubbleVisible = false
            }
        }
    }

    /// The greeting bubble: a small transparent frosted bubble
    /// with the tab's greeting and an x to dismiss it. Tapping
    /// the bubble opens the chat. It is forced to a light frost
    /// so the navy text stays legible in both appearances, the
    /// same way the app's own cards stay light.
    private var greetingBubble: some View {
        HStack(alignment: .top, spacing: PFSpacing.sm) {
            Text(greetingText)
                .font(.pfCallout.weight(.semibold))
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                bubbleVisible = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.pfSecondaryText)
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide greeting")
        }
        .padding(.horizontal, PFSpacing.md)
        .padding(.vertical, 10)
        .frame(width: 250, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.pfNavy.opacity(0.15), radius: 12, x: 0, y: 6)
        .environment(\.colorScheme, .light)
        .onTapGesture {
            showChat = true
        }
        .accessibilityAction {
            showChat = true
        }
    }

    /// Offer the tab's greeting a few seconds after the learner
    /// lands there, but only once per tab per session. If the
    /// learner opens the chat first, the greeting stays away.
    private func scheduleBubble(for tab: Int) {
        bubbleTask?.cancel()
        bubbleTask = nil
        guard !bubbleShownTabs.contains(tab) else { return }
        bubbleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            guard selectedTab == tab, !showChat, !isHidden else { return }
            bubbleShownTabs.insert(tab)
            if reduceMotion {
                bubbleVisible = true
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    bubbleVisible = true
                }
            }
        }
    }

    /// The gentle idle float: a slow drift up and down while the
    /// mascot waits. Reduced motion means it stays still.
    private func startIdleFloat() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            idleFloat = -3
        }
    }

    /// One happy dance with a big smile, then back to neutral.
    private func celebrate() {
        isCelebrating = true
        danceTick += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            isCelebrating = false
        }
    }

    /// Drag to move the mascot while held. On release it springs
    /// back to the bottom-right corner; dragging it down into
    /// the tab bar zone hides it instead.
    private func dragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if !isDragging {
                    // First move of this drag: remember where the
                    // mascot was, so the drag moves it from there.
                    isDragging = true
                    dragStartOffset = dragOffset
                }
                let raw = CGSize(
                    width: dragStartOffset.width + value.translation.width,
                    height: dragStartOffset.height + value.translation.height
                )
                dragOffset = clamped(raw, in: geometry)
                // Wiggle and bounce while dragging: the further the
                // mascot has moved, the more it wobbles, like Clippy.
                let distance = (value.translation.width * value.translation.width
                    + value.translation.height * value.translation.height).squareRoot()
                let wobble = sin(distance * 0.12)
                wiggleAngle = wobble * 10
                wiggleBounce = -abs(wobble) * 6
            }
            .onEnded { value in
                isDragging = false
                let raw = CGSize(
                    width: dragStartOffset.width + value.translation.width,
                    height: dragStartOffset.height + value.translation.height
                )
                let clampedOffset = clamped(raw, in: geometry)
                // The wiggle settles back to the resting pose.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.4)) {
                    wiggleAngle = 0
                    wiggleBounce = 0
                }
                if clampedOffset.height > hideDragDown {
                    // Dragged to the bottom edge: hide, and come
                    // back at the bottom-right corner next time.
                    dragOffset = .zero
                    dragStartOffset = .zero
                    withAnimation(.easeOut(duration: 0.2)) {
                        isHidden = true
                    }
                } else {
                    // Snap back to the bottom-right corner with a
                    // quick happy dance.
                    dragStartOffset = .zero
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                        dragOffset = .zero
                    }
                    celebrate()
                }
            }
    }

    /// Keep the mascot on screen while it is dragged: from the
    /// bottom-right corner it can move left across the width and
    /// up most of the height, but never off the top and never
    /// below the hide zone.
    private func clamped(_ offset: CGSize, in geometry: GeometryProxy) -> CGSize {
        let maxX = max(0, geometry.size.width - mascotSize - defaultTrailing * 2)
        let tabGap = geometry.safeAreaInsets.bottom + tabBarHeight + defaultBottomGap
        let minY = -(geometry.size.height - tabGap - mascotSize - 100)
        return CGSize(
            width: min(max(offset.width, -maxX), 0),
            height: min(max(offset.height, minY), hideDragDown + 10)
        )
    }
}

/// The chat as a small floating window inside the current page,
/// instead of a full-screen sheet. It sits above the mascot at
/// the bottom right, about 85% of the screen wide and at most
/// 65% tall, with a dimmed backdrop that dismisses on tap
/// outside and a Done button in the navigation bar. The content
/// is the existing ChatAssistantView inside its own
/// NavigationStack, so answers, source links, follow-up chips
/// and the conversation work exactly as before; a source link
/// opens its lesson inside this same window. The card lifts
/// above the keyboard while typing so the input field stays
/// visible.
struct ChatAssistantCard: View {
    @Binding var isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var keyboardHeight: CGFloat = 0

    private let tabBarHeight: CGFloat = 49
    private let mascotSize: CGFloat = 64

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .accessibilityLabel("Close chat")
                    .accessibilityAction { dismiss() }
                VStack(spacing: 0) {
                    NavigationStack {
                        ChatAssistantView()
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { dismiss() }
                                }
                            }
                    }
                }
                .frame(width: cardWidth(in: geometry), height: cardHeight(in: geometry))
                .background(Color.pfBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.pfBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 12)
                .padding(.trailing, 16)
                .padding(.bottom, cardBottomPadding(in: geometry))
                .offset(y: keyboardOffset(in: geometry))
                .scaleEffect(appeared ? 1 : 0.92, anchor: .bottomTrailing)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    appeared = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }

    private func cardWidth(in geometry: GeometryProxy) -> CGFloat {
        min(geometry.size.width * 0.85, 420)
    }

    private func cardHeight(in geometry: GeometryProxy) -> CGFloat {
        let maxHeight = min(geometry.size.height * 0.65, 620)
        let available = geometry.size.height - keyboardHeight - geometry.safeAreaInsets.top - 16
        return min(maxHeight, max(320, available))
    }

    /// The card sits just above the mascot, which sits just
    /// above the tab bar.
    private func cardBottomPadding(in geometry: GeometryProxy) -> CGFloat {
        geometry.safeAreaInsets.bottom + tabBarHeight + 16 + mascotSize + 12
    }

    /// Lift the card just enough that its bottom edge sits above
    /// the keyboard, so the input field stays visible while typing.
    private func keyboardOffset(in geometry: GeometryProxy) -> CGFloat {
        guard keyboardHeight > 0 else { return 0 }
        return -max(0, keyboardHeight - cardBottomPadding(in: geometry))
    }

    private func dismiss() {
        if reduceMotion || !appeared {
            isPresented = false
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isPresented = false
        }
    }
}
