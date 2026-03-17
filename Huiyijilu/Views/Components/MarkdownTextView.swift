//
//  MarkdownTextView.swift
//  Huiyijilu
//
//  Renders Markdown-formatted text using AttributedString for proper bold/italic/header display.
//

import SwiftUI

/// A SwiftUI view that renders Markdown text using AttributedString.
/// Supports: **bold**, *italic*, `code`, ## headings, - list items.
/// Falls back to plain text if parsing fails.
struct MarkdownText: View {
    let text: String
    var font: Font = .body
    var lineSpacing: CGFloat = 5

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .font(font)
                .lineSpacing(lineSpacing)
        } else {
            Text(text)
                .font(font)
                .lineSpacing(lineSpacing)
        }
    }
}
