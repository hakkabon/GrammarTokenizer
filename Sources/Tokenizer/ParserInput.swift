//
//  ParserInput.swift
//  Tokenizer
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//
//  `ParserInput` is the *only* place where lookahead state lives.
//  `TokenizerCore` and its subclasses are pure scanners with no internal buffer.

import Foundation

/// A lazy lookahead queue that sits between a scanner and a recursive-descent
/// parser.
///
/// Design
/// ──────
/// `TokenizerCore` (and its subclasses) is a pure scanner: it advances a
/// character cursor and classifies tokens one at a time, with no internal
/// buffer.  `ParserInput` adds the only lookahead state needed by a parser:
///
/// • A small FIFO queue that grows on demand as `peek(ahead:)` requests tokens.
/// • `consume()` drains from the front of that queue (or calls the scanner
///   directly if the queue is empty).
/// • There is no fixed maximum lookahead depth; the queue grows to whatever
///   the parser requests.
///
/// This separates two concerns cleanly:
///  - The scanner knows how to recognise tokens.
///  - `ParserInput` knows how to buffer and expose them to a parser.
///
/// Usage
/// ─────
/// ```swift
/// var input = ParserInput(GrammarTokenizer(source))
///
/// // Look ahead without consuming:
/// if input.peek()?.type == .keyword("rule") {
///     input.consume()               // discard "rule"
///     let name = input.consume()    // grab rule name
///     // …
/// }
///
/// // Deeper lookahead:
/// if input.peek(ahead: 2)?.type == .symbol("::=") { … }
///
/// // Get — returns .eof sentinel instead of nil:
/// let token = input.get()
/// ```
public struct ParserInput<Scanner: Tokenizing> {

    private let scanner:    Scanner
    private var lookahead:  [Token] = []

    /// The source range end-index, cached for constructing `.eof` tokens.
    /// Because `Token` requires a `Range<String.Index>` we need a valid index
    /// even at end-of-input.
    private let eofRange: Range<String.Index>

    /// Creates a `ParserInput` wrapping `scanner`.
    ///
    /// No tokens are produced during initialisation.
    public init(_ scanner: Scanner, source: String) {
        self.scanner  = scanner
        let end       = source.endIndex
        self.eofRange = end ..< end
    }

    /// Returns the token `n` positions ahead of the current position **without
    /// consuming it**.
    ///
    /// `peek(ahead: 1)` (the default) returns the next token to be consumed.
    /// `peek(ahead: 2)` returns the one after that, and so on.
    ///
    /// The lookahead queue is filled lazily: if the queue does not yet contain
    /// `n` tokens, the scanner is called until it does (or until the input is
    /// exhausted).
    ///
    /// Returns `nil` when fewer than `n` tokens remain.
    public mutating func peek(ahead n: Int = 1) -> Token? {
        precondition(n >= 1, "peek(ahead:) requires n ≥ 1")
        while lookahead.count < n {
            guard let token = scanner.next() else { return nil }
            lookahead.append(token)
        }
        return lookahead[n - 1]
    }

    /// Removes and returns the next token from the stream.
    ///
    /// If the lookahead queue has a buffered token it is returned first;
    /// otherwise the scanner is called directly.
    ///
    /// Returns `nil` when the input is exhausted.
    @discardableResult
    public mutating func consume() -> Token? {
        if !lookahead.isEmpty {
            return lookahead.removeFirst()
        }
        return scanner.next()
    }

    /// Removes and returns the next token, or an `.eof` sentinel token when
    /// the input is exhausted.
    ///
    /// Prefer this over `consume()` in parsers that use a sentinel-based loop
    /// rather than an optional-based loop.
    @discardableResult
    public mutating func get() -> Token {
        consume() ?? Token(type: .eof, range: eofRange)
    }

    /// `true` when the scanner is exhausted *and* the lookahead queue is empty.
    public var isEmpty: Bool {
        lookahead.isEmpty && scanner.isEmpty
    }

    // MARK: - Convenience: match & expect

    /// Returns `true` (and consumes the token) if the next token's type equals
    /// `type`.  Returns `false` and leaves the stream unchanged otherwise.
    public mutating func match(_ type: TokenType) -> Bool {
        guard peek()?.type == type else { return false }
        consume()
        return true
    }

    /// Consumes the next token and returns it if its type equals `type`.
    /// Returns `nil` without consuming if the type does not match.
    public mutating func accept(_ type: TokenType) -> Token? {
        guard peek()?.type == type else { return nil }
        return consume()
    }
}
