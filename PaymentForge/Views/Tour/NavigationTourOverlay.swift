// NavigationTourOverlay.swift
// Payments Training Hub iOS - Interactive navigation tour overlay.
// A guided tour of the five tabs and the key drawer rows: a dimmed
// interface with a spotlight cutout and a gold ring around the
// highlighted control, plus a navy tooltip card. The tour never
// blocks the app: the dim and the ring ignore every tap, so the
// learner can tap anything in the app while the tour runs, and only
// the tour cards themselves intercept taps. Tab frames come from
// the measured tab bar frame; drawer row frames come from live
// frame values supplied by the coordinator, refreshed on every
// scroll and slide, with anchors as fallback, so the spotlight
// and the pointing hand land exactly on the row and track it
// while it moves. A target that is not on screen gets no
// spotlight and no hand until the drawer scroll brings it into
// view: the pointer never sits on a guessed position. No em
// dashes in any user-facing text.

import SwiftUI
import UIKit

// MARK: - Drawer row anchors

/// The anchor contract for drawer row frames. The coordinator
/// attaches this key to each drawer row in SideDrawerView with an
/// anchorPreference whose value is the row bounds keyed by its
/// DrawerDestination, for example:
/// `.anchorPreference(key: DrawerRowAnchorKey.self, value: .bounds) { [destination: $0] }`.
/// The parent reads the anchors with onPreferenceChange at the
/// common ancestor of the drawer and this overlay (preferences
/// only flow up, never down into a sibling subtree), passes them
/// down, and this overlay resolves them with proxy[anchor]
/// against its own full-screen GeometryReader. Anchors resolve
/// against the current layout, so the overlay re-resolves them
/// after the drawer slide and scroll finish (see geometryTick),
/// which keeps the spotlight on the settled row.
struct DrawerRowAnchorKey: PreferenceKey {
    static var defaultValue: [DrawerDestination: Anchor<CGRect>] = [:]
    static func reduce(value: inout [DrawerDestination: Anchor<CGRect>], nextValue: () -> [DrawerDestination: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The anchor of the Keep Learning card at the bottom of the
/// drawer, for the tour's final step. A single anchor, not a
/// dictionary: the card is not a drawer destination row. The
/// parent reads it with onPreferenceChange at the common
/// ancestor and passes it to the overlay, which resolves it
/// against its own full-screen GeometryReader.
struct KeepLearningAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

// MARK: - Drawer row frames

/// The live frames of the drawer rows, reported by SideDrawerView
/// as concrete rects in the tour coordinate space (see
/// TourCoordinateSpace). A rect value changes whenever its row
/// moves, so scrolling the drawer list and sliding the drawer
/// open both push fresh values up through onPreferenceChange
/// and the overlay re-renders with the target's real on-screen
/// frame. Anchors stay as the fallback: an anchor resolves
/// lazily, and its stored value does not change when the row
/// moves, so a scroll or slide can leave the overlay holding a
/// stale position with nothing forcing a re-resolve. Frames are
/// the primary source; anchors only fill in when no frame has
/// arrived yet.
struct DrawerRowFrameKey: PreferenceKey {
    static var defaultValue: [DrawerDestination: CGRect] = [:]
    static func reduce(value: inout [DrawerDestination: CGRect], nextValue: () -> [DrawerDestination: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The live frame of the Keep Learning card, same contract as
/// DrawerRowFrameKey: a concrete rect in the tour coordinate
/// space, refreshed on every move.
struct KeepLearningFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// The anchor of the Search page's search field, for the tour's
/// typing demo on the Search step: the hand types at the field
/// and the spotlight frames it while the demo runs.
struct SearchFieldAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// The tour's search demo messages, posted by the overlay and
/// received by SearchView. Type carries the cumulative text and
/// the full demo query; submit carries the query to run; reset
/// carries the query to clear, and only clears when the field
/// still holds exactly that text, so the learner's own typing
/// is never wiped.
extension Notification.Name {
    static let tourSearchDemoType = Notification.Name("pf.tourSearchDemoType")
    static let tourSearchDemoSubmit = Notification.Name("pf.tourSearchDemoSubmit")
    static let tourSearchDemoReset = Notification.Name("pf.tourSearchDemoReset")
}

// MARK: - Tab bar frame

/// The shared coordinate space for tour geometry. MainTabView
/// declares it on the root ZStack; drawer row anchors are
/// resolved in it, and the overlay uses spotlight rects in the
/// same space because the overlay fills the same window. The
/// tab bar frame reader reports in the ZStack's own coordinates,
/// which match this space because both fill the same ZStack.
enum TourCoordinateSpace {
    static let name = "tourSpace"
}

// MARK: - Tab bar frame reader

/// The measured tab bar geometry: the rect of every visible tab
/// button, plus the bar frame (the union of the buttons when any
/// were found, else the UITabBar frame). All rects are in WINDOW
/// coordinates: the reader converts with `to: nil`, and the
/// overlay translates them into its own space with the
/// GeometryReader global origin, so a reader/overlay frame
/// mismatch can never shift the spotlight. iOS 26 draws the
/// floating pill offset from the tab bar's layout frame, so the
/// bar frame alone places the spotlight above the pill: the
/// button rects are the controls the learner actually sees.
struct TabBarGeometry: Equatable {
    let buttonRects: [CGRect]
    let barFrame: CGRect
}

/// Reports the real tab bar geometry in window coordinates.
/// toolbarBackground takes a ShapeStyle, not a View, so a reader
/// cannot live in the toolbar background itself. Instead this
/// invisible reader fills the root ZStack and asks UIKit for
/// the tab buttons' frames on every layout, converted into
/// window coordinates. Re-reports whenever the layout changes,
/// the parent re-renders, or a settle check finds a new frame,
/// so rotation, size changes, and the bar compacting on scroll
/// move the spotlight with the tab bar.
struct TabBarFrameReader: UIViewRepresentable {
    /// Called on the main queue whenever the measured geometry changes.
    var onGeometry: (TabBarGeometry) -> Void

    func makeUIView(context: Context) -> TabBarFrameReaderView {
        let view = TabBarFrameReaderView(frame: .zero)
        view.onGeometry = onGeometry
        return view
    }

    func updateUIView(_ uiView: TabBarFrameReaderView, context: Context) {
        uiView.onGeometry = onGeometry
        uiView.reportFrameIfNeeded()
    }
}

/// The invisible view that measures the tab bar. It draws nothing
/// and never intercepts touches.
final class TabBarFrameReaderView: UIView {
    var onGeometry: ((TabBarGeometry) -> Void)?
    private var lastReported: TabBarGeometry = TabBarGeometry(buttonRects: [], barFrame: .zero)
    private var recheckStep = 0
    /// Settle re-measurements after a report, at growing delays:
    /// the bar can still be animating, compacting, or laying out
    /// its buttons when the first layout fires, and this view's
    /// own layout does not fire again when only the bar moves.
    /// Bounded: four checks, then the chain ends.
    private let recheckDelays: [TimeInterval] = [0.15, 0.4, 0.8, 1.5]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportFrameIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportFrameIfNeeded()
    }

    /// Finds the tab buttons, converts their frames into window
    /// coordinates, and reports the geometry when it changed.
    /// Only genuinely visible buttons count: hidden, transparent,
    /// or off-window views and views outside the bar bounds are
    /// dropped, and near-duplicate rects from an in-flight
    /// animation are merged into one rect per tab, so the
    /// spotlight never falls back to equal segments because an
    /// extra or stale button made the count wrong. Reporting is
    /// async so no state changes during layout. A settle chain
    /// follows every report, so a frame captured mid-animation
    /// is corrected once the bar settles.
    func reportFrameIfNeeded() {
        guard let window, let tabBar = Self.tabBar(in: window.rootViewController) else { return }
        let barBoundsInWindow = tabBar.convert(tabBar.bounds, to: nil)
        let buttons = Self.tabBarButtons(in: tabBar)
            .filter { !$0.isHidden && $0.alpha > 0.01 && $0.window != nil }
            .map { $0.convert($0.bounds, to: nil) }
            .filter { $0.width > 0 && $0.height > 0 }
            .filter { $0.intersects(barBoundsInWindow.insetBy(dx: -4, dy: -4)) }
        let merged = Self.mergedButtonRects(buttons)
        let barFrame: CGRect
        if let first = merged.first {
            barFrame = merged.dropFirst().reduce(first) { $0.union($1) }
        } else {
            barFrame = barBoundsInWindow
        }
        let geometry = TabBarGeometry(buttonRects: merged, barFrame: barFrame)
        guard geometry != lastReported, barFrame.width > 0, barFrame.height > 0 else { return }
        lastReported = geometry
        let handler = onGeometry
        DispatchQueue.main.async { handler?(geometry) }
        scheduleRecheckChain()
    }

    /// Merges button rects into one rect per tab: rects whose
    /// centres sit within 10pt of each other are the same tab
    /// seen twice (an animating copy or a stale layout), so the
    /// largest rect of the cluster wins. The result is sorted
    /// left to right. When more than five clusters survive, the
    /// five largest win: this app has five tabs, so any extra
    /// cluster is a spurious view, never a sixth tab.
    private static func mergedButtonRects(_ rects: [CGRect]) -> [CGRect] {
        let sorted = rects.sorted { $0.midX < $1.midX }
        var clusters: [[CGRect]] = []
        for rect in sorted {
            if let last = clusters.last, let first = last.first, abs(rect.midX - first.midX) <= 10 {
                clusters[clusters.count - 1].append(rect)
            } else {
                clusters.append([rect])
            }
        }
        var merged = clusters.map { cluster in
            cluster.max(by: { $0.width * $0.height < $1.width * $1.height }) ?? cluster[0]
        }
        if merged.count > 5 {
            merged = Array(merged.sorted(by: { $0.width * $0.height > $1.width * $1.height }).prefix(5))
        }
        return merged.sorted { $0.minX < $1.minX }
    }

    /// Starts the settle chain after a report. A no-op while a
    /// chain is already running: the running chain re-measures
    /// anyway, so restarting it would only delay the last check.
    private func scheduleRecheckChain() {
        guard recheckStep == 0 else { return }
        scheduleNextRecheck()
    }

    private func scheduleNextRecheck() {
        guard recheckStep < recheckDelays.count else {
            recheckStep = 0
            return
        }
        let delay = recheckDelays[recheckStep]
        recheckStep += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.reportFrameIfNeeded()
            self?.scheduleNextRecheck()
        }
    }

    /// The tab bar buttons, found by walking the tab bar's view
    /// hierarchy for views whose class is a tab bar button. The
    /// search recurses so a floating-bar container between the
    /// bar and its buttons does not hide them; a matched view's
    /// own children are its internals, not more buttons.
    private static func tabBarButtons(in view: UIView) -> [UIView] {
        var found: [UIView] = []
        for subview in view.subviews {
            if String(describing: type(of: subview)).contains("TabBarButton") {
                found.append(subview)
            } else {
                found.append(contentsOf: tabBarButtons(in: subview))
            }
        }
        return found
    }

    /// The tab bar backing the SwiftUI TabView, found by walking
    /// the view controller hierarchy from the window root.
    private static func tabBar(in viewController: UIViewController?) -> UITabBar? {
        guard let viewController else { return nil }
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController.tabBar
        }
        for child in viewController.children {
            if let found = tabBar(in: child) { return found }
        }
        return tabBar(in: viewController.presentedViewController)
    }
}

// MARK: - Spotlight dim shape

/// A full-rect dim with an optional rounded-rect hole, filled with
/// the even-odd rule so the hole stays clear. The hole rect is the
/// animatable data, so the spotlight glides between targets when
/// the change is animated, and jumps instantly when Reduce Motion
/// turns the animation off. When showsHole is false the path is
/// the full rect, so the dim covers the whole screen with no hole.
private struct NavigationTourSpotlightShape: Shape {
    var holeRect: CGRect
    var showsHole: Bool
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(holeRect.origin.x, holeRect.origin.y),
                AnimatablePair(holeRect.size.width, holeRect.size.height)
            )
        }
        set {
            holeRect = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if showsHole {
            path.addRoundedRect(in: holeRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        }
        return path
    }
}

/// Scrolls the visible tab page down through its content and
/// back to the top, like a human scrolling, so a tab step
/// shows the page instead of only its top. Finds the largest
/// vertical scroll view in the key window (the visible tab's
/// content scroller) and animates its offset: down over 1.8
/// seconds, a short pause, then back to the top over 1.6
/// seconds. A newer request cancels an older one, so stepping
/// through the tour never stacks scrolls, and a page with
/// nothing to scroll through is left alone. The user can grab
/// the page mid-scroll: the animation allows interaction.
private enum TourPageScroller {
    private static var generation = 0

    static func scrollThroughPage(shallow: Bool = false) {
        generation += 1
        let myGeneration = generation
        // The scroll view is looked up AFTER the delay, not
        // before it: on a just-switched tab the new page has
        // not laid out yet at call time, so an immediate lookup
        // finds nothing (or the old tab) and no scroll ever
        // shows. Looking up after the settle delay finds the
        // new tab's scroller with its real content size, with
        // one retry for a slow layout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard myGeneration == generation else { return }
            if let scrollView = largestVerticalScrollView() {
                animateScroll(scrollView, generation: myGeneration, shallow: shallow)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard myGeneration == generation else { return }
                    guard let scrollView = largestVerticalScrollView() else { return }
                    animateScroll(scrollView, generation: myGeneration, shallow: shallow)
                }
            }
        }
    }

    private static func animateScroll(_ scrollView: UIScrollView, generation myGeneration: Int, shallow: Bool) {
        // Settle the layout first, so the size read below is
        // the real one: a stale size can overshoot past the
        // content and flash the bare background. The legs run
        // soft and slow, so lazily rendered rows keep up and
        // no white gap shows mid-scroll. A shallow scroll caps
        // the depth at two screens and pauses longer at the
        // bottom: for a long lazy list, a full traverse
        // outruns the rendering whatever the speed, and the
        // white gaps are the rows not yet drawn.
        scrollView.layoutIfNeeded()
        let top = CGPoint(x: 0, y: -scrollView.adjustedContentInset.top)
        var bottomY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        if shallow {
            bottomY = min(bottomY, top.y + scrollView.bounds.height * 2)
        }
        guard bottomY > top.y + 40 else { return }
        let bottom = CGPoint(x: 0, y: bottomY)
        UIView.animate(withDuration: 1.8, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            scrollView.contentOffset = bottom
        } completion: { _ in
            guard myGeneration == generation else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + (shallow ? 0.5 : 0.35)) {
                guard myGeneration == generation else { return }
                UIView.animate(withDuration: 1.6, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                    scrollView.contentOffset = top
                }
            }
        }
    }

    static func cancel() {
        generation += 1
    }

    /// The largest vertical scroll view in the key window that
    /// is visible, enabled, and taller than its content area.
    /// Horizontal chip scrollers fail the height test, and the
    /// closed drawer's scroller fails the visibility test, so
    /// the winner is the visible tab's content scroller.
    private static func largestVerticalScrollView() -> UIScrollView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .filter { $0.isKeyWindow }
        guard let window = windows.first else { return nil }
        var best: UIScrollView?
        var bestArea: CGFloat = 0
        func visit(_ view: UIView) {
            if let scrollView = view as? UIScrollView,
               !scrollView.isHidden, scrollView.alpha > 0.01, scrollView.isScrollEnabled,
               scrollView.bounds.width > 200,
               scrollView.contentSize.height > scrollView.bounds.height + 40 {
                let frameInWindow = scrollView.convert(scrollView.bounds, to: nil)
                if frameInWindow.intersects(window.bounds) {
                    let area = scrollView.bounds.width * scrollView.bounds.height
                    if area > bestArea {
                        bestArea = area
                        best = scrollView
                    }
                }
            }
            for subview in view.subviews { visit(subview) }
        }
        visit(window)
        return best
    }
}

/// The pointing hand: a white hand with its index finger
/// extended, outlined in black, like the Windows hand cursor.
/// Owns its gentle tap bob, so the bob restarts cleanly each
/// time the hand appears. The press on the click beat is
/// applied by the caller, on an outer view, so it never
/// disturbs the bob animation running inside.
private struct TourHandCursor: View {
    var reduceMotion: Bool
    @State private var bob = false

    var body: some View {
        ZStack {
            Image(systemName: "hand.point.up.fill")
                .font(.system(size: 30))
                .foregroundColor(.black)
                .scaleEffect(1.15)
            Image(systemName: "hand.point.up.fill")
                .font(.system(size: 30))
                .foregroundColor(.white)
        }
        .shadow(color: .black.opacity(0.35), radius: 3, x: 1, y: 2)
        .offset(x: 0, y: bob ? 4 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                bob = true
            }
        }
    }
}

// MARK: - The tour overlay

/// The interactive navigation tour: a start card, eight steps, and
/// a completion screen. The overlay manages its own step state and
/// calls onFinish when the user taps Skip Tour at any point or
/// "Explore the Platform" on the completion screen. The parent
/// owns post-tour state: marking the tour done, closing the drawer,
/// and landing on Home. This view never duplicates that work.
struct NavigationTourOverlay: View {
    @Binding private var selectedTab: Int
    @Binding private var isDrawerOpen: Bool
    @Binding private var drawerScrollTarget: DrawerDestination?
    /// Drawer row anchors, read by the parent at the common
    /// ancestor and passed down. Resolved against this overlay's
    /// own full-screen GeometryReader. The fallback when no live
    /// frame has arrived yet; drawer steps show a full dim with
    /// no spotlight hole until their row frame or anchor arrives
    /// and the row is actually on screen.
    private let drawerRowAnchors: [DrawerDestination: Anchor<CGRect>]
    /// The live frames of the drawer rows, in the tour
    /// coordinate space. The overlay fills the same ZStack, so
    /// these are already overlay coordinates. The primary source
    /// for drawer spotlights: refreshed on every scroll and
    /// slide, unlike the anchors, whose stored values do not
    /// change when a row moves.
    private let drawerRowFrames: [DrawerDestination: CGRect]
    /// The measured tab bar geometry in WINDOW coordinates,
    /// reported by the frame reader. Empty until the first
    /// report arrives; tab steps fall back to the strip estimate
    /// until then. The overlay translates it into its own space
    /// with localRect(_:proxy:) before use.
    private let tabBarGeometry: TabBarGeometry
    /// The anchor of the Keep Learning card at the bottom of the
    /// drawer, for the final step. The fallback when no live
    /// frame has arrived yet. Nil until the drawer lays out.
    private let keepLearningAnchor: Anchor<CGRect>?
    /// The live frame of the Keep Learning card, in the tour
    /// coordinate space, same contract as the row frames. The
    /// primary source for the final step. Nil until the drawer
    /// lays out.
    private let keepLearningFrame: CGRect?
    /// The anchor of the Search page's search field, for the
    /// typing demo on the Search step. Nil until Search lays out.
    private let searchFieldAnchor: Anchor<CGRect>?
    private let onFinish: () -> Void

    /// The bar frame for tooltip clearance and the segment
    /// fallback: the union of the measured buttons, else the
    /// UITabBar frame.
    private var tabBarFrame: CGRect { tabBarGeometry.barFrame }
    /// The measured tab button rects, left to right.
    private var tabButtonRects: [CGRect] { tabBarGeometry.buttonRects }

    /// The tour highlight colour: bright cyan, deliberately
    /// different from the gold used by buttons and accents, so
    /// the spotlight ring and the pointing hand read as "tap
    /// here" at a glance against the navy cards and the tab bar.
    private static let tourHighlight = Color(red: 0.05, green: 0.78, blue: 0.95)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: TourPhase = .start
    /// Bumped after the drawer finishes opening and scrolling, so
    /// the spotlight re-resolves the row anchors against the
    /// settled layout instead of the mid-animation frames.
    @State private var geometryTick = 0
    /// The hand's fingertip while it drags a scroll showcase:
    /// set during the drag, nil when the hand sits on its tab
    /// (tab steps) or is hidden (drawer and card steps between
    /// drags). Screen coordinates; the overlay fills the
    /// screen, so they match its space.
    @State private var handPoint: CGPoint?
    /// Guards the tab-step transition sequence (glide, click,
    /// switch, scroll): only the latest step's sequence runs,
    /// and a step already sequenced does not restart when
    /// applySideEffects is called again for it from another
    /// path. Bumped on every finish or exit so a pending
    /// sequence can never switch the tab after the tour ends.
    @State private var transitionGeneration = 0
    @State private var sequencedStep: Int?
    /// The hand's press on the click beat of a tab step.
    @State private var clickTap = false
    /// The expanding ring at the fingertip on the click beat.
    /// Zero hides it; each click takes a new id so a stale
    /// hide never kills a fresh ring.
    @State private var clickRippleID = 0
    @State private var clickRingExpanded = false
    /// True while the Search demo runs: the spotlight frames
    /// the search field instead of the tab capsule.
    @State private var searchDemoFieldActive = false
    /// The Search demo's hand phase. Idle except while the
    /// demo types and taps.
    @State private var searchDemoPhase: SearchDemoPhase = .idle
    @AccessibilityFocusState private var accessibilityFocus: TourFocus?

    init(
        selectedTab: Binding<Int>,
        isDrawerOpen: Binding<Bool>,
        drawerScrollTarget: Binding<DrawerDestination?>,
        drawerRowAnchors: [DrawerDestination: Anchor<CGRect>],
        drawerRowFrames: [DrawerDestination: CGRect],
        tabBarGeometry: TabBarGeometry,
        keepLearningAnchor: Anchor<CGRect>?,
        keepLearningFrame: CGRect?,
        searchFieldAnchor: Anchor<CGRect>?,
        onFinish: @escaping () -> Void
    ) {
        self._selectedTab = selectedTab
        self._isDrawerOpen = isDrawerOpen
        self._drawerScrollTarget = drawerScrollTarget
        self.drawerRowAnchors = drawerRowAnchors
        self.drawerRowFrames = drawerRowFrames
        self.tabBarGeometry = tabBarGeometry
        self.keepLearningAnchor = keepLearningAnchor
        self.keepLearningFrame = keepLearningFrame
        self.searchFieldAnchor = searchFieldAnchor
        self.onFinish = onFinish
    }

    /// The demo query the tour types on the Search step. A
    /// term with guaranteed results: the ISO 20022 chapters
    /// and their lessons.
    private static let searchDemoQuery = "ISO 20022"

    /// The Search demo's hand phase: idle on the tab, typing at
    /// the field's text position, or tapping the search icon.
    /// The hand position derives from this in the spotlight
    /// layer, so the hand glides to the live field frame.
    private enum SearchDemoPhase {
        case idle
        case typing
        case tapping
    }

    /// The tour phases: the start card, one of the eight steps
    /// (zero based index), or the completion screen.
    private enum TourPhase: Equatable {
        case start
        case step(Int)
        case complete
    }

    /// VoiceOver focus targets: the start card text, the tooltip
    /// text, or the completion card text.
    private enum TourFocus: Hashable {
        case startCard
        case tooltip
        case completionCard
    }

    /// Where the tooltip card sits for the current step.
    private enum TooltipPlacement {
        case aboveTabBar
        case rightOfDrawer
        case aboveRow
        case belowRow
        case centered
    }

    /// One tour step: copy plus its target: a tab index (steps
    /// 1 to 5), a drawer destination (steps 6 and 7), or the
    /// Keep Learning card at the bottom of the drawer (step 8).
    /// Exactly one target is set for every step.
    private struct TourStep {
        let title: String
        let body: String
        let symbol: String
        let tabIndex: Int?
        let destination: DrawerDestination?
        let highlightsCard: Bool

        /// Explicit init, not the synthesized memberwise one:
        /// the memberwise form with a defaulted last parameter
        /// was rejected by Xcode as an extra argument, so the
        /// six argument call is spelled out here. The seven
        /// other steps use the default.
        init(
            title: String,
            body: String,
            symbol: String,
            tabIndex: Int?,
            destination: DrawerDestination?,
            highlightsCard: Bool = false
        ) {
            self.title = title
            self.body = body
            self.symbol = symbol
            self.tabIndex = tabIndex
            self.destination = destination
            self.highlightsCard = highlightsCard
        }
    }

    private static let steps: [TourStep] = [
        TourStep(
            title: "Home",
            body: "Your personal learning dashboard. Pick up where you left off and continue learning.",
            symbol: "house.fill",
            tabIndex: 0,
            destination: nil
        ),
        TourStep(
            title: "Learn",
            body: "Structured learning paths, courses and lessons, in the order to follow.",
            symbol: "book.fill",
            tabIndex: 1,
            destination: nil
        ),
        TourStep(
            title: "Search",
            body: "Search and filter the full learning library to find any lesson, guide or case.",
            symbol: "magnifyingglass",
            tabIndex: 2,
            destination: nil
        ),
        TourStep(
            title: "Payment Cases",
            body: "Real-world payment situations, worked the way a senior BA handles them.",
            symbol: "briefcase.fill",
            tabIndex: 3,
            destination: nil
        ),
        TourStep(
            title: "My Progress",
            body: "Your learning analytics, streak and achievements, all in one place.",
            symbol: "chart.bar.fill",
            tabIndex: 4,
            destination: nil
        ),
        TourStep(
            title: "Payment Simulator",
            body: "Follow a payment through its whole lifecycle, inject a fault, and see where it stops.",
            symbol: "arrow.triangle.2.circlepath",
            tabIndex: nil,
            destination: .simulator
        ),
        TourStep(
            title: "Profile and Purchases",
            body: "Profile holds your account and settings. My Purchases sits just below Profile in the menu, with your bundles and access.",
            symbol: "person.fill",
            tabIndex: nil,
            destination: .profile
        ),
        TourStep(
            title: "Start Learning",
            body: "Your streak and weekly goal live here, with one tap to jump into your next lesson.",
            symbol: "flame.fill",
            tabIndex: nil,
            destination: nil,
            highlightsCard: true
        )
    ]

    /// The corner radius shared by the spotlight hole and the gold
    /// ring, so the ring traces the hole exactly.
    private let spotlightCornerRadius: CGFloat = 12

    /// Height of the tab bar strip at the bottom of the container:
    /// the standard 49pt tab bar plus the live bottom safe area
    /// inset from the overlay's own GeometryReader, which is the
    /// same 49pt the rest of the app uses for the tab bar. The
    /// overlay fills the whole screen, so the strip is the bottom
    /// strip of the GeometryReader container.
    /// Translates a window-coordinate rect from the frame reader
    /// into this overlay's GeometryReader space, using the
    /// reader's global origin. When the overlay fills the window
    /// the origin is zero and the rect is unchanged; when it is
    /// not, this is what keeps the spotlight on the tab.
    private func localRect(_ rect: CGRect, proxy: GeometryProxy) -> CGRect {
        let origin = proxy.frame(in: .global).origin
        return rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    /// The floating pill rect, in overlay space: the union of
    /// the five measured buttons when the reader found them,
    /// else the strip estimate measured from the device
    /// screenshot (iPhone 17 Pro Max, 12 Nov 2026): 19.5pt side
    /// margins, a 63pt tall pill, 21pt above the screen bottom.
    private func pillRect(proxy: GeometryProxy) -> CGRect {
        if tabButtonRects.count == 5, isTabBarFrameValid {
            return localRect(tabBarFrame, proxy: proxy)
        }
        let size = proxy.size
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGRect(x: 19.5, y: size.height - 84, width: max(0, size.width - 39), height: 63)
    }

    /// Tab centres as fractions of the pill width, measured
    /// from the device screenshot. The tabs are NOT equally
    /// spaced: the long Payment Cases and My Progress labels
    /// widen their buttons, so equal fifths put the highlight
    /// up to 31pt off the icon. Home 0.115, Learn 0.269,
    /// Search 0.424, Payment Cases 0.627, My Progress 0.857.
    private static let tabCenterFractions: [CGFloat] = [0.115, 0.269, 0.424, 0.627, 0.857]

    /// True once the frame reader has reported a real frame.
    private var isTabBarFrameValid: Bool {
        !tabBarFrame.isNull && tabBarFrame.width > 0 && tabBarFrame.height > 0
    }

    /// The clearance the tooltip card needs above the tab bar:
    /// the distance from the pill top to the bottom of the
    /// container.
    private func tabBarClearance(proxy: GeometryProxy) -> CGFloat {
        let pill = pillRect(proxy: proxy)
        guard pill.height > 0 else { return 49 + proxy.safeAreaInsets.bottom }
        return max(0, proxy.size.height - pill.minY)
    }

    /// The spotlight animation: a short ease when motion is
    /// allowed, none when Reduce Motion is on. There is no pulsing
    /// ring: the ring is static in all cases.
    private var spotlightAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.3)
    }

    /// The tab-step spotlight animation: the same 0.7 second
    /// ease as the hand's glide, so the ring and the hand
    /// travel together between tabs. Drawer steps keep the
    /// shorter animation so the ring tracks the scrolling row
    /// without trailing behind it.
    private var tabSpotlightAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.7)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                switch phase {
                case .start:
                    startPhaseView
                case .step(let index):
                    stepPhaseView(proxy: proxy, stepIndex: index)
                case .complete:
                    completionPhaseView
                }
            }
            .frame(width: size.width, height: size.height)
            .onChange(of: phase) { _, newPhase in
                if case .step(let index) = newPhase {
                    applySideEffects(for: index)
                    accessibilityFocus = .tooltip
                }
            }
        }
        .ignoresSafeArea()
        .onDisappear {
            TourPageScroller.cancel()
            transitionGeneration += 1
            postSearchDemoReset()
        }
    }

    // MARK: - Phases

    private var startPhaseView: some View {
        ZStack {
            dimView(hole: nil)
            startCard
        }
    }

    private var completionPhaseView: some View {
        ZStack {
            dimView(hole: nil)
            completionCard
        }
    }

    @ViewBuilder
    private func stepPhaseView(proxy: GeometryProxy, stepIndex: Int) -> some View {
        if Self.steps.indices.contains(stepIndex) {
            ZStack {
                spotlightLayer(proxy: proxy, stepIndex: stepIndex)
                tooltipContainer(proxy: proxy, stepIndex: stepIndex)
            }
        } else {
            dimView(hole: nil)
        }
    }

    /// The dim, the highlight ring, and the pointing hand,
    /// animated together when the spotlight rect changes. Tab
    /// steps use a capsule hole and ring (radius half the
    /// capsule height), matching the pill and the system
    /// selection capsule, except while the Search demo runs,
    /// when the hole frames the search field instead. Drawer
    /// and card steps use a circle hole and ring on the icon
    /// alone, the same 64pt circle for Payment Simulator, Profile
    /// and Start Learning. The hand sits on the tab on tab
    /// steps, follows its drag point while a scroll showcase
    /// runs, and sits at the search field while the Search
    /// demo types and taps. On drawer and card steps the hand
    /// sits on the circled icon from the live target frame and
    /// tracks it while the drawer slides and scrolls, with no
    /// press, and stays hidden while the target is off screen.
    /// The animation is nil when Reduce
    /// Motion is on, so the spotlight jumps instantly.
    private func spotlightLayer(proxy: GeometryProxy, stepIndex: Int) -> some View {
        let spotlight = currentSpotlightRect(proxy: proxy, stepIndex: stepIndex)
        let isTabStep = Self.steps.indices.contains(stepIndex) && Self.steps[stepIndex].tabIndex != nil
        let isSearchStep = Self.steps.indices.contains(stepIndex) && Self.steps[stepIndex].tabIndex == 2
        let isCircleStep = Self.steps.indices.contains(stepIndex) && (Self.steps[stepIndex].destination != nil || Self.steps[stepIndex].highlightsCard)
        let showingFieldDemo = isSearchStep && searchDemoFieldActive && searchFieldSpotlightRect(proxy: proxy) != nil
        let radius = showingFieldDemo ? spotlightCornerRadius : (spotlight?.height ?? 0) / 2
        let tabTip: CGPoint? = spotlight.map { CGPoint(x: $0.midX - 2, y: $0.midY - 7) }
        let fieldTip: CGPoint? = {
            guard isSearchStep, searchDemoPhase != .idle, let anchor = searchFieldAnchor else { return nil }
            let field = proxy[anchor]
            guard !field.isNull, field.width > 0, field.height > 0 else { return nil }
            switch searchDemoPhase {
            case .typing:
                return CGPoint(x: field.minX + 44, y: field.midY)
            case .tapping:
                return CGPoint(x: field.minX + 22, y: field.midY)
            case .idle:
                return nil
            }
        }()
        // Circle steps point at the circled icon only, from the
        // live spotlight rect: no delayed flag, no fallback to
        // a stale drag point. When the target is off screen the
        // spotlight is nil, so there is no hand at all until
        // the drawer scroll brings the row into view: the hand
        // never sits on a guessed position.
        let circleTip: CGPoint? = {
            guard isCircleStep else { return nil }
            return spotlight.map { CGPoint(x: $0.midX - 2, y: $0.midY - 7) }
        }()
        let handTip = isCircleStep ? circleTip : (fieldTip ?? handPoint ?? (isTabStep ? tabTip : nil))
        return ZStack {
            dimView(hole: spotlight, cornerRadius: radius)
            ringView(hole: spotlight, cornerRadius: radius)
            if let handTip {
                handCursorView(tip: handTip)
                    .animation(.easeInOut(duration: 0.35), value: searchDemoPhase)
            }
            if clickRippleID != 0, let ripplePoint = isCircleStep ? circleTip : (fieldTip ?? handPoint ?? (isTabStep ? tabTip : nil)) {
                Circle()
                    .stroke(Self.tourHighlight, lineWidth: 2.5)
                    .frame(width: 44, height: 44)
                    .scaleEffect(clickRingExpanded ? 1.5 : 0.4)
                    .opacity(clickRingExpanded ? 0 : 0.9)
                    .position(x: ripplePoint.x, y: ripplePoint.y)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(isTabStep ? tabSpotlightAnimation : spotlightAnimation, value: spotlight)
    }

    /// The pointing hand with its fingertip at the given point:
    /// on the tab icon on tab steps, or at the drag point while
    /// a scroll showcase runs. The press on the click beat is
    /// applied here, outside the hand itself, so it never
    /// disturbs the bob. Fades in and out with the transaction
    /// that shows or hides it. Visual only: it never
    /// intercepts taps.
    private func handCursorView(tip: CGPoint) -> some View {
        TourHandCursor(reduceMotion: reduceMotion)
            .scaleEffect(clickTap ? 0.88 : 1.0)
            .offset(x: 0, y: clickTap ? 5 : 0)
            .animation(.easeInOut(duration: 0.15), value: clickTap)
            .position(x: tip.x + 2, y: tip.y + 14)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Dim and ring

    /// The dim: a full-rect shape with an even-odd hole around the
    /// target, or no hole when the hole rect is nil. The dim is
    /// visual only and never intercepts a tap: hit testing is
    /// off, so every tap passes through to the app underneath,
    /// including taps on the highlighted control. Only the tour
    /// cards and their buttons respond to taps.
    private func dimView(hole: CGRect?) -> some View {
        dimView(hole: hole, cornerRadius: spotlightCornerRadius)
    }

    private func dimView(hole: CGRect?, cornerRadius: CGFloat) -> some View {
        NavigationTourSpotlightShape(
            holeRect: hole ?? .zero,
            showsHole: hole != nil,
            cornerRadius: cornerRadius
        )
        .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The highlight ring tracing the spotlight hole, in the
    /// tour highlight colour with a soft glow, so it stands
    /// apart from the gold accents. It never takes part in hit
    /// testing: taps on the ring pass through to the app
    /// underneath, like every other part of the overlay except
    /// the tour cards.
    @ViewBuilder
    private func ringView(hole: CGRect?) -> some View {
        ringView(hole: hole, cornerRadius: spotlightCornerRadius)
    }

    @ViewBuilder
    private func ringView(hole: CGRect?, cornerRadius: CGFloat) -> some View {
        if let hole {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Self.tourHighlight, lineWidth: 3)
                .shadow(color: Self.tourHighlight.opacity(0.6), radius: 8, x: 0, y: 0)
                .frame(width: hole.width, height: hole.height)
                .position(x: hole.midX, y: hole.midY)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Spotlight geometry

    /// The spotlight rect for a step, or nil when there is no hole
    /// to cut (the anchor for a drawer step has not arrived yet).
    /// A nil result means the full dim with the tooltip still
    /// shown, never a crash and never a forced unwrap.
    private func currentSpotlightRect(proxy: GeometryProxy, stepIndex: Int) -> CGRect? {
        // Reading the tick subscribes this computation to the
        // settle bump, so drawer anchors re-resolve once the
        // drawer has finished opening and scrolling.
        _ = geometryTick
        guard Self.steps.indices.contains(stepIndex) else { return nil }
        let step = Self.steps[stepIndex]
        if let tabIndex = step.tabIndex {
            if tabIndex == 2, searchDemoFieldActive, let fieldRect = searchFieldSpotlightRect(proxy: proxy) {
                return fieldRect
            }
            return tabSpotlightRect(tabIndex: tabIndex, proxy: proxy)
        }
        if let destination = step.destination {
            return rowIconSpotlightRect(for: destination, proxy: proxy)
        }
        if step.highlightsCard {
            return cardIconSpotlightRect(proxy: proxy)
        }
        return nil
    }

    /// The tab spotlight rect: a capsule hugging the tab's icon
    /// and label, sized from the floating pill as measured on
    /// device (iPhone 17 Pro Max screenshot, 12 Nov 2026): the
    /// system selection capsule is 82pt wide and 57pt tall
    /// inside a 401pt wide, 63pt tall pill. Every tab gets the
    /// SAME capsule: one width for all five, never narrower
    /// than the measured 82pt, so a long label is never cut
    /// on a narrow phone and the highlights never vary in
    /// size. The capsule centre comes from the measured
    /// button when the reader found all five, else from the
    /// screenshot centre fractions. The capsule is never the
    /// raw button rect: a button spans its whole segment, and
    /// a box that size reads as a square highlight that does
    /// not match the icon space.
    /// Recomputed on every layout, so rotation and size changes
    /// move the spotlight with the tab bar.
    private func tabSpotlightRect(tabIndex: Int, proxy: GeometryProxy) -> CGRect? {
        let pill = pillRect(proxy: proxy)
        guard pill.width > 0, pill.height > 0, Self.tabCenterFractions.indices.contains(tabIndex) else { return nil }
        let centerX: CGFloat
        if tabButtonRects.count == 5, tabButtonRects.indices.contains(tabIndex) {
            centerX = localRect(tabButtonRects[tabIndex], proxy: proxy).midX
        } else {
            centerX = pill.minX + Self.tabCenterFractions[tabIndex] * pill.width
        }
        let width = max(pill.width * 0.205, 82)
        let height = pill.height * 0.90
        let rect = CGRect(x: centerX - width / 2, y: pill.midY - height / 2, width: width, height: height)
        let containerRect = CGRect(origin: .zero, size: proxy.size)
        let clipped = rect.intersection(containerRect)
        // An empty clip means the pill is not on screen: no
        // spotlight and no hand, never a zero rect that would
        // park the hand at the top-left corner.
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }

    /// The search field spotlight, used only while the Search
    /// step's typing demo runs: the field rect expanded by 6pt,
    /// so the field lights up while the hand types in it. Nil
    /// when the field anchor has not arrived yet; the tab
    /// capsule stays the spotlight then.
    private func searchFieldSpotlightRect(proxy: GeometryProxy) -> CGRect? {
        guard let anchor = searchFieldAnchor else { return nil }
        let resolved = proxy[anchor]
        guard !resolved.isNull, resolved.width > 0, resolved.height > 0 else { return nil }
        let expanded = resolved.insetBy(dx: -6, dy: -6)
        let containerRect = CGRect(origin: .zero, size: proxy.size)
        let visible = expanded.intersection(containerRect)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
        return visible
    }

    /// The drawer row spotlight: a circle on the row's icon
    /// alone, the same 64pt circle for Payment Simulator, Profile
    /// and every other drawer step. The icon is a 40pt frame
    /// starting 24pt into the row, so the circle is centred on
    /// the icon centre. The row frame comes from the live frame
    /// feed first, falling back to the resolved anchor; either
    /// way the circle follows the row while the list scrolls.
    /// Nil when the row is not actually on screen: a row below
    /// the fold, or a drawer still slid shut, must not produce
    /// a spotlight clamped to the screen edge, which is what
    /// parked the hand at the bottom-left. The drawer scroll
    /// brings the row into view, and the spotlight and hand
    /// appear on the real row once it is visible.
    private func rowIconSpotlightRect(for destination: DrawerDestination, proxy: GeometryProxy) -> CGRect? {
        let resolved: CGRect
        if let frame = drawerRowFrames[destination] {
            resolved = frame
        } else if let anchor = drawerRowAnchors[destination] {
            resolved = proxy[anchor]
        } else {
            return nil
        }
        guard isTargetVisible(resolved, in: proxy) else { return nil }
        return iconCircleRect(rowFrame: resolved, iconCenterXOffset: PFSpacing.xl + 20, proxy: proxy)
    }

    /// The Start Learning spotlight: the same 64pt circle on
    /// the card's flame icon. The icon is a 52pt circle
    /// starting 16pt into the card, so the ring sits centred
    /// on it with 6pt to spare on each side. The card frame
    /// comes from the live frame feed first, falling back to
    /// the resolved anchor, and the spotlight stays hidden
    /// until the card is actually on screen, like the rows.
    private func cardIconSpotlightRect(proxy: GeometryProxy) -> CGRect? {
        let resolved: CGRect
        if let frame = keepLearningFrame {
            resolved = frame
        } else if let anchor = keepLearningAnchor {
            resolved = proxy[anchor]
        } else {
            return nil
        }
        guard isTargetVisible(resolved, in: proxy) else { return nil }
        return iconCircleRect(rowFrame: resolved, iconCenterXOffset: PFSpacing.lg + 26, proxy: proxy)
    }

    /// True when a drawer target frame is genuinely on screen:
    /// non-empty, inside the container horizontally (a shut
    /// drawer sits a full drawer width to the left, so its
    /// rows fail here), and fully inside vertically within a
    /// small tolerance. A row still below the fold fails here
    /// until the drawer scroll lands it in view.
    private func isTargetVisible(_ frame: CGRect, in proxy: GeometryProxy) -> Bool {
        guard !frame.isNull, frame.width > 0, frame.height > 0 else { return false }
        let size = proxy.size
        guard size.width > 0, size.height > 0 else { return false }
        let tolerance: CGFloat = 8
        return frame.minX >= -tolerance
            && frame.maxX <= size.width + tolerance
            && frame.minY >= -tolerance
            && frame.maxY <= size.height + tolerance
    }

    /// The 64pt circle centred on a drawer target's icon: the
    /// icon centre is the given offset into the target frame,
    /// vertically centred on the frame. The circle itself is
    /// shifted only enough to stay on screen, which moves it
    /// off the icon by at most a few points when the target
    /// sits at an extreme edge; the target frame is already
    /// verified visible, so this never fabricates a position
    /// for an off-screen row.
    private func iconCircleRect(rowFrame: CGRect, iconCenterXOffset: CGFloat, proxy: GeometryProxy) -> CGRect {
        let diameter: CGFloat = 64
        let centerX = rowFrame.minX + iconCenterXOffset
        let centerY = min(max(rowFrame.midY, diameter / 2 + 8), proxy.size.height - diameter / 2 - 8)
        return CGRect(x: centerX - diameter / 2, y: centerY - diameter / 2, width: diameter, height: diameter)
    }

    /// The drawer row spotlight: the one uniform drawer box,
    /// centred on the row. The row's anchor supplies only the
    /// vertical centre; the size is the same for every drawer
    /// step, so the highlights never vary. Nil when the anchor
    /// is missing (the row has not laid out yet), when the
    /// resolved rect is empty, or when the row is fully off
    /// screen.
    private func drawerSpotlightRect(for destination: DrawerDestination, proxy: GeometryProxy) -> CGRect? {
        guard let anchor = drawerRowAnchors[destination] else { return nil }
        let resolved = proxy[anchor]
        guard !resolved.isNull, resolved.width > 0, resolved.height > 0 else { return nil }
        let center = CGPoint(x: drawerWidth(for: proxy.size) / 2, y: resolved.midY)
        return uniformSpotlightRect(center: center, proxy: proxy)
    }

    /// The Keep Learning card spotlight: the same uniform
    /// drawer box, centred on the card. The card's anchor
    /// supplies only the vertical centre, like the rows, so
    /// the Start Learning box is exactly the size of every
    /// other drawer highlight. Nil when the anchor is missing
    /// or the resolved rect is empty or fully off screen.
    private func cardSpotlightRect(proxy: GeometryProxy) -> CGRect? {
        guard let anchor = keepLearningAnchor else { return nil }
        let resolved = proxy[anchor]
        guard !resolved.isNull, resolved.width > 0, resolved.height > 0 else { return nil }
        let center = CGPoint(x: drawerWidth(for: proxy.size) / 2, y: resolved.midY)
        return uniformSpotlightRect(center: center, proxy: proxy)
    }

    /// The one size for every drawer-family highlight: the
    /// width spans the drawer plus 8pt on each side, and the
    /// height fits the Keep Learning card plus 8pt on each
    /// side, so the tallest target is never clipped and rows
    /// share the card's exact box. Centred on the target, and
    /// shifted, never shrunk, near the screen edges, so the
    /// size stays identical on every step.
    private func uniformSpotlightRect(center: CGPoint, proxy: GeometryProxy) -> CGRect? {
        let width = drawerWidth(for: proxy.size) + 16
        let height = uniformDrawerSpotlightHeight(proxy: proxy)
        var rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        let container = CGRect(origin: .zero, size: proxy.size)
        if rect.minX < 0 { rect.origin.x = 0 }
        if rect.maxX > container.maxX { rect.origin.x = container.maxX - rect.width }
        if rect.minY < 8 { rect.origin.y = 8 }
        if rect.maxY > container.maxY - 8 { rect.origin.y = container.maxY - 8 - rect.height }
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    /// The uniform drawer highlight height: the Keep Learning
    /// card's live height plus 8pt on each side, so the box
    /// fits the tallest drawer target on any device and text
    /// size. Falls back to the measured 139pt when the card
    /// anchor has not arrived yet.
    private func uniformDrawerSpotlightHeight(proxy: GeometryProxy) -> CGFloat {
        if let anchor = keepLearningAnchor {
            let card = proxy[anchor]
            if !card.isNull, card.height > 0 {
                return card.height + 16
            }
        }
        return 139
    }

    // MARK: - Tooltip placement

    /// The drawer panel width. This mirrors the formula in
    /// DrawerContainer and is used only to decide whether the
    /// tooltip fits beside the drawer. The spotlight itself uses
    /// the row anchors, never this width.
    private func drawerWidth(for size: CGSize) -> CGFloat {
        min(size.width * 0.85, 360)
    }

    /// Decides where the tooltip card goes, from the step kind, the
    /// spotlight rect, and the container size. Tab steps sit above
    /// the tab bar. Drawer steps prefer the space to the right of
    /// the drawer when at least 280pt of width is free there, else
    /// above the row when the row is in the lower half and below
    /// the row when it is in the upper half. With no row frame yet
    /// the card is centered over the full dim. No position is
    /// hardcoded: every placement derives from live geometry.
    private func placement(for stepIndex: Int, spotlight: CGRect?, size: CGSize) -> TooltipPlacement {
        guard Self.steps.indices.contains(stepIndex) else { return .centered }
        let step = Self.steps[stepIndex]
        if step.tabIndex != nil {
            return .aboveTabBar
        }
        guard let spotlight else {
            return .centered
        }
        if size.width - drawerWidth(for: size) >= 280 {
            return .rightOfDrawer
        }
        if spotlight.midY > size.height / 2 {
            return .aboveRow
        }
        return .belowRow
    }

    /// The tooltip card placed by the placement decision. Spacer
    /// heights derive from the strip height or the spotlight rect,
    /// so the card never covers the highlighted control and stays
    /// inside the screen bounds and safe area. Every spacer and
    /// filler ignores taps: only the card itself is hittable, so
    /// the rest of the app stays fully tappable during the tour.
    @ViewBuilder
    private func tooltipContainer(proxy: GeometryProxy, stepIndex: Int) -> some View {
        let size = proxy.size
        let spotlight = currentSpotlightRect(proxy: proxy, stepIndex: stepIndex)
        switch placement(for: stepIndex, spotlight: spotlight, size: size) {
        case .aboveTabBar:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                tooltipCard(stepIndex: stepIndex)
                    .padding(.horizontal, PFSpacing.lg)
                Color.clear
                    .frame(height: tabBarClearance(proxy: proxy) + PFSpacing.md)
                    .allowsHitTesting(false)
            }
            .padding(.top, proxy.safeAreaInsets.top)
        case .rightOfDrawer:
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: drawerWidth(for: size) + PFSpacing.md)
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                tooltipCard(stepIndex: stepIndex)
                    .frame(maxWidth: 360)
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, PFSpacing.lg)
            .padding(.top, proxy.safeAreaInsets.top + PFSpacing.sm)
            .padding(.bottom, proxy.safeAreaInsets.bottom + PFSpacing.sm)
        case .aboveRow:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                tooltipCard(stepIndex: stepIndex)
                    .padding(.horizontal, PFSpacing.lg)
                Color.clear
                    .frame(height: max(0, size.height - (spotlight?.minY ?? size.height) + PFSpacing.md))
                    .allowsHitTesting(false)
            }
        case .belowRow:
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: (spotlight?.maxY ?? 0) + PFSpacing.md)
                    .allowsHitTesting(false)
                tooltipCard(stepIndex: stepIndex)
                    .padding(.horizontal, PFSpacing.lg)
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
        case .centered:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                tooltipCard(stepIndex: stepIndex)
                    .padding(.horizontal, PFSpacing.lg)
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .padding(.top, proxy.safeAreaInsets.top)
            .padding(.bottom, proxy.safeAreaInsets.bottom)
        }
    }

    // MARK: - Cards

    /// The tooltip card: title, progress, explanation, and the
    /// Back, Next and Skip Tour buttons. The text block is ONE
    /// accessibility element (title, body and progress combined),
    /// and VoiceOver focus moves to it when the step changes. The
    /// buttons stay separate elements. Content wraps and the card
    /// width caps at the container width minus padding, so larger
    /// Dynamic Type sizes wrap instead of clipping.
    private func tooltipCard(stepIndex: Int) -> some View {
        let step = Self.steps[stepIndex]
        return VStack(alignment: .leading, spacing: PFSpacing.md) {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: step.symbol)
                        .font(.pfCallout)
                        .foregroundColor(.pfGold)
                        .accessibilityHidden(true)
                    Text(step.title)
                        .font(.pfCallout.weight(.semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text("\(stepIndex + 1) of 8")
                        .font(.pfCaptionBold)
                        .foregroundColor(.white.opacity(0.8))
                }
                GeometryReader { barProxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                        Capsule()
                            .fill(Color.pfGold)
                            .frame(width: barProxy.size.width * CGFloat(stepIndex + 1) / 8)
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
                Text(step.body)
                    .font(.pfCaption)
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityFocused($accessibilityFocus, equals: .tooltip)
            HStack(spacing: PFSpacing.sm) {
                tourOutlineButton(title: "Back") {
                    goBack(from: stepIndex)
                }
                tourGoldButton(title: "Next") {
                    goNext(from: stepIndex)
                }
            }
            tourTextButton(title: "Skip Tour", action: onFinish)
        }
        .padding(PFSpacing.lg)
        .frame(maxWidth: 480)
        .background(Color.pfNavy.opacity(0.75))
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: PFSpacing.cardRadius))
        .onTapGesture {}
        .id("tour-tooltip-\(stepIndex)")
        .onAppear {
            applySideEffects(for: stepIndex)
            accessibilityFocus = .tooltip
        }
    }

    /// The start card: centered premium navy card, full-screen dim
    /// behind it, no spotlight.
    private var startCard: some View {
        VStack(spacing: PFSpacing.lg) {
            VStack(spacing: PFSpacing.sm) {
                Text("Payments Training Hub")
                    .font(.system(.title2, design: .default).weight(.bold))
                    .foregroundColor(.pfGold)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
                Text("Welcome!")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Take a quick tour of the key areas of the app. It only takes a minute. The app stays fully usable while the tour runs.")
                    .font(.pfCaption)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityFocused($accessibilityFocus, equals: .startCard)
            tourGoldButton(title: "Start Tour", action: startTour)
            tourTextButton(title: "Skip Tour", action: onFinish)
        }
        .padding(PFSpacing.xl)
        .frame(maxWidth: 480)
        .background(Color.pfNavy.opacity(0.75))
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
        .padding(.horizontal, PFSpacing.lg)
        .contentShape(RoundedRectangle(cornerRadius: PFSpacing.cardRadius))
        .onTapGesture {}
        .onAppear {
            accessibilityFocus = .startCard
        }
    }

    /// The completion screen: centered navy card, full-screen dim
    /// behind it, no spotlight.
    private var completionCard: some View {
        VStack(spacing: PFSpacing.lg) {
            VStack(spacing: PFSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.pfGold)
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark")
                        .font(.system(.title3, design: .default).weight(.bold))
                        .foregroundColor(.pfNavy)
                }
                .accessibilityHidden(true)
                Text("You're all set!")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You've explored the key areas of Payments Training Hub. You can revisit this tour anytime from Help & Support.")
                    .font(.pfCaption)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityFocused($accessibilityFocus, equals: .completionCard)
            tourGoldButton(title: "Explore the Platform", action: onFinish)
            tourOutlineButton(title: "Replay Tour", action: replayTour)
        }
        .padding(PFSpacing.xl)
        .frame(maxWidth: 480)
        .background(Color.pfNavy.opacity(0.75))
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
        .padding(.horizontal, PFSpacing.lg)
        .contentShape(RoundedRectangle(cornerRadius: PFSpacing.cardRadius))
        .onTapGesture {}
        .onAppear {
            accessibilityFocus = .completionCard
        }
    }

    /// A white outline button for the navy cards: Back and Replay
    /// Tour. Real Button, full tap height, wraps with Dynamic Type.
    private func tourOutlineButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.pfCaptionBold)
            .foregroundColor(.white)
            .padding(.vertical, PFSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.white.opacity(0.10))
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
    }

    /// A plain text button for the navy cards: Skip Tour. Real
    /// Button with a full-width 44pt tap area.
    private func tourTextButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.pfCaptionBold)
            .foregroundColor(.white.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    /// The gold primary button for the tour cards: the same gold
    /// styling as PFGoldButton with smaller text to match the
    /// tour cards. Tour-local on purpose: the shared button keeps
    /// its size everywhere else in the app.
    private func tourGoldButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.pfCaptionBold)
                .foregroundColor(.pfNavy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.pfGold)
                .cornerRadius(PFSpacing.cornerRadius)
                .shadow(color: Color.pfGold.opacity(0.45), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(PFCardButtonStyle())
    }

    // MARK: - Navigation side effects and actions

    /// Applies the navigation side effects for a step. Tab steps
    /// close the drawer and clear the scroll target at once, then
    /// run the transition sequence: the hand glides to the tab
    /// over 0.7 seconds, presses it like a tap with an expanding
    /// ring, and only then does the tab switch and the page
    /// scroll through its content and back to the top. The
    /// sequence runs once per step entry: repeat calls for the
    /// same step re-apply the immediate bits and nothing else.
    /// With Reduce Motion the tab switches at once and there is
    /// no glide, click, or page scroll. Drawer and card steps
    /// open the drawer and circle the row or card icon from its
    /// live frame, and the hand points at the icon from the
    /// same frame: no press, no activation. Drawer steps pulse
    /// the scroll target and then open the drawer, so the
    /// drawer list re-issues its scroll into view on every
    /// entry, and schedule geometry re-resolves after the slide
    /// and scroll finish, so the spotlight lands on the settled
    /// row. A row that has not scrolled into view yet gets no
    /// spotlight and no hand. The drawer opens with a spring,
    /// matching DrawerContainer, or instantly when Reduce Motion
    /// is on. Called from every step-change action, from the phase
    /// change, and from the tooltip card appearance, so Back, Next
    /// and Replay all land correctly. Setting the same values
    /// twice is harmless: the bindings hold the same result.
    private func applySideEffects(for index: Int) {
        guard Self.steps.indices.contains(index) else { return }
        let step = Self.steps[index]
        // Every step entry clears a leftover demo query, so the
        // Search page never keeps one after the demo, and a
        // fresh Search visit starts from an empty field. Steps
        // other than Search also stand the demo down. The
        // drawer hand needs no standing down: it derives from
        // the live spotlight rect, so it follows the current
        // step's target and vanishes when the target is off
        // screen.
        postSearchDemoReset()
        if step.tabIndex != 2 {
            searchDemoFieldActive = false
            searchDemoPhase = .idle
        }
        if let tabIndex = step.tabIndex {
            isDrawerOpen = false
            drawerScrollTarget = nil
            guard sequencedStep != index else { return }
            sequencedStep = index
            handPoint = nil
            if reduceMotion {
                selectedTab = tabIndex
                return
            }
            transitionGeneration += 1
            let myGeneration = transitionGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                guard myGeneration == transitionGeneration else { return }
                withAnimation(.easeInOut(duration: 0.15)) { clickTap = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard myGeneration == transitionGeneration else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { clickTap = false }
                    showClickRipple()
                    selectedTab = tabIndex
                    if tabIndex == 2 {
                        // Search step: show the Search screen
                        // only. No typing demo, no scroll. The
                        // hand stays on the tab.
                    } else if tabIndex == 3 {
                        // Payment Cases: the list renders its
                        // ContentManifest.situationCount rows lazily, so a full traverse
                        // outruns the rendering and flashes
                        // white gaps. A shallow scroll shows
                        // the top of the page with a gentle
                        // down and back, inside the rows that
                        // are already rendered.
                        TourPageScroller.scrollThroughPage(shallow: true)
                        let drag = pageDragPoints(lift: 100)
                        Task {
                            await runHandDrag(
                                legs: [(drag.center, 0.4), (drag.raised, 1.8), (drag.raised, 0.5), (drag.center, 1.6)],
                                generation: myGeneration
                            )
                        }
                    } else {
                        // The page itself scrolls through its
                        // content at a medium pace and back to the
                        // top, like a human scrolling, so the step
                        // shows the page, not just its tab. The
                        // same for every tab, Home included. The
                        // hand drags the scroll in step with the
                        // page, so the scroll is shown, not just
                        // felt: it glides onto the page, drags up
                        // while the content scrolls down, pauses,
                        // drags back down while the content returns
                        // to the top, then returns to its tab.
                        TourPageScroller.scrollThroughPage()
                        let drag = pageDragPoints()
                        Task {
                            await runHandDrag(
                                legs: [(drag.center, 0.4), (drag.raised, 1.8), (drag.raised, 0.35), (drag.center, 1.6)],
                                generation: myGeneration
                            )
                        }
                    }
                }
            }
        } else if let destination = step.destination {
            TourPageScroller.cancel()
            // Release any drag point left over from a tab
            // step, so the hand never lands mid-screen here.
            handPoint = nil
            // Pulse the scroll target through nil so the
            // drawer list re-issues its scroll on every entry
            // to this step, including re-entering the same row
            // step: setting the same value twice would not
            // retrigger the drawer's scroll task. The delayed
            // set is guarded by the phase, so a fast Next or
            // Back never resurrects a stale target. The drawer
            // opens at once, without waiting for the pulse.
            drawerScrollTarget = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard phase == .step(index) else { return }
                drawerScrollTarget = destination
            }
            if reduceMotion {
                isDrawerOpen = true
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isDrawerOpen = true
                }
            }
            // The drawer slide and the scroll into view both
            // animate, so the row frames only settle after
            // them. Bump the tick as the slide finishes and
            // after the scroll passes, so the anchor fallback
            // re-resolves against the settled layout; the live
            // frame feed refreshes on its own as the row moves.
            // The hand points at the circled icon from the
            // live frame, without pressing or activating the
            // row, and stays hidden until the row is visible.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                geometryTick += 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                geometryTick += 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                geometryTick += 1
            }
            guard sequencedStep != index else { return }
            sequencedStep = index
            // A new generation so any pending tab sequence
            // (scroll showcase or search demo) aborts.
            transitionGeneration += 1
        } else if step.highlightsCard {
            // The card is fixed at the bottom of the drawer, so
            // no scroll is needed: open the drawer and spotlight
            // the card once the slide settles.
            TourPageScroller.cancel()
            // Release any drag point left over from a tab
            // step, so the hand never lands mid-screen here.
            handPoint = nil
            drawerScrollTarget = nil
            if reduceMotion {
                isDrawerOpen = true
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isDrawerOpen = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                geometryTick += 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                geometryTick += 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                geometryTick += 1
            }
            guard sequencedStep != index else { return }
            sequencedStep = index
            // A new generation so any pending tab sequence
            // (scroll showcase or search demo) aborts. The
            // hand points at the circled card icon from the
            // live frame once the drawer slide settles,
            // without pressing or activating the card.
            transitionGeneration += 1
        }
    }

    /// Shows the expanding ring at the fingertip for one click
    /// beat: the ring appears small, expands and fades over
    /// 0.45 seconds, then hides. The ripple id guards both
    /// delayed steps, so a newer click is never cut short by
    /// an older click's hide.
    private func showClickRipple() {
        clickRippleID += 1
        let rippleID = clickRippleID
        clickRingExpanded = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard rippleID == clickRippleID else { return }
            withAnimation(.easeOut(duration: 0.45)) { clickRingExpanded = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard rippleID == clickRippleID else { return }
            clickRippleID = 0
            clickRingExpanded = false
        }
    }

    /// Clears a leftover demo query from the Search page. The
    /// reset only clears when the field still holds exactly the
    /// demo query, so the learner's own typing is never wiped.
    private func postSearchDemoReset() {
        NotificationCenter.default.post(
            name: .tourSearchDemoReset,
            object: nil,
            userInfo: ["query": Self.searchDemoQuery]
        )
    }

    /// Dormant: the Search step currently shows the screen
    /// only, with no typing demo and no scroll. Kept so the
    /// demo can return without rebuilding.
    /// The Search step demo: the field lights up, the hand moves
    /// to it, the query types itself in character by character,
    /// the hand taps the search icon, and the results run. The
    /// field is never focused, so no keyboard covers the page.
    /// No scroll showcase on this step. Aborts silently when a
    /// newer step takes over; the reset posted by the next step
    /// clears the demo query.
    private func runSearchDemo(generation: Int) {
        let demoQuery = Self.searchDemoQuery
        Task { @MainActor in
            guard generation == transitionGeneration else { return }
            searchDemoFieldActive = true
            searchDemoPhase = .typing
            try? await Task.sleep(nanoseconds: 400_000_000)
            var typed = ""
            for character in demoQuery {
                guard generation == transitionGeneration else { return }
                typed.append(character)
                NotificationCenter.default.post(
                    name: .tourSearchDemoType,
                    object: nil,
                    userInfo: ["text": typed, "full": demoQuery, "run": generation]
                )
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            guard generation == transitionGeneration else { return }
            searchDemoPhase = .tapping
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard generation == transitionGeneration else { return }
            withAnimation(.easeInOut(duration: 0.15)) { clickTap = true }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard generation == transitionGeneration else { return }
            withAnimation(.easeInOut(duration: 0.15)) { clickTap = false }
            showClickRipple()
            NotificationCenter.default.post(
                name: .tourSearchDemoSubmit,
                object: nil,
                userInfo: ["query": demoQuery, "run": generation]
            )
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard generation == transitionGeneration else { return }
            searchDemoFieldActive = false
            searchDemoPhase = .idle
        }
    }

    /// The fingertip points for a tab page scroll showcase, in
    /// screen coordinates: the centre of the page, and the
    /// raised point the hand drags to while the content scrolls
    /// down. The overlay fills the screen, so screen points
    /// match its space. A shallow showcase lifts less, matching
    /// its shorter scroll.
    private func pageDragPoints(lift: CGFloat = 200) -> (center: CGPoint, raised: CGPoint) {
        let bounds = UIScreen.main.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY - 40)
        return (center, CGPoint(x: bounds.midX, y: bounds.midY - 40 - lift))
    }

    /// Runs the hand through a scroll showcase: each leg moves
    /// the fingertip to a point over its duration, in step with
    /// the page scroll it demonstrates. A leg that
    /// repeats the previous point is a pause. Aborts silently
    /// when a newer step takes over; the new step owns the hand
    /// from there. Ends by releasing the hand back to its tab
    /// (tab steps) or fading it out (drawer and card steps).
    private func runHandDrag(legs: [(point: CGPoint, duration: Double)], generation: Int) async {
        for leg in legs {
            guard generation == transitionGeneration else {
                // Abandoned mid-drag: release the hand, or the
                // stale point hijacks the next step's hand.
                handPoint = nil
                return
            }
            withAnimation(.easeInOut(duration: leg.duration)) { handPoint = leg.point }
            try? await Task.sleep(nanoseconds: UInt64(leg.duration * 1_000_000_000))
        }
        guard generation == transitionGeneration else {
            handPoint = nil
            return
        }
        withAnimation(.easeInOut(duration: 0.4)) { handPoint = nil }
    }

    private func startTour() {
        phase = .step(0)
        applySideEffects(for: 0)
        accessibilityFocus = .tooltip
    }

    private func goToStep(_ index: Int) {
        phase = .step(index)
        applySideEffects(for: index)
        accessibilityFocus = .tooltip
    }

    private func goBack(from index: Int) {
        if index == 0 {
            TourPageScroller.cancel()
            transitionGeneration += 1
            sequencedStep = nil
            postSearchDemoReset()
            phase = .start
            accessibilityFocus = .startCard
        } else {
            goToStep(index - 1)
        }
    }

    private func goNext(from index: Int) {
        if index >= Self.steps.count - 1 {
            TourPageScroller.cancel()
            transitionGeneration += 1
            sequencedStep = nil
            postSearchDemoReset()
            phase = .complete
            accessibilityFocus = .completionCard
        } else {
            goToStep(index + 1)
        }
    }

    private func replayTour() {
        goToStep(0)
    }
}
