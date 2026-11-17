// LessonDiagramView.swift
// Payments Training Hub iOS - Renders a lesson diagram SVG as a real visual.
// The SVG comes from the lesson page (ContentService extracts it from
// the studio-canvas div). It is shown in a WKWebView so the vector
// artwork renders exactly as on the website, scaled to the phone width,
// with the beat that matches the current narration time highlighted.
// No em dashes in any user-facing text.

import SwiftUI
import WebKit

// MARK: - Lesson diagram view

/// Renders the given SVG string as a real visual. The active beat is
/// highlighted: groups for other beats are dimmed, the active beat stays
/// at full opacity. Pass a negative activeBeat to show every beat at
/// full opacity.
struct LessonDiagramView: View {
    let svg: String
    let activeBeat: Int

    /// Height reported by JavaScript after the SVG renders.
    @State private var contentHeight: CGFloat? = nil

    init(svg: String, activeBeat: Int) {
        self.svg = svg
        self.activeBeat = activeBeat
    }

    /// Width over height from the SVG viewBox, used to size the view
    /// before JavaScript reports the true rendered height.
    private var aspectRatioValue: CGFloat? {
        guard let viewBoxRange = svg.range(of: "viewBox=\"") else { return nil }
        let afterQuote = svg[viewBoxRange.upperBound...]
        guard let endQuote = afterQuote.firstIndex(of: "\"") else { return nil }
        let numbers = afterQuote[..<endQuote]
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
        guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
        return CGFloat(numbers[2] / numbers[3])
    }

    var body: some View {
        DiagramWebView(svg: svg, activeBeat: activeBeat, contentHeight: $contentHeight)
            .aspectRatio(aspectRatioValue, contentMode: .fit)
            .frame(minHeight: 120)
            .frame(height: contentHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityAddTraits(.isImage)
    }

    /// The spoken description of the diagram: how many points it has
    /// and which point is highlighted, counted from the data-beat
    /// markers in the SVG itself. Falls back to a plain label when
    /// the SVG carries no beat markers. Rendering is untouched.
    private var accessibilityDescription: String {
        let beatNumbers = beatNumbersInSVG
        guard !beatNumbers.isEmpty else { return "Lesson diagram" }
        let count = beatNumbers.count
        if activeBeat >= 0, beatNumbers.contains(activeBeat) {
            return "Lesson diagram with \(count) points, point \(activeBeat + 1) highlighted"
        }
        return "Lesson diagram with \(count) points, no point highlighted"
    }

    /// The distinct beat numbers in the SVG, from data-beat="N"
    /// markers, in ascending order. Empty when the SVG has none.
    private var beatNumbersInSVG: [Int] {
        var found = Set<Int>()
        var searchFrom = svg.startIndex
        while let marker = svg.range(of: "data-beat=\"", range: searchFrom..<svg.endIndex) {
            let after = svg[marker.upperBound...]
            let digits = after.prefix(while: { $0.isNumber })
            if let value = Int(digits) {
                found.insert(value)
            }
            searchFrom = marker.upperBound
        }
        return found.sorted()
    }

    // MARK: - Web view

    private struct DiagramWebView: UIViewRepresentable {
        let svg: String
        let activeBeat: Int
        @Binding var contentHeight: CGFloat?

        func makeCoordinator() -> Coordinator {
            Coordinator(activeBeat: activeBeat, loadedSVG: svg) { [contentHeight = $contentHeight] height in
                DispatchQueue.main.async {
                    // Write only on a real change: the page
                    // reports its height on every resize, and the
                    // frame follows this value, so an
                    // unconditional write feeds resize reports
                    // back into resizes without end.
                    if contentHeight.wrappedValue != height {
                        contentHeight.wrappedValue = height
                    }
                }
            }
        }

        func makeUIView(context: Context) -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.userContentController.add(context.coordinator, name: "pfHeight")
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = context.coordinator
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.isScrollEnabled = false
            webView.scrollView.bounces = false
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.isUserInteractionEnabled = false
            webView.loadHTMLString(Self.wrappedHTML(for: svg), baseURL: nil)
            return webView
        }

        func updateUIView(_ webView: WKWebView, context: Context) {
            context.coordinator.activeBeat = activeBeat
            if context.coordinator.loadedSVG != svg {
                context.coordinator.loadedSVG = svg
                webView.loadHTMLString(Self.wrappedHTML(for: svg), baseURL: nil)
            } else {
                Task { _ = try? await webView.evaluateJavaScript("setActiveBeat(\(activeBeat))") }
            }
        }

        /// Minimal wrapper HTML: the SVG scales to the view width,
        /// transparent background, no scrolling, no zoom.
        static func wrappedHTML(for svg: String) -> String {
            """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
            <style>
            html, body { margin: 0; padding: 0; background: transparent; }
            body { -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; }
            svg { display: block; width: 100%; height: auto; }
            </style>
            </head>
            <body>
            \(svg)
            <script>
            function setActiveBeat(i) {
              var items = document.querySelectorAll('svg [data-beat]');
              var hasMatch = false;
              items.forEach(function(el) {
                if (parseInt(el.getAttribute('data-beat'), 10) === i) { hasMatch = true; }
              });
              items.forEach(function(el) {
                var beat = parseInt(el.getAttribute('data-beat'), 10);
                el.style.opacity = (i < 0 || !hasMatch || beat === i) ? '1' : '0.35';
              });
            }
            function reportHeight() {
              var svg = document.querySelector('svg');
              if (svg) {
                window.webkit.messageHandlers.pfHeight.postMessage(svg.getBoundingClientRect().height);
              }
            }
            window.addEventListener('resize', reportHeight);
            reportHeight();
            </script>
            </body>
            </html>
            """
        }

        // MARK: - Coordinator

        final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
            var activeBeat: Int
            var loadedSVG: String
            var onHeight: ((CGFloat) -> Void)?

            init(activeBeat: Int, loadedSVG: String, onHeight: @escaping (CGFloat) -> Void) {
                self.activeBeat = activeBeat
                self.loadedSVG = loadedSVG
                self.onHeight = onHeight
            }

            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
                guard message.name == "pfHeight",
                      let height = message.body as? Double, height > 0 else { return }
                onHeight?(CGFloat(height))
            }

            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                Task { _ = try? await webView.evaluateJavaScript("reportHeight(); setActiveBeat(\(activeBeat));") }
            }
        }
    }
}
