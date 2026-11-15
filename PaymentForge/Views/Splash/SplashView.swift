// SplashView.swift
// Payments Training Hub iOS - Launch splash screen.
// Matches the first board's dark navy Home/splash: deep navy
// gradient, the gold PF monogram, the Payments Training Hub wordmark and the
// "Master Banking and Payments" tagline, with a subtle bank
// illustration drawn from SF Symbols and shapes only. No raster
// image, no AI-generated image. Shown briefly on launch, then the
// main tab view takes over. No em dashes in any user-facing text.

import SwiftUI

/// The splash screen shown briefly at launch. It is a plain view,
/// not a launch storyboard: MainTabView presents it as an overlay
/// and dismisses it after a short delay, so it can never trap the
/// user on a loading screen.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color.pfHeroGradient
                .ignoresSafeArea()

            VStack(spacing: PFSpacing.xl) {
                Spacer()

                // Gold PF monogram tile, the established app identity.
                Text("PF")
                    .font(.system(.largeTitle, design: .default).weight(.bold))
                    .foregroundColor(.pfNavy)
                    .frame(width: 96, height: 96)
                    .background(Color.pfGold)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 8)
                    .accessibilityLabel("Payments Training Hub")

                VStack(spacing: PFSpacing.sm) {
                    Text("Payments Training Hub")
                        .font(.system(.largeTitle, design: .default).weight(.bold))
                        .foregroundColor(.white)
                    Text("Master Banking and Payments")
                        .font(.pfBody)
                        .foregroundColor(.white.opacity(0.85))
                }

                // Subtle bank illustration: SF Symbols in translucent
                // circles, a bank, a card and a transfer arrow.
                HStack(spacing: PFSpacing.lg) {
                    splashSymbol("building.columns.fill")
                    splashSymbol("creditcard.fill")
                    splashSymbol("arrow.left.arrow.right")
                }
                .padding(.top, PFSpacing.md)

                Spacer()

                VStack(spacing: PFSpacing.sm) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .accessibilityLabel("Loading Payments Training Hub")
                    Text("Loading your course...")
                        .font(.pfBody)
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.bottom, PFSpacing.xxl)
            }
            .padding(PFSpacing.xl)
        }
        .onAppear {
            // Launch analytics, at most once per process and only
            // with consent. The service gates on consent itself.
            AnalyticsService.shared.recordAppLaunch()
        }
    }

    private func splashSymbol(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(.title2, design: .default))
            .foregroundColor(.white)
            .frame(width: 56, height: 56)
            .background(Color.white.opacity(0.12))
            .clipShape(Circle())
            .overlay(
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}
