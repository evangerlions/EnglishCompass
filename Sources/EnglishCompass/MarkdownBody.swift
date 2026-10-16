import Foundation
import SwiftUI

/// Foundation's CommonMark parser supplies block structure; Text alone only
/// renders inline intents. Lay out those native blocks explicitly, preserving
/// nested list/quote indentation rather than splitting source lines by hand.
struct MarkdownBody: View {
    let source: String
    var fontSize: CGFloat = 12.5

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(MarkdownDocument.blocks(source).enumerated()), id: \.offset) { _, block in
                if block.isDivider {
                    Divider()
                } else if !block.tableCells.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(block.tableCells.enumerated()), id: \.offset) { _, cell in
                            Text(cell).font(.system(size: fontSize, weight: block.isTableHeader ? .semibold : .regular))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(block.isTableHeader ? 0.06 : 0.025))
                } else {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if let marker = block.marker {
                        Text(marker).foregroundStyle(.secondary)
                    }
                    Text(block.text)
                        .font(.system(size: block.headingLevel.map { fontSize + CGFloat(max(1, 5 - $0)) } ?? fontSize,
                                      weight: block.headingLevel == nil ? .regular : .semibold,
                                      design: block.isCode ? .monospaced : .default))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: fontSize))
                .padding(.leading, CGFloat(max(0, block.listDepth - 1)) * 14 + (block.isQuote ? 10 : 0))
                .padding(block.isCode ? 8 : 0)
                .background {
                    if block.isCode {
                        RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.045))
                    }
                }
                .overlay(alignment: .leading) {
                    if block.isQuote { Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 2) }
                }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum MarkdownDocument {
    struct Block {
        var text: AttributedString
        var headingLevel: Int?
        var listDepth = 0
        var marker: String?
        var isQuote = false
        var isCode = false
        var isDivider = false
        var tableCells: [AttributedString] = []
        var isTableHeader = false
        var tableRowIdentity: Int?
        var tableCellIdentity: Int?
    }

    static func blocks(_ source: String) -> [Block] {
        guard let parsed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .full)) else {
            return [Block(text: AttributedString(source))]
        }
        var blocks: [Block] = []
        var lastIdentity: Int?
        var markedItems = Set<Int>()
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let identity = components.first?.identity
            var tableRow: Int?
            var tableCell: Int?
            var tableHeader = false
            for component in components {
                switch component.kind {
                case .tableCell(columnIndex: _): tableCell = component.identity
                case .tableHeaderRow: tableRow = component.identity; tableHeader = true
                case .tableRow(rowIndex: _): tableRow = component.identity
                default: break
                }
            }
            if let tableRow, let tableCell {
                let text = AttributedString(parsed[run.range])
                if blocks.last?.tableRowIdentity == tableRow {
                    let index = blocks.count - 1
                    if blocks[index].tableCellIdentity == tableCell {
                        blocks[index].tableCells[blocks[index].tableCells.count - 1] += text
                    } else {
                        blocks[index].tableCells.append(text)
                        blocks[index].tableCellIdentity = tableCell
                    }
                } else {
                    var block = Block(text: text)
                    block.tableCells = [text]; block.tableRowIdentity = tableRow
                    block.tableCellIdentity = tableCell; block.isTableHeader = tableHeader
                    blocks.append(block)
                }
                lastIdentity = identity
                continue
            }
            if !blocks.isEmpty, identity == lastIdentity {
                blocks[blocks.count - 1].text += AttributedString(parsed[run.range])
                continue
            }
            var block = Block(text: AttributedString(parsed[run.range]))
            var item: (Int, Int)?
            var ordered = false
            for component in components {
                switch component.kind {
                case .header(level: let level): block.headingLevel = level
                case .codeBlock(languageHint: _): block.isCode = true
                case .blockQuote: block.isQuote = true
                case .thematicBreak: block.isDivider = true
                case .listItem(ordinal: let ordinal):
                    if item == nil { item = (component.identity, ordinal) }
                case .orderedList:
                    block.listDepth += 1
                    if block.listDepth == 1 { ordered = true }
                case .unorderedList: block.listDepth += 1
                default: break
                }
            }
            if let item, markedItems.insert(item.0).inserted {
                block.marker = ordered ? "\(item.1)." : "•"
            }
            blocks.append(block)
            lastIdentity = identity
        }
        return blocks
    }
}
