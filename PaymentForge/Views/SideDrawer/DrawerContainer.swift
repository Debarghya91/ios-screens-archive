// DrawerContainer.swift
// Payments Training Hub iOS - The side drawer container.
// Slides the drawer in from the left over the main content and slides it
// back out to close, with a dimmed background behind it. Tap the dimmed
// background or swipe left on the drawer to close it. Swipe right from
// the left edge of the main content to open it.
// No em dashes in any user-facing text.

import SwiftUI
import UIKit

/// Device safe-area insets read from the key window, for views that
/// ignore the safe area (the drawer panel) and so cannot read the insets
/// from the environment. Falls back to the notched-iPhone values when no
/// key window is available yet.
enum PFWindowSafeArea {
    static var top: CGFloat {
        keyWindow?.safeAreaInsets.top ?? 47
    }

    static var bottom: CGFloat {
        keyWindow?.safeAreaInsets.bottom ?? 20
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

/// Wraps the main content and presents the side drawer over it.
/// Place this around the app's root content and pass a binding that
/// controls whether the drawer is open.
struct DrawerContainer<Content: View>: View {
    @Binding var isOpen: Bool
    /// Called when a drawer row is selected, after the drawer closes.
    var onSelect: (DrawerDestination) -> Void
    /// The currently selected tab, passed through to the drawer so
    /// the row for the current tab shows the active state. Nil means
    /// no row is active.
    var selectedTab: Int? = nil
    /// The drawer row the guided tour wants scrolled into view, if
    /// any. Passed through to the drawer list; nil when the tour is
    /// not running or is on a tab step.
    var tourScrollTarget: DrawerDestination? = nil
    let content: Content

    @State private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The slide animation for opening and closing the drawer. No
    /// animation when Reduce Motion is on: the drawer appears and
    /// disappears instantly instead of sliding.
    private var drawerAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)
    }

    init(
        isOpen: Binding<Bool>,
        onSelect: @escaping (DrawerDestination) -> Void,
        selectedTab: Int? = nil,
        tourScrollTarget: DrawerDestination? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self._isOpen = isOpen
        self.onSelect = onSelect
        self.selectedTab = selectedTab
        self.tourScrollTarget = tourScrollTarget
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = min(geometry.size.width * 0.85, 360)

            ZStack(alignment: .leading) {
                // Main content.
                content
                    .disabled(isOpen)
                    // Swipe right from the left edge to open the drawer.
                    .gesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .global)
                            .onEnded { value in
                                if !isOpen
                                    && value.startLocation.x < 24
                                    && value.translation.width > 60 {
                                    withAnimation(drawerAnimation) {
                                        isOpen = true
                                    }
                                }
                            }
                    )

                // Dimmed background behind the drawer. Tap to close.
                if isOpen || dragOffset != 0 {
                    Color.black.opacity(isOpen ? 0.45 : 0)
                        .ignoresSafeArea()
                        .onTapGesture {
                            close()
                        }
                        .accessibilityLabel("Close menu")
                        .accessibilityHint("Closes the navigation menu.")
                        .accessibilityAddTraits(.isButton)
                }

                // The drawer panel.
                SideDrawerView(onSelect: { destination in
                    close()
                    // Wait for the close animation before navigating.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onSelect(destination)
                    }
                }, selectedTab: selectedTab, tourScrollTarget: tourScrollTarget)
                .frame(width: drawerWidth)
                .ignoresSafeArea(edges: .vertical)
                .offset(x: isOpen ? dragOffset : -drawerWidth + dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Only allow dragging left (closing direction).
                            if value.translation.width < 0 {
                                dragOffset = value.translation.width
                            }
                        }
                        .onEnded { value in
                            if value.translation.width < -60 {
                                close()
                            } else {
                                withAnimation(drawerAnimation) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
            }
        }
    }

    private func close() {
        withAnimation(drawerAnimation) {
            isOpen = false
            dragOffset = 0
        }
    }
}

// MARK: - Menu button

/// The hamburger button that opens the drawer. Place it in the
/// navigation bar of the root screens. The visible circle stays
/// 40 points, with a 44-point tap area around it.
struct DrawerMenuButton: View {
    @Binding var isDrawerOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                isDrawerOpen = true
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.pfCardTitle.weight(.semibold))
                .foregroundColor(.pfNavy)
                .frame(width: 40, height: 40)
                .background(Color.pfCard)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .pfDecorative()
        }
        .accessibilityLabel("Open menu")
        .accessibilityHint("Opens the navigation menu.")
    }
}
