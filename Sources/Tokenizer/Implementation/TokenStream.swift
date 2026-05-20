//
//  TokenStream.swift
//  GrammarTokenizer
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/12.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

//  ┌─────────────────────────────────────────────────────────────────────────┐
//  │  Architecture                                                           │
//  │                                                                         │
//  │  Tokenizing (protocol)        — public consumer-facing contract         │
//  │       │                                                                 │
//  │  TokenStream (open class)     — shared scanning engine (no buffer)      │
//  │       │                                                                 │
//  │       ├── Tokenizer           — general purpose; caller supplies        │
//  │       │                         symbols + keywords                      │
//  │       ├── GrammarTokenizer    — pre-configured for BNF/EBNF grammar     │
//  │       │                         *definitions*                           │
//  │       └── InputTokenizer      — configured at runtime from a grammar's  │
//  │                                 terminal set; used to lex the *input    │
//  │                                 text* a grammar describes               │
//  │                                                                         │
//  │  Lookahead / peek                                                       │
//  │  ─────────────────                                                      │
//  │  All tokenizers share a lazy lookahead queue managed by ParserInput.    │
//  │  TokenStream itself has no internal buffer; it is a pure scanner.       │
//  │  Callers that need peek / consume wrap any TokenStream subclass in      │
//  │  ParserInput (see ParserInput.swift).                                   │
//  └─────────────────────────────────────────────────────────────────────────┘

/// The public interface every concrete tokenizer exposes.
public protocol Tokenizing: AnyObject {

    /// Returns the next token, or `nil` when input is exhausted.
    func next() -> Token?

    /// Collects every token into an array.  Appends a single
    /// `.invalid(.unrecognizedInput)` token at the end if any characters were
    /// left unconsumed after the main scan loop ends.
    func tokenize() -> [Token]

    /// `true` when the underlying character view is fully consumed.
    var isEmpty: Bool { get }

    /// The symbol set active for this tokenizer (built-in defaults merged with
    /// any caller-supplied symbols).
    var symbols: Set<String> { get }

    /// The keyword set active for this tokenizer.
    var keywords: Set<String> { get }
    
    /// The source range end-index, cached for constructing `.eof` tokens.
    var endIndex: String.Index { get }
}

/// Wraps any `Tokenizing` object as a Swift `Sequence` of `Token` values,
/// enabling `for token in TokenSequence(myTokenizer) { … }`.
///
/// Separating the sequence from the tokenizer avoids the "single-pass iterator
/// that is also its own sequence" trap in the original design, where mixing
/// `for … in` and direct `next()` calls produced silent ordering bugs.
public struct TokenSequence<T: Tokenizing>: Sequence, IteratorProtocol {
    private let tokenizer: T

    public init(_ tokenizer: T) { self.tokenizer = tokenizer }

    public mutating func next() -> Token? { tokenizer.next() }
}

/// The shared scanning engine inherited by all concrete tokenizers.
///
/// `TokenStream` owns the `UnicodeScalarView` cursor, the symbol `Trie`, and
/// the keyword set.  Its single responsibility is `nextToken()` — advance the
/// cursor by one token and classify it.
///
/// Aspects of Extension Points
/// **Open** so that `GrammarTokenizer`, `InputTokenizer`, and user-defined
/// subclasses can override `nextToken()` when they need custom scanning
/// behaviour (e.g. indentation-sensitive scanning).
open class TokenStream: Tokenizing {
    
    // Always registered regardless of the caller's additions.
    // These are the minimum needed to recognise string literals, regex literals,
    // line comments, and both C-style and Pascal-style block comments.
    public static let builtInSymbols: Set<String> = [
        ".", ",", ";", ":",     // common punctuation
        "'", "\"",              // string literal delimiters
        "#", "//",              // line-comment markers
        "/",                    // regex delimiter (also the prefix of // and /*)
        "/*", "*/",             // C-style block comment
        "(*", "*)"              // Pascal-style block comment
    ]
    
    // MARK: - Stored state
    
    /// Sliding-window cursor over the original source string.
    /// Declared `internal` so subclasses and parser extension methods can read it.
    var characters: UnicodeScalarView
    
    /// Maximum-munch symbol matcher built during `init`.
    private var trie: Trie<Character> = .empty
    
    public private(set) var symbols:  Set<String>
    public private(set) var keywords: Set<String>
    
    public var endIndex: String.Index {
        self.characters.endIndex
    }
    
    // MARK: - Initialisation
    
    /// Designated initialiser used by all subclasses.
    ///
    /// - Parameters:
    ///   - source:   The complete input string to scan.
    ///   - symbols:  Domain-specific operator / punctuation strings to recognise
    ///               in addition to the built-in set.
    ///   - keywords: Reserved words emitted as `.keyword` rather than
    ///               `.identifier`.
    public init(_ source: String, symbols: Set<String> = [], keywords: Set<String> = []) {
        self.characters = UnicodeScalarView(source.unicodeScalars)
        self.symbols    = TokenStream.builtInSymbols.union(symbols)
        self.keywords   = keywords
        
        // Build the Trie once; no further mutations after init.
        for symbol in self.symbols {
            trie = trie.inserting(symbol)
        }
    }

    // MARK: - Tokenizing conformance
    
    /// `true` when the underlying character view is fully consumed.
    public var isEmpty: Bool { characters.isEmpty }

    /// Returns the next token by delegating to `nextToken()`.
    /// Subclasses should override `nextToken()`, not this method.
    public final func next() -> Token? { nextToken() }

    /// Classifies exactly one token from `characters` and returns it.
    ///
    /// Scanning order:
    ///  1. Skip leading whitespace and newlines.
    ///  2. Attempt maximum-munch symbol match via the Trie.
    ///     • Recognised trigger symbols dispatch to sub-parsers for literals,
    ///       comments, and regex definitions.
    ///     • All other matched symbols are emitted directly as `.symbol`.
    ///  3. If no symbol matches, try identifier / number parsing.
    ///  4. Return `nil` if the view is empty or the first character is
    ///     unclassifiable (the residual text is handled by `tokenize()`).
    ///
    /// Subclasses may override this method to inject additional token classes
    /// (e.g. indentation tokens, interpolation markers).
    ///
    /// Implementation note: Why you cannot put this in its own extension.
    /// In Swift, extensions are designed to add new functionality, not modify or override
    /// existing behavior. If you try to override a method declared in a superclass's
    /// extension, the compiler lacks the necessary dynamic dispatch information to
    /// link the call to your subclass implementation. It is a Swift limitation.
    ///
    /// There are two primary ways to resolve this:
    /// 1. Move implemetation to main definition (this implementation does so).
    /// 2. Or enable dynamic dispatch at runtime (Objective-C features).

    open func nextToken() -> Token? {
        
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
        if CharacterSet.letters.contains(first) || first == "_" {
            return characters.parseIdentifier(startIndex: tokenStart, keywords: keywords)
        }
        if first >= "0" && first <= "9" {
            return characters.parseNumber(startIndex: tokenStart)
        }
        
        // Unclassifiable character — return nil so tokenize() can produce a
        // single `.invalid(.unrecognizedInput)` token for the residual text.
        return nil
    }
}
    
extension TokenStream {

    /// Eagerly generating an array of tokens from input string. It also guards against
    /// any unrecognized part of input data after processing.
    public func tokenize() -> [Token] {
        var result: [Token] = []
        while let token = nextToken() {
            result.append(token)
        }
        
        // Any characters that survived the scan loop matched nothing.
        // Wrap them in one diagnostic token rather than silently discarding.
        // (residual-input guard)
        if !characters.isEmpty {
            result.append(Token(
                type: .invalid(.unrecognizedInput(String(characters))),
                range: characters.range
            ))
        }
        return result
    }
}
