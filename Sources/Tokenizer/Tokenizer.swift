//
//  Tokenizer.swift
//  GrammarTokenizer
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

/// A general-purpose tokenizer in which the caller supplies the complete symbol
/// set and keyword list.
///
/// Use this class when you are building a new DSL or scanning tool and want
/// full control over the token vocabulary.  For the common case of reading
/// BNF/EBNF grammar *definitions* prefer `GrammarTokenizer`, which comes
/// pre-configured with the standard BNF operator set.
///
/// Lookahead / parsing
/// ───────────────────
/// `Tokenizer` is a pure scanner — it has no internal buffer.  Wrap it in a
/// `ParserInput` when your parsing algorithm needs `peek` or `consume`:
///
/// ```swift
/// let scanner = Tokenizer(source, symbols: mySymbols, keywords: myKeywords)
/// var input   = ParserInput(scanner)
///
/// if input.peek()?.type == .keyword("if") {
///     input.consume()
///     // …
/// }
/// ```
///
/// Sequential iteration (no lookahead needed)
/// ───────────────────────────────────────────
/// ```swift
/// let scanner = Tokenizer(source, symbols: mySymbols, keywords: myKeywords)
///
/// // Lazy, one token at a time:
/// for token in TokenSequence(scanner) { … }
///
/// // Eager, all at once:
/// let tokens = scanner.tokenize()
/// ```
public final class Tokenizer: TokenStream {

    /// Creates a general-purpose tokenizer.
    ///
    /// - Parameters:
    ///   - source:   The source string to tokenize.
    ///   - symbols:  Operator / punctuation strings to recognise.
    ///               These are merged with the built-in set
    ///               (`TokenStream.builtInSymbols`).
    ///   - keywords: Reserved words emitted as `.keyword` rather than
    ///               `.identifier`.
    public override init(
        _ source:   String,
        symbols:    Set<String> = [],
        keywords:   Set<String> = []
    ) {
        super.init(source, symbols: symbols, keywords: keywords)
    }
}
