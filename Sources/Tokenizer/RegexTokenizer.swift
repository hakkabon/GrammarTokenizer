//
//  RegexTokenizer.swift
//  GrammarTokenizer
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/16.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

public final class RegexTokenizer: TokenStream {
    
    /// Symbols that are part of the BNF/EBNF meta-notation.
    public static let regularPunctuation: Set<String> = [
        "|",
        "\\",
        "^",
        ":",
        ",",
        "$",
        ".",
        "\"",
        "¶",
        ">",
        "#",
        "-",
        "{",
        "[",
        "<",
        "(",
        "(?:",
        "(?|",
        "[:",
        "+",
        "+?",
        "'",
        "}",
        "]",
        ":]",
        ")",
        ";",
        "/",
        "*",
        "*?",
        "?",
        "??"
    ]
    
    public static let regularKeywords = [
        "alnum", "alpha", "ascii", "blank", "cntrl", "digit",
        "graph", "lower", "print", "punct", "space", "upper", "word", "xdigit"
    ]
 
    /// Creates a Regular Expression tokenizer.
    ///
    /// - Parameters:
    ///   - source:          The regular expression as text.
    ///   - extraSymbols:    Any dialect-specific symbols beyond the standard set.
    ///   - extraKeywords:   Any meta-level keywords your grammar dialect uses.
    public init(
        _ source:        String,
        extraSymbols:    Set<String> = [],
        extraKeywords:   Set<String> = []
    ) {
        super.init(
            source,
            symbols:  RegexTokenizer.regularPunctuation.union(extraSymbols),
            keywords: extraKeywords
        )
    }
    
    public override func nextToken() -> Token? {
        
        // Skip all irrelevant characters until we find something.
        characters.skipWhitespace()
        guard !characters.isEmpty else { return nil }
        
        let tokenStart = characters.startIndex
        
        // Maximum-munch symbol branch
        if let matched = trie.longestMatch(in: &characters) {
            let symbol = String(matched)
            switch symbol {
                
            case "'": return characters.parseLiteral(startIndex: tokenStart, until: "'")
            case "\"": return characters.parseLiteral(startIndex: tokenStart, until: "\"")
            case "/": return characters.parseRegexDefinition(startIndex: tokenStart, until: "/")
            case "#": return characters.parseLineComment(startIndex: tokenStart)
            case "//": return characters.parseLineComment(startIndex: tokenStart)
            case "/*": return characters.parseBlockComment(startIndex: tokenStart, match: "*/")
            case "(*": return characters.parseBlockComment(startIndex: tokenStart, match: "*)")
                // Stray closing comment markers are a user-input error.
                // Return an `.invalid` token rather than crashing.
            case "*/", "*)":
                return Token(
                    type:  .invalid(.unrecognizedInput(symbol)),
                    range: tokenStart ..< characters.startIndex
                )
                
                // otherwise, maximum-munch gives us a valid symbol.
            default:
                return Token(type: .symbol(symbol), range: tokenStart ..< characters.startIndex)
            }
        }
        
        // Identifier / keyword / number branch
        guard let first = characters.first else { return nil }
        
        // Leading underscore is accepted as an identifier head (fixes the
        // mismatch between the original comment grammar and implementation).
        if CharacterSet.letters.contains(first) {
            return characters.parseCharacter(startIndex: tokenStart)
        }
        if first >= "0" && first <= "9" {
            return characters.parseNumber(startIndex: tokenStart)
        }
        
        // Unclassifiable character — return nil so tokenize() can produce a
        // single `.invalid(.unrecognizedInput)` token for the residual text.
        return nil
    }
}

extension UnicodeScalarView {

    // Parse character token containing exactly one character.
    mutating func parseCharacter(startIndex: Index) -> Token? {
        let startIndex = startIndex
        guard let ch = readCharacter(where: { CharacterSet.letters.contains($0) } ) else {
            return nil
        }
        return Token(type: .char(Character(ch)), range: startIndex ..< self.startIndex)
    }
}
