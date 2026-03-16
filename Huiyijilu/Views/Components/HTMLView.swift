//
//  HTMLView.swift
//  Huiyijilu
//
//  Renders HTML content from Bailian workflow using WKWebView.
//

import SwiftUI
import WebKit

/// Renders an HTML string in a WKWebView that auto-sizes to content height.
struct HTMLView: UIViewRepresentable {
    let html: String
    @Binding var dynamicHeight: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Uses CSS media queries for dark/light mode — no Swift trait-collection hacks needed.
        let wrapped = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
        <style>
          :root {
            color-scheme: light dark;
          }
          body {
            font-family: -apple-system, "SF Pro Text", sans-serif;
            font-size: 15px;
            line-height: 1.6;
            color: #000;
            background: #fff;
            margin: 0; padding: 12px;
            word-break: break-word;
          }
          @media (prefers-color-scheme: dark) {
            body { color: #F2F2F7; background: #1C1C1E; }
            th, td { border-color: #38383A; }
            code, pre { background: #2C2C2E; }
            blockquote { border-left-color: #8E8E93; color: #8E8E93; }
            hr { border-top-color: #38383A; }
          }
          h1 { font-size: 20px; font-weight: 700; margin: 16px 0 8px; }
          h2 { font-size: 17px; font-weight: 600; margin: 14px 0 6px; }
          h3 { font-size: 15px; font-weight: 600; margin: 10px 0 4px; }
          p  { margin: 6px 0; }
          ul, ol { padding-left: 20px; margin: 6px 0; }
          li { margin: 3px 0; }
          table {
            width: 100%; border-collapse: collapse; margin: 10px 0; font-size: 14px;
          }
          th, td {
            border: 1px solid #D1D1D6; padding: 6px 10px; text-align: left;
          }
          th { font-weight: 600; }
          code {
            background: #F2F2F7; border-radius: 4px;
            padding: 1px 4px; font-family: "SF Mono", monospace; font-size: 13px;
          }
          pre { background: #F2F2F7; border-radius: 8px; padding: 10px; overflow-x: auto; }
          pre code { padding: 0; background: none; }
          blockquote {
            border-left: 3px solid #6C6C70;
            margin: 8px 0; padding: 4px 12px; color: #6C6C70;
          }
          a { color: #0A84FF; }
          hr { border: none; border-top: 1px solid #D1D1D6; margin: 12px 0; }
        </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
        webView.loadHTMLString(wrapped, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: HTMLView

        init(_ parent: HTMLView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Measure actual content height
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, _ in
                DispatchQueue.main.async {
                    if let height = result as? CGFloat {
                        self.parent.dynamicHeight = max(height, 40)
                    }
                }
            }
        }
    }
}

// MARK: - Convenience wrapper that handles its own height state

/// Drop-in view: auto-expands to the HTML content's natural height.
struct AutoHeightHTMLView: View {
    let html: String
    @State private var height: CGFloat = 200

    var body: some View {
        HTMLView(html: html, dynamicHeight: $height)
            .frame(height: height)
    }
}
