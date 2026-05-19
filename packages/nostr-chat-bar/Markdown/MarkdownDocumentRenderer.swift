import Cocoa
import Foundation
import Markdown

// MARK: - Markdown document rendering

enum MarkdownDocumentRenderer {
    private static let cache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>()
        cache.countLimit = 500
        return cache
    }()

    static func attributedText(from text: String, mine: Bool,
                               textColor: NSColor, linkTint: NSColor) -> NSAttributedString {
        let key = "\(mine ? 1 : 0)\u{1f}\(text)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let rendered = SwiftMarkdownRenderer(mine: mine, textColor: textColor, linkTint: linkTint)
            .render(document: Document(parsing: text, options: [.disableSmartOpts]))
        cache.setObject(rendered, forKey: key)
        return rendered
    }
}

private final class SwiftMarkdownRenderer {
    private let mine: Bool
    private let textColor: NSColor
    private let linkTint: NSColor
    private let baseFont = NSFont.systemFont(ofSize: 13)
    private let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    init(mine: Bool, textColor: NSColor, linkTint: NSColor) {
        self.mine = mine
        self.textColor = textColor
        self.linkTint = linkTint
    }

    func render(document: Document) -> NSAttributedString {
        renderBlocks(Array(document.children), depth: 0, tight: false)
    }

    private func renderBlocks(_ blocks: [Markup], depth: Int, tight: Bool) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 { out.append(NSAttributedString(string: tight ? "\n" : "\n\n")) }
            out.append(renderBlock(block, depth: depth))
        }
        return out
    }

    private func renderBlock(_ block: Markup, depth: Int) -> NSAttributedString {
        switch block {
        case let paragraph as Paragraph:
            return renderInlineChildren(of: paragraph, font: baseFont, color: textColor)
        case let heading as Heading:
            let size: CGFloat = heading.level == 1 ? 17 : (heading.level == 2 ? 15 : 14)
            return renderInlineChildren(of: heading, font: .boldSystemFont(ofSize: size), color: textColor)
        case let quote as BlockQuote:
            return renderQuote(quote, depth: depth)
        case let code as CodeBlock:
            return renderCodeBlock(code)
        case is ThematicBreak:
            return NSAttributedString(string: "────────", attributes: [.foregroundColor: textColor.withAlphaComponent(0.45)])
        case let list as UnorderedList:
            return renderList(Array(list.listItems), orderedStart: nil, depth: depth)
        case let list as OrderedList:
            return renderList(Array(list.listItems), orderedStart: Int(list.startIndex), depth: depth)
        case let table as Table:
            return renderTable(table)
        case let html as HTMLBlock:
            return NSAttributedString(string: html.rawHTML, attributes: baseAttributes(font: baseFont, color: textColor))
        default:
            return renderBlocks(Array(block.children), depth: depth, tight: true)
        }
    }

    private func renderQuote(_ quote: BlockQuote, depth: Int) -> NSAttributedString {
        let body = renderBlocks(Array(quote.children), depth: depth + 1, tight: false)
        let out = NSMutableAttributedString()
        let markerAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: textColor.withAlphaComponent(0.45),
        ]
        let lines = body.string.components(separatedBy: .newlines)
        var location = 0
        for (index, line) in lines.enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(NSAttributedString(string: "▏ ", attributes: markerAttributes))
            let length = (line as NSString).length
            if length > 0 {
                out.append(body.attributedSubstring(from: NSRange(location: location, length: length)))
            }
            location += length + 1
        }
        applyParagraphStyle(out, firstLineHeadIndent: CGFloat(depth) * 18,
                            headIndent: CGFloat(depth) * 18 + 14)
        return out
    }

    private func renderCodeBlock(_ block: CodeBlock) -> NSAttributedString {
        let bg = mine ? NSColor.white.withAlphaComponent(0.16)
            : NSColor(calibratedWhite: 0.92, alpha: 1)
        let attr = NSMutableAttributedString(
            string: block.code,
            attributes: [
                .font: codeFont,
                .foregroundColor: mine ? NSColor.white : NSColor(calibratedWhite: 0.08, alpha: 1),
                .backgroundColor: bg,
            ])
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        attr.addAttribute(.paragraphStyle,
                          value: style,
                          range: NSRange(location: 0, length: attr.length))
        return attr
    }

    private func renderList(_ items: [ListItem], orderedStart: Int?, depth: Int) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n")) }
            let marker: String
            if let orderedStart {
                marker = "\(orderedStart + index). "
            } else {
                marker = "• "
            }
            out.append(NSAttributedString(string: marker, attributes: baseAttributes(font: baseFont, color: textColor)))
            if let checkbox = item.checkbox {
                out.append(NSAttributedString(string: checkbox == .checked ? "☑ " : "☐ ",
                                              attributes: baseAttributes(font: baseFont, color: textColor)))
            }
            out.append(renderListItemContents(item, depth: depth))
        }
        applyParagraphStyle(out,
                            firstLineHeadIndent: CGFloat(depth) * 18,
                            headIndent: CGFloat(depth + 1) * 18)
        return out
    }

    private func renderListItemContents(_ item: ListItem, depth: Int) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var renderedFirstParagraph = false
        for child in item.children {
            if let paragraph = child as? Paragraph, !renderedFirstParagraph, out.length == 0 {
                out.append(renderInlineChildren(of: paragraph, font: baseFont, color: textColor))
                renderedFirstParagraph = true
            } else {
                if out.length > 0 { out.append(NSAttributedString(string: "\n")) }
                out.append(renderBlock(child, depth: depth + 1))
            }
        }
        return out
    }

    private func renderTable(_ table: Table) -> NSAttributedString {
        let rows = tableRows(table)
        guard !rows.isEmpty, let columnCount = rows.map(\.count).max(), columnCount > 0 else {
            return NSAttributedString()
        }

        let textTable = NSTextTable()
        textTable.numberOfColumns = columnCount
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false

        let out = NSMutableAttributedString()
        for (rowIndex, row) in rows.enumerated() {
            for column in 0..<columnCount {
                if out.length > 0 { out.append(NSAttributedString(string: "\n")) }
                let cell = column < row.count ? row[column] : nil
                let cellText = cell.map {
                    renderInlineChildren(of: $0,
                                         font: rowIndex == 0 ? .boldSystemFont(ofSize: 12) : baseFont,
                                         color: textColor)
                } ?? NSMutableAttributedString(string: " ", attributes: baseAttributes(font: baseFont, color: textColor))
                if cellText.length == 0 {
                    cellText.append(NSAttributedString(string: " ", attributes: baseAttributes(font: baseFont, color: textColor)))
                }
                applyTableCellStyle(cellText,
                                    table: textTable,
                                    row: rowIndex,
                                    column: column,
                                    alignment: table.columnAlignments[safe: column] ?? nil)
                out.append(cellText)
            }
        }
        return out
    }

    private func renderInlineChildren(of container: InlineContainer,
                                      font: NSFont, color: NSColor) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for child in container.inlineChildren {
            out.append(renderInline(child, font: font, color: color, traits: []))
        }
        return out
    }

    private func renderInline(_ inline: InlineMarkup, font: NSFont, color: NSColor,
                              traits: NSFontTraitMask) -> NSAttributedString {
        switch inline {
        case let text as Text:
            return NSAttributedString(string: text.string,
                                      attributes: baseAttributes(font: styledFont(font, traits: traits), color: color))
        case let code as InlineCode:
            let bg = mine ? NSColor.white.withAlphaComponent(0.16)
                : NSColor(calibratedWhite: 0.90, alpha: 1)
            return NSAttributedString(string: code.code,
                                      attributes: [
                                          .font: codeFont,
                                          .foregroundColor: color,
                                          .backgroundColor: bg,
                                      ])
        case let strong as Strong:
            return renderInlineContainer(strong, font: font, color: color, traits: traits.union(.boldFontMask))
        case let emphasis as Emphasis:
            return renderInlineContainer(emphasis, font: font, color: color, traits: traits.union(.italicFontMask))
        case let strike as Strikethrough:
            let attr = NSMutableAttributedString(attributedString: renderInlineContainer(strike, font: font, color: color, traits: traits))
            attr.addAttribute(.strikethroughStyle,
                              value: NSUnderlineStyle.single.rawValue,
                              range: NSRange(location: 0, length: attr.length))
            return attr
        case let link as Link:
            let attr = NSMutableAttributedString(attributedString: renderInlineContainer(link, font: font, color: color, traits: traits))
            if let destination = link.destination, Self.safeLink(destination) {
                attr.addAttributes([
                    .link: destination,
                    .foregroundColor: linkTint,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .cursor: NSCursor.pointingHand,
                ], range: NSRange(location: 0, length: attr.length))
            }
            return attr
        case let image as Image:
            let label = image.plainText.isEmpty ? "image" : image.plainText
            return NSAttributedString(string: "[\(label)]",
                                      attributes: baseAttributes(font: styledFont(font, traits: traits), color: color))
        case is SoftBreak:
            return NSAttributedString(string: "\n", attributes: baseAttributes(font: font, color: color))
        case is LineBreak:
            return NSAttributedString(string: "\n", attributes: baseAttributes(font: font, color: color))
        case let html as InlineHTML:
            return NSAttributedString(string: html.plainText, attributes: baseAttributes(font: font, color: color))
        default:
            if let container = inline as? InlineContainer {
                return renderInlineContainer(container, font: font, color: color, traits: traits)
            }
            return NSAttributedString(string: inline.plainText,
                                      attributes: baseAttributes(font: styledFont(font, traits: traits), color: color))
        }
    }

    private func renderInlineContainer(_ container: InlineContainer,
                                       font: NSFont, color: NSColor,
                                       traits: NSFontTraitMask) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for child in container.inlineChildren {
            out.append(renderInline(child, font: font, color: color, traits: traits))
        }
        return out
    }

    private func tableRows(_ table: Table) -> [[Table.Cell]] {
        var rows: [[Table.Cell]] = []
        rows.append(Array(table.head.cells))
        for row in table.body.rows {
            rows.append(Array(row.cells))
        }
        return rows
    }

    private func applyTableCellStyle(_ attr: NSMutableAttributedString,
                                     table: NSTextTable,
                                     row: Int,
                                     column: Int,
                                     alignment: Table.ColumnAlignment?) {
        let block = NSTextTableBlock(table: table,
                                     startingRow: row,
                                     rowSpan: 1,
                                     startingColumn: column,
                                     columnSpan: 1)
        let border = mine
            ? NSColor.white.withAlphaComponent(0.26)
            : NSColor.separatorColor.withAlphaComponent(0.85)
        block.setBorderColor(border)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setWidth(6, type: .absoluteValueType, for: .padding)
        block.backgroundColor = row == 0
            ? (mine ? NSColor.white.withAlphaComponent(0.18) : NSColor(calibratedWhite: 0.88, alpha: 0.95))
            : (mine ? NSColor.white.withAlphaComponent(0.08) : NSColor(calibratedWhite: 1.0, alpha: 0.55))

        let style = NSMutableParagraphStyle()
        style.textBlocks = [block]
        style.paragraphSpacing = 0
        switch alignment {
        case .left?: style.alignment = .left
        case .center?: style.alignment = .center
        case .right?: style.alignment = .right
        case nil: style.alignment = .natural
        }
        attr.addAttribute(.paragraphStyle,
                          value: style,
                          range: NSRange(location: 0, length: attr.length))
    }

    private func baseAttributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    private func styledFont(_ font: NSFont, traits: NSFontTraitMask) -> NSFont {
        guard !traits.isEmpty else { return font }
        return NSFontManager.shared.convert(font, toHaveTrait: traits)
    }

    private func applyParagraphStyle(_ attr: NSMutableAttributedString,
                                     firstLineHeadIndent: CGFloat,
                                     headIndent: CGFloat) {
        guard attr.length > 0 else { return }
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = firstLineHeadIndent
        style.headIndent = headIndent
        style.paragraphSpacing = 2
        attr.addAttribute(.paragraphStyle,
                          value: style,
                          range: NSRange(location: 0, length: attr.length))
    }

    private static func safeLink(_ value: String) -> Bool {
        guard let scheme = URL(string: value)?.scheme?.lowercased() else { return false }
        return ["http", "https", "nostr"].contains(scheme)
    }
}
