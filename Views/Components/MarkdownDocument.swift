import SwiftUI

/// A small native Markdown reader. HTML, embedded images and tables remain source text.
struct MarkdownDocument: View {
    let source: String
    var baseURL: URL?
    private var blocks: [Block] {
        var result: [Block] = []
        var code: [String] = []
        var inCode = false
        for line in source.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if inCode { result.append(Block(text: code.joined(separator: "\n"), style: .code)); code = [] }
                inCode.toggle(); continue
            }
            if inCode { code.append(line); continue }
            if line.isEmpty { continue }
            let hashes = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") {
                result.append(Block(text: String(line.dropFirst(hashes + 1)), style: .heading(hashes)))
            } else { result.append(Block(text: line, style: .text)) }
        }
        if !code.isEmpty { result.append(Block(text: code.joined(separator: "\n"), style: .code)) }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block.style {
                case .heading(let level):
                    Text(inline(block.text)).font(level == 1 ? .title.bold() : .headline).padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                case .code:
                    ScrollView(.horizontal) { Text(block.text).font(.system(.caption, design: .monospaced)).padding(12) }
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                case .text: Text(inline(block.text)).font(.body)
                }
            }
        }.textSelection(.enabled)
    }
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace), baseURL: baseURL)) ?? AttributedString(text)
    }
    private struct Block {
        enum Style { case heading(Int), code, text }
        let text: String
        let style: Style
    }
}
