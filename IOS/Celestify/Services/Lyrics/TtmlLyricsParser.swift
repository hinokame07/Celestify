//
//  TtmlLyricsParser.swift
//  Celestify
//
//  Native Swift XML parser for Apple Music / iTunes / Spicy Lyrics TTML documents.
//  Supports:
//    - itunes:timing="Word" | "Line" | "None"
//    - ttm:agent declarations & automatic secondary-vocalist duet alignment
//    - ttm:role="x-bg" inline & nested backing vocals (timed or plain)
//    - ttm:role="x-roman" & <iTunesMetadata><transliterations> (key + ±2ms timestamp match)
//    - ttm:role="x-translation" & <iTunesMetadata><translations>
//    - <songwriters><songwriter> credits
//    - Syllable adjacency (isPartOfWord) & untimed line interpolation
//    - Strict XXE / DOCTYPE rejection & 1 MB size safety bound
//
//  Adapted from Spicy Lyrics Mobile (TtmlLyricsParser.kt), AGPL-3.0, and Myspoti, GPL-3.0.
//  See THIRD_PARTY_NOTICES.md.
//

import Foundation

public enum TtmlParseError: Error, LocalizedError, Sendable, Equatable {
    case payloadTooLarge
    case forbiddenEntityDeclaration
    case malformedXML(String)
    case emptyLyrics

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge: return "TTML file exceeds the 1 MB safety limit."
        case .forbiddenEntityDeclaration: return "DOCTYPE and external XML entities are forbidden."
        case .malformedXML(let msg): return "Malformed TTML XML: \(msg)"
        case .emptyLyrics: return "No lyric lines were found in the TTML document."
        }
    }
}

public enum TtmlLyricsParser {
    public static let maxBytes = 1_024 * 1_024

    public static func parse(_ xmlString: String) throws -> Lyrics {
        guard let data = xmlString.data(using: .utf8) else {
            throw TtmlParseError.malformedXML("Invalid UTF-8 encoding")
        }
        return try parse(data: data)
    }

    public static func parse(data: Data) throws -> Lyrics {
        guard data.count <= maxBytes else {
            throw TtmlParseError.payloadTooLarge
        }
        if let headSample = String(data: data.prefix(4096), encoding: .utf8) ?? String(data: data.prefix(4096), encoding: .isoLatin1) {
            let upper = headSample.uppercased()
            if upper.contains("<!DOCTYPE") || upper.contains("<!ENTITY") {
                throw TtmlParseError.forbiddenEntityDeclaration
            }
        }

        let builder = TtmlDOMBuilder()
        let xmlParser = XMLParser(data: data)
        xmlParser.shouldProcessNamespaces = false
        xmlParser.shouldResolveExternalEntities = false
        xmlParser.delegate = builder

        guard xmlParser.parse(), let root = builder.root else {
            let msg = xmlParser.parserError?.localizedDescription ?? "Failed to parse XML tree"
            throw TtmlParseError.malformedXML(msg)
        }

        return try extractLyrics(from: root)
    }

    // MARK: - TTML Clock & Offset Time Parser

    /// Parses TTML clock (`01:02:03.456`, `02:03.45`, `12.345`) and offset (`12.5s`, `350ms`, `2m`, `1h`) strings into milliseconds.
    public static func parseTimeMs(_ raw: String?) -> Int64? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasSuffix("ms") {
            guard let val = Double(trimmed.dropLast(2)) else { return nil }
            return Int64((val).rounded())
        }
        if trimmed.hasSuffix("s") && !trimmed.contains(":") {
            guard let val = Double(trimmed.dropLast(1)) else { return nil }
            return Int64((val * 1000.0).rounded())
        }
        if trimmed.hasSuffix("m") && !trimmed.contains(":") {
            guard let val = Double(trimmed.dropLast(1)) else { return nil }
            return Int64((val * 60_000.0).rounded())
        }
        if trimmed.hasSuffix("h") && !trimmed.contains(":") {
            guard let val = Double(trimmed.dropLast(1)) else { return nil }
            return Int64((val * 3_600_000.0).rounded())
        }

        let parts = trimmed.split(separator: ":").map(String.init)
        switch parts.count {
        case 1:
            guard let seconds = Double(parts[0]) else { return nil }
            return Int64((seconds * 1000.0).rounded())
        case 2:
            guard let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
            return Int64(((minutes * 60.0 + seconds) * 1000.0).rounded())
        case 3:
            guard let hours = Double(parts[0]),
                  let minutes = Double(parts[1]),
                  let seconds = Double(parts[2]) else { return nil }
            return Int64(((hours * 3600.0 + minutes * 60.0 + seconds) * 1000.0).rounded())
        default:
            return nil
        }
    }

    // MARK: - Structured Tree Extraction

    private static func extractLyrics(from root: XMLNode) throws -> Lyrics {
        let timingAttr = root.attribute("itunes:timing")?.lowercased()
        let declaredUnsynced = timingAttr == "none"

        var agentTypes: [String: String] = [:] // id -> "person" | "group" | "other"
        var songwriters: [String] = []
        var translitByKey: [String: String] = [:]
        var translitByTime: [(startMs: Int64, text: String)] = []
        var translationByKey: [String: String] = [:]

        // 1. Inspect <head> metadata (agents, songwriters, transliterations, translations)
        if let head = root.firstChild(named: "head") {
            if let metadata = head.firstChild(named: "metadata") {
                for child in metadata.children where child.localName == "agent" {
                    if let id = child.attribute("xml:id") ?? child.attribute("id") {
                        agentTypes[id] = child.attribute("type")?.lowercased() ?? "person"
                    }
                }
            }
            for metaNode in head.descendants(named: "iTunesMetadata") {
                if let swContainer = metaNode.firstChild(named: "songwriters") {
                    for sw in swContainer.children where sw.localName == "songwriter" {
                        let name = sw.flattenedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { songwriters.append(name) }
                    }
                }
                if let trContainer = metaNode.firstChild(named: "transliterations"),
                   let firstTranslit = trContainer.children.first(where: { $0.localName == "transliteration" }) {
                    for textNode in firstTranslit.children where textNode.localName == "text" {
                        let val = collapseSpaces(textNode.flattenedText)
                        guard !val.isEmpty else { continue }
                        if let key = textNode.attribute("for") {
                            translitByKey[key] = val
                        }
                        if let begin = parseTimeMs(textNode.attribute("begin")) {
                            translitByTime.append((begin, val))
                        }
                    }
                }
                if let tlContainer = metaNode.firstChild(named: "translations"),
                   let firstTranslation = tlContainer.children.first(where: { $0.localName == "translation" }) {
                    for textNode in firstTranslation.children where textNode.localName == "text" {
                        let val = collapseSpaces(textNode.flattenedText)
                        if !val.isEmpty, let key = textNode.attribute("for") {
                            translationByKey[key] = val
                        }
                    }
                }
            }
        }

        guard let body = root.firstChild(named: "body") else {
            throw TtmlParseError.emptyLyrics
        }

        // Collect all <p> elements inside <body> / <div>
        let paragraphs = body.descendants(named: "p")
        guard !paragraphs.isEmpty else {
            throw TtmlParseError.emptyLyrics
        }

        // Determine primary vs duet guest agents (matching Spicy TtmlLyricsParser.duetGuests)
        var orderedPersonAgents: [String] = []
        for p in paragraphs {
            if let agent = p.attribute("ttm:agent") ?? p.attribute("agent") {
                let kind = agentTypes[agent] ?? "person"
                if kind == "person" && !orderedPersonAgents.contains(agent) {
                    orderedPersonAgents.append(agent)
                }
            }
        }
        let duetAgents: Set<String> = orderedPersonAgents.count > 1
            ? Set(orderedPersonAgents.dropFirst())
            : []

        struct RawParagraph {
            var key: String?
            var startMs: Int64?
            var endMs: Int64?
            var speaker: LyricSpeaker
            var words: [LyricWord]
            var plainText: String
            var bgWords: [LyricWord]
            var bgText: String?
            var romanized: String?
            var translation: String?
        }

        var rawLines: [RawParagraph] = []
        var anyWordSynced = false
        var anyLineSynced = false

        for p in paragraphs {
            let lineKey = p.attribute("itunes:key")
            var pStart = parseTimeMs(p.attribute("begin"))
            var pEnd = parseTimeMs(p.attribute("end"))
            if pEnd == nil, let dur = parseTimeMs(p.attribute("dur")), let s = pStart {
                pEnd = s + dur
            }

            let agent = p.attribute("ttm:agent") ?? p.attribute("agent")
            let speaker: LyricSpeaker = (agent != nil && duetAgents.contains(agent!)) ? .duet : .main

            var leadWords: [LyricWord] = []
            var leadPlainPieces: [String] = []
            var bgWords: [LyricWord] = []
            var bgPlainPieces: [String] = []
            var inlineRoman: String?
            var inlineTranslation: String?

            func processItems(_ items: [XMLContent], intoWords targetWords: inout [LyricWord], intoPlain targetPlain: inout [String]) {
                for item in items {
                    switch item {
                    case .text(let str):
                        targetPlain.append(str)
                        // Whitespace between two timed spans separates words (clears isPartOfWord on previous span)
                        if str.contains(where: \.isWhitespace), let lastIdx = targetWords.indices.last {
                            let prev = targetWords[lastIdx]
                            if prev.isPartOfWord {
                                targetWords[lastIdx] = LyricWord(
                                    text: prev.text,
                                    startMs: prev.startMs,
                                    endMs: prev.endMs,
                                    isPartOfWord: false
                                )
                            }
                        }

                    case .element(let span):
                        let role = span.attribute("ttm:role") ?? span.attribute("role") ?? ""
                        if role == "x-bg" {
                            processItems(span.contents, intoWords: &bgWords, intoPlain: &bgPlainPieces)
                        } else if role == "x-roman" {
                            let r = collapseSpaces(span.flattenedText)
                            if !r.isEmpty { inlineRoman = r }
                        } else if role == "x-translation" {
                            let tr = collapseSpaces(span.flattenedText)
                            if !tr.isEmpty { inlineTranslation = tr }
                        } else if span.localName == "span" {
                            let sStart = parseTimeMs(span.attribute("begin"))
                            var sEnd = parseTimeMs(span.attribute("end"))
                            if sEnd == nil, let dur = parseTimeMs(span.attribute("dur")), let s = sStart {
                                sEnd = s + dur
                            }
                            let rawSpanText = span.directLeadText
                            targetPlain.append(rawSpanText)

                            if let sStart {
                                let hasTrailingSpace = rawSpanText.last?.isWhitespace == true
                                let hasLeadingSpace = rawSpanText.first?.isWhitespace == true
                                if hasLeadingSpace, let lastIdx = targetWords.indices.last {
                                    let prev = targetWords[lastIdx]
                                    if prev.isPartOfWord {
                                        targetWords[lastIdx] = LyricWord(
                                            text: prev.text,
                                            startMs: prev.startMs,
                                            endMs: prev.endMs,
                                            isPartOfWord: false
                                        )
                                    }
                                }
                                let trimmed = rawSpanText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    // Tentatively mark isPartOfWord = !hasTrailingSpace; cleared at end or on whitespace
                                    targetWords.append(
                                        LyricWord(
                                            text: trimmed,
                                            startMs: sStart,
                                            endMs: sEnd ?? (sStart + 250),
                                            isPartOfWord: !hasTrailingSpace
                                        )
                                    )
                                }
                            }
                            // Also inspect nested x-bg / x-roman / x-translation children inside span
                            for sub in span.children {
                                let subRole = sub.attribute("ttm:role") ?? sub.attribute("role") ?? ""
                                if subRole == "x-bg" {
                                    processItems(sub.contents, intoWords: &bgWords, intoPlain: &bgPlainPieces)
                                } else if subRole == "x-roman" {
                                    let r = collapseSpaces(sub.flattenedText)
                                    if !r.isEmpty { inlineRoman = r }
                                } else if subRole == "x-translation" {
                                    let tr = collapseSpaces(sub.flattenedText)
                                    if !tr.isEmpty { inlineTranslation = tr }
                                }
                            }
                        }
                    }
                }
                // Last syllable in a line never joins into a next syllable
                if let lastIdx = targetWords.indices.last {
                    let last = targetWords[lastIdx]
                    if last.isPartOfWord {
                        targetWords[lastIdx] = LyricWord(
                            text: last.text,
                            startMs: last.startMs,
                            endMs: last.endMs,
                            isPartOfWord: false
                        )
                    }
                }
            }

            processItems(p.contents, intoWords: &leadWords, intoPlain: &leadPlainPieces)

            let joinedPlain: String = {
                if !leadWords.isEmpty {
                    var built = ""
                    for (idx, w) in leadWords.enumerated() {
                        if idx > 0 && !leadWords[idx - 1].isPartOfWord {
                            built.append(" ")
                        }
                        built.append(w.text)
                    }
                    return built
                }
                return collapseSpaces(leadPlainPieces.joined())
            }()

            let cleanedBgText: String? = {
                let rawBg: String
                if !bgWords.isEmpty {
                    var built = ""
                    for (idx, w) in bgWords.enumerated() {
                        if idx > 0 && !bgWords[idx - 1].isPartOfWord { built.append(" ") }
                        built.append(w.text)
                    }
                    rawBg = built
                } else {
                    rawBg = collapseSpaces(bgPlainPieces.joined())
                }
                let stripped = stripOuterParentheses(rawBg)
                return stripped.isEmpty ? nil : stripped
            }()

            // Strip outer parentheses on first/last bgWords if present
            if !bgWords.isEmpty {
                if bgWords[0].text.hasPrefix("(") {
                    let w = bgWords[0]
                    let t = String(w.text.dropFirst()).trimmingCharacters(in: .whitespaces)
                    bgWords[0] = LyricWord(text: t, startMs: w.startMs, endMs: w.endMs, isPartOfWord: w.isPartOfWord)
                }
                if let lastIdx = bgWords.indices.last, bgWords[lastIdx].text.hasSuffix(")") {
                    let w = bgWords[lastIdx]
                    let t = String(w.text.dropLast()).trimmingCharacters(in: .whitespaces)
                    bgWords[lastIdx] = LyricWord(text: t, startMs: w.startMs, endMs: w.endMs, isPartOfWord: false)
                }
                bgWords.removeAll { $0.text.isEmpty }
            }

            if pStart == nil, let firstWord = leadWords.first {
                pStart = firstWord.startMs
            }
            if pEnd == nil, let lastWord = leadWords.last {
                pEnd = lastWord.endMs
            }

            guard !joinedPlain.isEmpty || cleanedBgText != nil else { continue }

            if !leadWords.isEmpty && !declaredUnsynced && timingAttr != "line" {
                anyWordSynced = true
            }
            if pStart != nil && !declaredUnsynced {
                anyLineSynced = true
            }

            // Match metadata transliteration / translation by itunes:key or ±2ms timestamp
            let resolvedRoman = inlineRoman
                ?? lineKey.flatMap { translitByKey[$0] }
                ?? pStart.flatMap { start in
                    translitByTime.first(where: { abs($0.startMs - start) <= 2 })?.text
                }
            let resolvedTranslation = inlineTranslation
                ?? lineKey.flatMap { translationByKey[$0] }

            rawLines.append(
                RawParagraph(
                    key: lineKey,
                    startMs: declaredUnsynced ? 0 : pStart,
                    endMs: declaredUnsynced ? nil : pEnd,
                    speaker: speaker,
                    words: (declaredUnsynced || timingAttr == "line") ? [] : leadWords,
                    plainText: joinedPlain.isEmpty ? (cleanedBgText ?? "") : joinedPlain,
                    bgWords: declaredUnsynced ? [] : bgWords,
                    bgText: joinedPlain.isEmpty ? nil : cleanedBgText,
                    romanized: resolvedRoman,
                    translation: resolvedTranslation
                )
            )
        }

        guard !rawLines.isEmpty else {
            throw TtmlParseError.emptyLyrics
        }

        // Interpolate any untimed lines sitting between timed lines (port of placeUntimed)
        for idx in rawLines.indices where rawLines[idx].startMs == nil {
            let prevTime = rawLines[0..<idx].reversed().compactMap { $0.endMs ?? $0.startMs }.first ?? 0
            let nextTime = rawLines[(idx + 1)...].compactMap(\.startMs).first ?? (prevTime + 2_000)
            let mid = (prevTime + max(prevTime, nextTime)) / 2
            rawLines[idx].startMs = mid
            rawLines[idx].endMs = max(mid, nextTime)
        }

        let lines: [LyricLine] = rawLines.enumerated().map { idx, rp in
            let s = rp.startMs ?? 0
            let nextStart = idx + 1 < rawLines.count ? rawLines[idx + 1].startMs : nil
            return LyricLine(
                startMs: s,
                endMs: rp.endMs ?? nextStart,
                words: rp.plainText,
                speaker: rp.speaker,
                wordTimings: rp.words,
                backgroundText: rp.bgText,
                backgroundWords: rp.bgWords,
                romanized: rp.romanized,
                translation: rp.translation
            )
        }

        let isRTL = lines.contains { LyricTiming.containsRTLCharacters($0.words) }

        return Lyrics(
            lines: lines,
            synced: anyLineSynced || anyWordSynced,
            wordSynced: anyWordSynced,
            provider: "TTML",
            isRTL: isRTL,
            songwriters: songwriters
        )
    }

    private static func collapseSpaces(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripOuterParentheses(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("(") && out.hasSuffix(")") && out.count >= 2 {
            out.removeFirst()
            out.removeLast()
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Lightweight Internal XML Tree

private enum XMLContent {
    case text(String)
    case element(XMLNode)
}

private final class XMLNode {
    let name: String
    let localName: String
    let attributes: [String: String]
    var contents: [XMLContent] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.localName = name.split(separator: ":").last.map(String.init) ?? name
        self.attributes = attributes
    }

    var children: [XMLNode] {
        contents.compactMap {
            if case .element(let node) = $0 { return node }
            return nil
        }
    }

    func attribute(_ key: String) -> String? {
        if let exact = attributes[key] { return exact }
        let short = key.split(separator: ":").last.map(String.init) ?? key
        return attributes.first(where: { ($0.key.split(separator: ":").last.map(String.init) ?? $0.key) == short })?.value
    }

    func firstChild(named target: String) -> XMLNode? {
        children.first { $0.localName == target || $0.name == target }
    }

    func descendants(named target: String) -> [XMLNode] {
        var result: [XMLNode] = []
        for child in children {
            if child.localName == target || child.name == target {
                result.append(child)
            }
            result.append(contentsOf: child.descendants(named: target))
        }
        return result
    }

    var flattenedText: String {
        var out = ""
        for item in contents {
            switch item {
            case .text(let s): out += s
            case .element(let el): out += el.flattenedText
            }
        }
        return out
    }

    /// Text directly inside a span, excluding nested `x-bg`, `x-roman`, or `x-translation` children.
    var directLeadText: String {
        var out = ""
        for item in contents {
            switch item {
            case .text(let s):
                out += s
            case .element(let el):
                let r = el.attribute("ttm:role") ?? el.attribute("role") ?? ""
                if !r.hasPrefix("x-") {
                    out += el.directLeadText
                }
            }
        }
        return out
    }
}

private final class TtmlDOMBuilder: NSObject, XMLParserDelegate {
    var root: XMLNode?
    private var stack: [XMLNode] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = XMLNode(name: qName ?? elementName, attributes: attributeDict)
        if let current = stack.last {
            current.contents.append(.element(node))
        } else {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let current = stack.last else { return }
        if case .text(let existing) = current.contents.last {
            current.contents[current.contents.count - 1] = .text(existing + string)
        } else {
            current.contents.append(.text(string))
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        _ = stack.popLast()
    }
}
