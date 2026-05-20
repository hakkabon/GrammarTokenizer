//
//  GrammarTokenizer.swift
//  GrammarTokenizer
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

/// A tokenizer pre-configured for reading BNF and EBNF grammar *definitions*.
///
/// `GrammarTokenizer` recognises the full operator vocabulary used in standard
/// BNF/EBNF notation — rule-definition operators, grouping brackets, the
/// alternation bar, and so on — without requiring the caller to list them
/// explicitly.
///
/// Additional symbols or keywords can still be supplied if a particular grammar
/// dialect extends the standard set.
///
/// Standard BNF/EBNF symbols registered by default
/// ─────────────────────────────────────────────────
///  `::=`  `=`  `|`  `<`  `>`  `(`  `)`  `[`  `]`  `{`  `}`  `,`  `+`  `*`  `?`  `-`
///
/// Standard BNF/EBNF keywords registered by default
/// ──────────────────────────────────────────────────
///  (none — BNF grammars typically have no reserved words at the meta level)
///
/// Usage
/// ─────
/// ```swift
/// // Read a grammar file with no extra symbols or keywords:
/// let tokenizer = GrammarTokenizer(grammarSource)
/// let tokens    = tokenizer.tokenize()
///
/// // Wrap in ParserInput to drive a recursive-descent parser:
/// var input = ParserInput(GrammarTokenizer(grammarSource))
/// ```
public final class GrammarTokenizer: TokenStream {

    /// Symbols that are part of the BNF/EBNF meta-notation.
    public static let bnfSymbols: Set<String> = [

        // rule definition
        ":",            // definition notational variation
        "=",            // EBNF rule definition (ISO style)
        ":=",           // notational variation
        "::=",          // BNF rule definition
        "->",           // notational variation
        
        // eol characters
        ".",            // EBNF/WSN terminaton definition
        ";",            // WSN terminaton definition
        
        // empty string symbols
        "ε",            // epsilon (empty string symbol)
        "λ",            // lambda (empty string symbol)
        
        // sequence character
        ",",            // EBNF sequence character (separator)

        "|",            // alternation
        "<", ">",       // non-terminal brackets
        "(", ")",       // grouping
        "[", "]",       // optional group   [ … ]
        "{", "}",       // repetition group { … }
        ",",            // sequence separator (some EBNF dialects)
        "+",            // one-or-more (EBNF extension)
        "*",            // zero-or-more (EBNF extension)
        "?",            // zero-or-one  (EBNF extension)
        "-",            // exception / exclusion (ISO EBNF)
        
        // Lexical elements (type 3 level)
        "/",            // regex separator
        "..",           // range operator
    ]

    /// Creates a BNF/EBNF grammar tokenizer.
    ///
    /// - Parameters:
    ///   - source:          The grammar source text.
    ///   - extraSymbols:    Any dialect-specific symbols beyond the standard set.
    ///   - extraKeywords:   Any meta-level keywords your grammar dialect uses.
    public init(
        _ source:        String,
        extraSymbols:    Set<String> = [],
        extraKeywords:   Set<String> = []
    ) {
        super.init(
            source,
            symbols:  GrammarTokenizer.bnfSymbols.union(extraSymbols),
            keywords: extraKeywords
        )
    }
}
