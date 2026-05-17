//
//  InputTokenizer.swift
//  Tokenizer
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

/// A tokenizer configured at runtime from the terminal symbols extracted from a
/// parsed BNF/EBNF grammar.
///
/// Use case
/// ────────
/// After `GrammarTokenizer` + a grammar parser have produced a `Grammar` value, the
/// next step is usually to lex *input text* that the grammar describes.  The
/// token vocabulary for that input text — its operators, keywords, and comment
/// style — is determined by the grammar itself, not by the programmer.
///
/// `InputTokenizer` accepts exactly the sets that a grammar parser would
/// produce and configures the shared scanning engine accordingly.
///
/// ```swift
/// // 1. Parse the BNF grammar.
/// let grammarTokenizer = GrammarTokenizer(grammarSource)
/// let grammar          = GrammarParser(grammarTokenizer).parse()
///
/// // 2. Create a tokenizer for actual input text, driven by the grammar.
/// let inputTokenizer = InputTokenizer(
///     inputSource,
///     terminalSymbols: grammar.terminalSymbols,
///     reservedWords:   grammar.reservedWords
/// )
///
/// // 3. Wrap in ParserInput and drive your recursive-descent parser.
/// var input = ParserInput(inputTokenizer)
/// ```
///
/// Relationship to `Tokenizer`
/// ────────────────────────────
/// `InputTokenizer` is functionally identical to `Tokenizer`; it exists as a
/// separate type so that call sites are self-documenting — reading
/// `InputTokenizer(src, terminalSymbols: …)` makes the intent clear at a
/// glance, whereas `Tokenizer(src, symbols: …)` is ambiguous about which layer
/// of the system we are in.
public final class InputTokenizer: TokenizerCore {

    /// Creates a tokenizer for input text whose vocabulary is defined by a
    /// grammar.
    ///
    /// - Parameters:
    ///   - source:          The input text to tokenize.
    ///   - terminalSymbols: The set of terminal symbols (operators, punctuation)
    ///                      extracted from the grammar.
    ///   - reservedWords:   The set of reserved words / keywords extracted from
    ///                      the grammar.
    public init(
        _ source:          String,
        terminalSymbols:   Set<String> = [],
        reservedWords:     Set<String> = []
    ) {
        super.init(
            source,
            symbols:  terminalSymbols,
            keywords: reservedWords
        )
    }
}
