//
//  TokenizerTests.swift
//  TokenizerTests
//
//  Comprehensive test suite for the revised Tokenizer module.
//
//  Coverage
//  ────────
//  • TokenizerCoreTests      — protocol conformance, base scanner behaviour
//  • TokenizerTests          — general-purpose subclass
//  • GrammarTokenizerTests   — pre-configured BNF symbol set
//  • InputTokenizerTests     — runtime-configured terminal set
//  • ParserInputTests        — lazy lookahead queue (peek, consume, get, match, accept)
//  • TokenSequenceTests      — Sequence / IteratorProtocol bridge
//  • IdentifierTests         — identifier grammar incl. underscore head and hyphen
//  • KeywordTests            — keyword recognition and case sensitivity
//  • SymbolTests             — single- and multi-char symbols, max-munch
//  • LiteralTests            — single/double-quoted strings, unterminated error
//  • NumberTests             — decimal, hex, octal, binary, malformed
//  • CommentTests            — line (#, //), block (/* */, (* *)), unterminated
//  • RegexTests              — /pattern/, unterminated
//  • WhitespaceTests         — skip behaviour, empty input
//  • ErrorTokenTests         — unrecognized characters, stray comment closers
//  • SourceRangeTests        — token.location(in:) byte offsets
//  • TrieTests               — insertion, longestMatch, word enumeration
//  • UnicodeScalarViewTests  — cursor operations
//  • TokenizerUtilsTests     — numeric conversions, line/column mapping
//  • FullGrammarTests        — multi-rule BNF grammar end-to-end

import XCTest
@testable import Tokenizer

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

private func bnf(_ source: String) -> [Token] {
    GrammarTokenizer(source).tokenize()
}

private func types(_ tokens: [Token]) -> [TokenType] {
    tokens.map(\.type)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TokenizerCoreTests
// ─────────────────────────────────────────────────────────────────────────────

final class TokenizerCoreTests: XCTestCase {

    func test_isEmpty_onEmptySource() {
        let t = Tokenizer("", symbols: [], keywords: [])
        XCTAssertTrue(t.isEmpty)
    }

    func test_isEmpty_afterFullTokenize() {
        let t = Tokenizer("hello", symbols: [], keywords: [])
        _ = t.tokenize()
        XCTAssertTrue(t.isEmpty)
    }

    func test_next_returnsNilWhenExhausted() {
        let t = Tokenizer("x", symbols: [], keywords: [])
        _ = t.next()          // consumes "x"
        XCTAssertNil(t.next())
    }

    func test_symbols_containBuiltIns() {
        let t = Tokenizer("", symbols: [], keywords: [])
        XCTAssertTrue(t.symbols.contains("//"))
        XCTAssertTrue(t.symbols.contains("/*"))
        XCTAssertTrue(t.symbols.contains("\""))
    }

    func test_symbols_mergedWithCaller() {
        let t = Tokenizer("", symbols: ["::="], keywords: [])
        XCTAssertTrue(t.symbols.contains("::="))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - General Tokenizer
// ─────────────────────────────────────────────────────────────────────────────

final class TokenizerTests: XCTestCase {

    func test_singleIdentifier() {
        let t = Tokenizer("hello", symbols: [], keywords: [])
        XCTAssertEqual(types(t.tokenize()), [.identifier("hello")])
    }

    func test_customSymbol() {
        let t = Tokenizer("a -> b", symbols: ["->"], keywords: [])
        XCTAssertEqual(types(t.tokenize()), [
            .identifier("a"), .symbol("->"), .identifier("b")
        ])
    }

    func test_customKeyword() {
        let t = Tokenizer("let x", symbols: [], keywords: ["let"])
        XCTAssertEqual(types(t.tokenize()), [.keyword("let"), .identifier("x")])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - GrammarTokenizer
// ─────────────────────────────────────────────────────────────────────────────

final class GrammarTokenizerTests: XCTestCase {

    func test_bnfSymbols_registered() {
        let t = GrammarTokenizer("")
        for sym in GrammarTokenizer.bnfSymbols {
            XCTAssertTrue(t.symbols.contains(sym), "Missing BNF symbol: \(sym)")
        }
    }

    func test_simpleRule() {
        XCTAssertEqual(types(bnf("rule ::= \"a\" | \"b\" ;")), [
            .identifier("rule"),
            .symbol("::="),
            .literal("a"),
            .symbol("|"),
            .literal("b"),
            .symbol(";")
        ])
    }

    func test_extraSymbols_merged() {
        let t = GrammarTokenizer("", extraSymbols: ["@"])
        XCTAssertTrue(t.symbols.contains("@"))
    }

    func test_extraKeywords_registered() {
        let t = GrammarTokenizer("rule", extraKeywords: ["rule"])
        XCTAssertEqual(types(t.tokenize()), [.keyword("rule")])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - InputTokenizer
// ─────────────────────────────────────────────────────────────────────────────

final class InputTokenizerTests: XCTestCase {

    func test_terminalSymbols_registered() {
        let t = InputTokenizer("", terminalSymbols: ["+", "-", "*"])
        XCTAssertTrue(t.symbols.contains("+"))
        XCTAssertTrue(t.symbols.contains("-"))
        XCTAssertTrue(t.symbols.contains("*"))
    }

    func test_reservedWords_recognised() {
        let t = InputTokenizer("if x", reservedWords: ["if"])
        XCTAssertEqual(types(t.tokenize()), [.keyword("if"), .identifier("x")])
    }

    func test_tokenizesInput_withGrammarTerminals() {
        let t = InputTokenizer(
            "count + 1",
            terminalSymbols: ["+"],
            reservedWords:   []
        )
        XCTAssertEqual(types(t.tokenize()), [
            .identifier("count"),
            .symbol("+"),
            .number(.decimal(1))
        ])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ParserInput  (lazy lookahead queue)
// ─────────────────────────────────────────────────────────────────────────────

final class ParserInputTests: XCTestCase {

    private func makeInput(_ source: String) -> ParserInput<Tokenizer> {
        let t = Tokenizer(source, symbols: ["::=", "|"], keywords: ["rule"])
        return ParserInput(t, source: source)
    }

    // ── peek ────────────────────────────────────────────────────────────────

    func test_peek1_returnsFirstToken_withoutConsuming() {
        var input = makeInput("a b c")
        let p = input.peek(ahead: 1)
        XCTAssertEqual(p?.type, .identifier("a"))
        // Peeking again returns the same token.
        XCTAssertEqual(input.peek(ahead: 1)?.type, .identifier("a"))
    }

    func test_peek2_returnsSecondToken() {
        var input = makeInput("a b c")
        XCTAssertEqual(input.peek(ahead: 2)?.type, .identifier("b"))
    }

    func test_peek3_returnsThirdToken() {
        var input = makeInput("a b c")
        XCTAssertEqual(input.peek(ahead: 3)?.type, .identifier("c"))
    }

    func test_peek_pastEnd_returnsNil() {
        var input = makeInput("a")
        XCTAssertNil(input.peek(ahead: 2))
    }

    func test_peek_doesNotAdvanceStream() {
        var input = makeInput("a b")
        _ = input.peek(ahead: 1)
        _ = input.peek(ahead: 1)
        XCTAssertEqual(input.consume()?.type, .identifier("a"))
    }

    // ── consume ──────────────────────────────────────────────────────────────

    func test_consume_drainsQueue_thenScanner() {
        var input = makeInput("a b c")
        _ = input.peek(ahead: 2)          // fill queue with "a", "b"
        XCTAssertEqual(input.consume()?.type, .identifier("a"))
        XCTAssertEqual(input.consume()?.type, .identifier("b"))
        XCTAssertEqual(input.consume()?.type, .identifier("c"))
        XCTAssertNil(input.consume())
    }

    func test_consume_returnsNilWhenExhausted() {
        var input = makeInput("")
        XCTAssertNil(input.consume())
    }

    // ── get ──────────────────────────────────────────────────────────────────

    func test_get_returnsEof_whenExhausted() {
        var input = makeInput("x")
        _ = input.get()                   // consume "x"
        XCTAssertEqual(input.get().type, .eof)
    }

    // ── isEmpty ──────────────────────────────────────────────────────────────

    func test_isEmpty_trueOnEmptySource() {
        var input = makeInput("")
        XCTAssertTrue(input.isEmpty)
    }

    func test_isEmpty_falseWhileTokensRemain() {
        var input = makeInput("a")
        XCTAssertFalse(input.isEmpty)
    }

    func test_isEmpty_trueAfterConsuming() {
        var input = makeInput("a")
        _ = input.consume()
        XCTAssertTrue(input.isEmpty)
    }

    // ── match ────────────────────────────────────────────────────────────────

    func test_match_consumesOnTypeMatch() {
        var input = makeInput("rule a")
        XCTAssertTrue(input.match(.keyword("rule")))
        XCTAssertEqual(input.consume()?.type, .identifier("a"))
    }

    func test_match_doesNotConsumeOnMismatch() {
        var input = makeInput("a b")
        XCTAssertFalse(input.match(.keyword("rule")))
        XCTAssertEqual(input.consume()?.type, .identifier("a"))
    }

    // ── accept ───────────────────────────────────────────────────────────────

    func test_accept_returnsToken_onTypeMatch() {
        var input = makeInput("rule a")
        let t = input.accept(.keyword("rule"))
        XCTAssertNotNil(t)
        XCTAssertEqual(t?.type, .keyword("rule"))
    }

    func test_accept_returnsNil_onMismatch() {
        var input = makeInput("a b")
        XCTAssertNil(input.accept(.keyword("rule")))
        XCTAssertEqual(input.consume()?.type, .identifier("a"))
    }

    // ── No init side effects ─────────────────────────────────────────────────

    func test_init_hasNoSideEffectsOnScanner() {
        // Constructing ParserInput must not call nextToken() on the scanner.
        // We verify this by checking that all tokens are still available.
        let source = "a b c"
        let scanner = Tokenizer(source, symbols: [], keywords: [])
        var input   = ParserInput(scanner, source: source)
        var collected: [TokenType] = []
        while let t = input.consume() { collected.append(t.type) }
        XCTAssertEqual(collected, [.identifier("a"), .identifier("b"), .identifier("c")])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TokenSequence
// ─────────────────────────────────────────────────────────────────────────────

final class TokenSequenceTests: XCTestCase {

    func test_forIn_producesAllTokens() {
        let t = GrammarTokenizer("a b c")
        var result: [TokenType] = []
        for tok in TokenSequence(t) { result.append(tok.type) }
        XCTAssertEqual(result, [.identifier("a"), .identifier("b"), .identifier("c")])
    }

    func test_tokenSequence_matchesTokenize() {
        let source = "rule greeting ::= \"hello\" ;"
        let t1 = GrammarTokenizer(source)
        let t2 = GrammarTokenizer(source)
        let bySeq = TokenSequence(t1).map(\.type)
        let byTokenize = t2.tokenize().map(\.type)
        XCTAssertEqual(bySeq, byTokenize)
    }

    func test_tokenSequence_independentOfDirectNext() {
        // TokenSequence wraps the scanner in a struct; calling next() on the
        // *scanner* directly after creating a TokenSequence should not corrupt
        // the sequence (they share the same scanner object, so the sequence
        // simply sees the remaining tokens from that point).
        let t = GrammarTokenizer("a b c")
        _ = t.next()               // consume "a" directly on the scanner
        var seq = TokenSequence(t)
        XCTAssertEqual(seq.next()?.type, .identifier("b"))
        XCTAssertEqual(seq.next()?.type, .identifier("c"))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Identifiers
// ─────────────────────────────────────────────────────────────────────────────

final class IdentifierTests: XCTestCase {

    func test_singleLetter()              { XCTAssertEqual(types(bnf("x")),    [.identifier("x")]) }
    func test_multiLetter()               { XCTAssertEqual(types(bnf("hello")), [.identifier("hello")]) }
    func test_withDigits()                { XCTAssertEqual(types(bnf("rule2")), [.identifier("rule2")]) }

    func test_underscoreHead() {
        // Leading underscore must be accepted (grammar: [_A-Za-z]…).
        XCTAssertEqual(types(bnf("_private")), [.identifier("_private")])
    }

    func test_underscoreOnly() {
        XCTAssertEqual(types(bnf("_")), [.identifier("_")])
    }

    func test_hyphenatedBnfStyleName() {
        XCTAssertEqual(types(bnf("non-terminal")), [.identifier("non-terminal")])
    }

    func test_mixedUnderscoreAndDigits() {
        XCTAssertEqual(types(bnf("_my_rule_2")), [.identifier("_my_rule_2")])
    }

    func test_digitHead_notAnIdentifier() {
        // "1abc" — "1" is a number, "abc" is a separate identifier.
        XCTAssertEqual(types(bnf("1abc")), [.number(.decimal(1)), .identifier("abc")])
    }

    func test_multiple_identifiers() {
        XCTAssertEqual(types(bnf("a b c")), [
            .identifier("a"), .identifier("b"), .identifier("c")
        ])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Keywords
// ─────────────────────────────────────────────────────────────────────────────

final class KeywordTests: XCTestCase {

    private func tok(_ source: String, kw: Set<String> = ["rule", "token", "let"]) -> [Token] {
        Tokenizer(source, symbols: [], keywords: kw).tokenize()
    }

    func test_keyword_matched()           { XCTAssertEqual(types(tok("rule")),  [.keyword("rule")]) }
    func test_keyword_token()             { XCTAssertEqual(types(tok("token")), [.keyword("token")]) }
    func test_keyword_let()               { XCTAssertEqual(types(tok("let")),   [.keyword("let")]) }

    func test_keyword_caseSensitive() {
        // Keywords are case-sensitive; "RULE" should be an identifier.
        XCTAssertEqual(types(tok("RULE")), [.identifier("RULE")])
    }

    func test_prefix_of_keyword_is_identifier() {
        XCTAssertEqual(types(tok("rul")), [.identifier("rul")])
    }

    func test_keyword_followed_by_identifier() {
        XCTAssertEqual(types(tok("rule greeting")), [.keyword("rule"), .identifier("greeting")])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Symbols
// ─────────────────────────────────────────────────────────────────────────────

final class SymbolTests: XCTestCase {

    func test_singleChar_pipe()      { XCTAssertEqual(types(bnf("|")),   [.symbol("|")]) }
    func test_singleChar_semicolon() { XCTAssertEqual(types(bnf(";")),   [.symbol(";")]) }
    func test_multiChar_bnf()        { XCTAssertEqual(types(bnf("::=")), [.symbol("::=")]) }

    func test_maxMunch_preferLonger() {
        // "::=" must be preferred over ":" or "::"
        let tokens = bnf("::=")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].type, .symbol("::="))
    }

    func test_maxMunch_slashVsDoubleSlash() {
        // "// comment" — the Trie must pick "//" not "/"
        let tokens = bnf("// comment")
        XCTAssertEqual(tokens.count, 1)
        if case .comment(_) = tokens[0].type { } else { XCTFail() }
    }

    func test_consecutive_symbols() {
        XCTAssertEqual(types(bnf("()")), [.symbol("("), .symbol(")")])
    }

    func test_symbols_between_identifiers() {
        XCTAssertEqual(types(bnf("a|b")), [.identifier("a"), .symbol("|"), .identifier("b")])
    }

    func test_stray_closing_comment_marker_is_invalid() {
        // "*/" at the top level is a user error; must not fatalError.
        let tokens = bnf("*/")
        XCTAssertEqual(tokens.count, 1)
        if case .invalid(.unrecognizedInput(let s)) = tokens[0].type {
            XCTAssertEqual(s, "*/")
        } else {
            XCTFail("Expected .invalid(.unrecognizedInput(\"*/\")), got \(tokens[0].type)")
        }
    }

    func test_stray_pascal_closing_marker_is_invalid() {
        let tokens = bnf("*)")
        XCTAssertEqual(tokens.count, 1)
        if case .invalid(.unrecognizedInput(_)) = tokens[0].type { } else { XCTFail() }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Literals
// ─────────────────────────────────────────────────────────────────────────────

final class LiteralTests: XCTestCase {

    func test_doubleQuoted()     { XCTAssertEqual(types(bnf("\"hello\"")), [.literal("hello")]) }
    func test_singleQuoted()     { XCTAssertEqual(types(bnf("'world'")),   [.literal("world")]) }
    func test_emptyDouble()      { XCTAssertEqual(types(bnf("\"\"")),       [.literal("")]) }
    func test_emptySingle()      { XCTAssertEqual(types(bnf("''")),         [.literal("")]) }

    func test_literalWithSpaces() {
        XCTAssertEqual(types(bnf("\"hello world\"")), [.literal("hello world")])
    }

    func test_literalWithSymbolsInside() {
        XCTAssertEqual(types(bnf("\"a ::= b\"")), [.literal("a ::= b")])
    }

    func test_unterminated_double() {
        let t = bnf("\"unterminated")
        XCTAssertEqual(t.count, 1)
        if case .invalid(.unterminatedString(let s)) = t[0].type {
            XCTAssertEqual(s, "unterminated")
        } else { XCTFail() }
    }

    func test_unterminated_single() {
        let t = bnf("'oops")
        XCTAssertEqual(t.count, 1)
        if case .invalid(.unterminatedString(_)) = t[0].type { } else { XCTFail() }
    }

    func test_two_literals() {
        XCTAssertEqual(types(bnf("\"a\" \"b\"")), [.literal("a"), .literal("b")])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Numbers
// ─────────────────────────────────────────────────────────────────────────────

final class NumberTests: XCTestCase {

    func test_zero()         { XCTAssertEqual(types(bnf("0")),   [.number(.decimal(0))]) }
    func test_decimal()      { XCTAssertEqual(types(bnf("42")),  [.number(.decimal(42))]) }
    func test_large()        { XCTAssertEqual(types(bnf("9999")), [.number(.decimal(9999))]) }

    func test_hexadecimal() {
        XCTAssertEqual(types(bnf("0xFF")), [.number(.hexadecimal(255))])
    }

    func test_hexadecimal_uppercase_prefix() {
        XCTAssertEqual(types(bnf("0XFF")), [.number(.hexadecimal(255))])
    }

    func test_octal() {
        XCTAssertEqual(types(bnf("0o17")), [.number(.octal(15))])
    }

    func test_binary() {
        XCTAssertEqual(types(bnf("0b1010")), [.number(.binary(10))])
    }

    func test_malformed_hex_prefix() {
        // "0x" with no digits following is malformed.
        let t = bnf("0x")
        XCTAssertEqual(t.count, 1)
        if case .invalid(.malformedNumber) = t[0].type { } else { XCTFail("Expected malformedNumber, got \(t[0].type)") }
    }

    func test_malformed_binary_prefix() {
        let t = bnf("0b")
        XCTAssertEqual(t.count, 1)
        if case .invalid(.malformedNumber) = t[0].type { } else { XCTFail() }
    }

    func test_number_then_identifier() {
        XCTAssertEqual(types(bnf("42abc")), [.number(.decimal(42)), .identifier("abc")])
    }

    func test_number_then_symbol() {
        XCTAssertEqual(types(bnf("7|")), [.number(.decimal(7)), .symbol("|")])
    }

    func test_numerical_intValue() {
        XCTAssertEqual(Numerical.decimal(5).intValue,     5)
        XCTAssertEqual(Numerical.hexadecimal(255).intValue, 255)
        XCTAssertEqual(Numerical.octal(8).intValue,       8)
        XCTAssertEqual(Numerical.binary(3).intValue,      3)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Comments
// ─────────────────────────────────────────────────────────────────────────────

final class CommentTests: XCTestCase {

    func test_doubleSlash() {
        let t = bnf("// line comment")
        XCTAssertEqual(t.count, 1)
        if case .comment(let body) = t[0].type {
            XCTAssertTrue(body.contains("line comment"))
        } else { XCTFail() }
    }

    func test_hash() {
        let t = bnf("# hash comment")
        XCTAssertEqual(t.count, 1)
        if case .comment(_) = t[0].type { } else { XCTFail() }
    }

    func test_lineComment_doesNotConsumeNextLine() {
        let t = bnf("// comment\nidentifier")
        XCTAssertEqual(t.count, 2)
        XCTAssertEqual(t[1].type, .identifier("identifier"))
    }

    func test_lineComment_emptyBody_atEOF() {
        // "//" at the very end of input, no trailing newline.
        let t = bnf("//")
        XCTAssertEqual(t.count, 1)
        if case .comment(_) = t[0].type { } else { XCTFail() }
    }

    func test_lineComment_body_excludesDelimiter() {
        let t = bnf("// hello")
        if case .comment(let body) = t[0].type {
            XCTAssertFalse(body.hasPrefix("//"))
        } else { XCTFail() }
    }

    func test_cStyleBlock() {
        let t = bnf("/* block */")
        XCTAssertEqual(t.count, 1)
        if case .comment(_) = t[0].type { } else { XCTFail() }
    }

    func test_pascalStyleBlock() {
        let t = bnf("(* pascal *)")
        XCTAssertEqual(t.count, 1)
        if case .comment(_) = t[0].type { } else { XCTFail() }
    }

    func test_blockComment_multiLine() {
        let t = bnf("/* line one\nline two */")
        XCTAssertEqual(t.count, 1)
        if case .comment(let body) = t[0].type {
            XCTAssertTrue(body.contains("line one"))
            XCTAssertTrue(body.contains("line two"))
        } else { XCTFail() }
    }

    func test_unterminatedBlock_isInvalid_notNil() {
        // Original bug: returned nil, then silently re-parsed the opening "/*".
        // New behaviour: returns .invalid(.unterminatedString).
        let t = bnf("/* never closed")
        XCTAssertEqual(t.count, 1)
        if case .invalid(.unterminatedString(_)) = t[0].type { }
        else { XCTFail("Expected unterminatedString, got \(t[0].type)") }
    }

    func test_unterminatedPascalBlock_isInvalid() {
        let t = bnf("(* never closed")
        XCTAssertEqual(t.count, 1)
        if case .invalid(.unterminatedString(_)) = t[0].type { } else { XCTFail() }
    }

    func test_codeAfterLineComment() {
        let t = bnf("rule // comment\nname")
        XCTAssertEqual(t.count, 3)
        XCTAssertEqual(t[0].type, .identifier("rule"))
        if case .comment(_) = t[1].type { } else { XCTFail() }
        XCTAssertEqual(t[2].type, .identifier("name"))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Regex
// ─────────────────────────────────────────────────────────────────────────────

final class RegexTests: XCTestCase {

    func test_simple() {
        let t = bnf("/[a-z]+/")
        XCTAssertEqual(t.count, 1)
        if case .regex(let body) = t[0].type {
            XCTAssertEqual(body, "[a-z]+")
        } else { XCTFail() }
    }

    func test_digits() {
        let t = bnf("/[0-9]*/")
        XCTAssertEqual(t.count, 1)
        if case .regex(_) = t[0].type { } else { XCTFail() }
    }

    func test_unterminated() {
        let t = bnf("/unterminated")
        XCTAssertEqual(t.count, 1)
        if case .invalid(.unterminatedString(_)) = t[0].type { } else { XCTFail() }
    }

    func test_regexAmongOtherTokens() {
        let t = bnf("/[A-Z]+/ ;")
        XCTAssertEqual(t.count, 2)
        if case .regex(_) = t[0].type { } else { XCTFail() }
        XCTAssertEqual(t[1].type, .symbol(";"))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Whitespace
// ─────────────────────────────────────────────────────────────────────────────

final class WhitespaceTests: XCTestCase {

    func test_leadingSkipped()     { XCTAssertEqual(types(bnf("   hello")), [.identifier("hello")]) }
    func test_trailingSkipped()    { XCTAssertEqual(types(bnf("hello   ")), [.identifier("hello")]) }
    func test_tabsSkipped()        { XCTAssertEqual(types(bnf("\thello\t")), [.identifier("hello")]) }
    func test_newlinesSkipped()    { XCTAssertEqual(types(bnf("\n\nhello\n\n")), [.identifier("hello")]) }
    func test_emptyInput()         { XCTAssertTrue(bnf("").isEmpty) }
    func test_whitespaceOnlyInput(){ XCTAssertTrue(bnf("   \t\n  ").isEmpty) }

    func test_tokensBetweenWhitespace() {
        XCTAssertEqual(types(bnf("a  \t  b")), [.identifier("a"), .identifier("b")])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Error tokens
// ─────────────────────────────────────────────────────────────────────────────

final class ErrorTokenTests: XCTestCase {

    func test_unrecognized_character() {
        let t = bnf("@")
        XCTAssertEqual(t.count, 1)
        if case .invalid(.unrecognizedInput(_)) = t[0].type { } else { XCTFail() }
    }

    func test_valid_then_unrecognized() {
        let t = bnf("hello @")
        XCTAssertEqual(t.count, 2)
        XCTAssertEqual(t[0].type, .identifier("hello"))
        if case .invalid(_) = t[1].type { } else { XCTFail() }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Source ranges
// ─────────────────────────────────────────────────────────────────────────────

final class SourceRangeTests: XCTestCase {

    func test_singleToken_offset() {
        let source = "hello"
        let t = bnf(source)
        let loc = t[0].location(in: source)
        XCTAssertEqual(loc.start, 0)
        XCTAssertEqual(loc.end,   5)
    }

    func test_secondToken_offset() {
        let source = "foo bar"
        let t = bnf(source)
        let loc = t[1].location(in: source)
        XCTAssertEqual(loc.start, 4)
        XCTAssertEqual(loc.end,   7)
    }

    func test_symbol_offset() {
        let source = "rule::="
        let t = bnf(source)
        // "rule" (identifier) at 0–4, "::=" (symbol) at 4–7
        let sym = t[1].location(in: source)
        XCTAssertEqual(sym.start, 4)
        XCTAssertEqual(sym.end,   7)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Trie
// ─────────────────────────────────────────────────────────────────────────────

final class TrieTests: XCTestCase {

    func test_emptyTrie_noMatch() {
        var view   = UnicodeScalarView("abc")
        let result = Trie<Character>.empty.longestMatch(in: &view)
        XCTAssertNil(result)
        XCTAssertEqual(String(view), "abc")    // view unchanged
    }

    func test_singleSymbol_matched() {
        let trie = Trie<Character>.empty.inserting("|")
        var view = UnicodeScalarView("|rest")
        let result = trie.longestMatch(in: &view)
        XCTAssertEqual(result, "|")
        XCTAssertEqual(String(view), "rest")
    }

    func test_longerSymbol_preferredOverShorter() {
        let trie = Trie<Character>.empty
            .inserting("/")
            .inserting("//")
        var view = UnicodeScalarView("//comment")
        XCTAssertEqual(trie.longestMatch(in: &view), "//")
        XCTAssertEqual(String(view), "comment")
    }

    func test_shorterSymbol_whenLongerAbsent() {
        let trie = Trie<Character>.empty
            .inserting("/")
            .inserting("//")
        var view = UnicodeScalarView("/x")
        XCTAssertEqual(trie.longestMatch(in: &view), "/")
        XCTAssertEqual(String(view), "x")
    }

    func test_noMatch_doesNotAdvanceView() {
        let trie = Trie<Character>.empty.inserting("::=")
        var view = UnicodeScalarView("hello")
        XCTAssertNil(trie.longestMatch(in: &view))
        XCTAssertEqual(String(view), "hello")
    }

    func test_words_containsAll() {
        let trie = Trie<Character>.empty
            .inserting("a")
            .inserting("ab")
            .inserting("abc")
        let words = trie.words.map { String($0) }.sorted()
        XCTAssertEqual(words, ["a", "ab", "abc"])
    }

    func test_returns_string_not_array() {
        // longestMatch now returns String?, eliminating the nil-vs-empty ambiguity.
        let trie = Trie<Character>.empty.inserting("|")
        var view = UnicodeScalarView("|")
        let result: String? = trie.longestMatch(in: &view)
        XCTAssertEqual(result, "|")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - UnicodeScalarView
// ─────────────────────────────────────────────────────────────────────────────

final class UnicodeScalarViewTests: XCTestCase {

    func test_isEmpty_onEmpty()      { XCTAssertTrue(UnicodeScalarView("").isEmpty) }
    func test_first_returnsFirst()   { XCTAssertEqual(UnicodeScalarView("abc").first, Unicode.Scalar("a")) }

    func test_popFirst_consumesScalar() {
        var v = UnicodeScalarView("abc")
        XCTAssertEqual(v.popFirst(), Unicode.Scalar("a"))
        XCTAssertEqual(String(v), "bc")
    }

    func test_popFirst_onEmpty_isNil() {
        var v = UnicodeScalarView("")
        XCTAssertNil(v.popFirst())
    }

    func test_removeFirst_n() {
        var v = UnicodeScalarView("hello")
        v.removeFirst(2)
        XCTAssertEqual(String(v), "llo")
    }

    func test_suffixFrom() {
        let v   = UnicodeScalarView("hello")
        let idx = v.index(v.startIndex, offsetBy: 2)
        XCTAssertEqual(String(v.suffix(from: idx)), "llo")
    }

    func test_prefixUpTo() {
        let v   = UnicodeScalarView("hello")
        let idx = v.index(v.startIndex, offsetBy: 3)
        XCTAssertEqual(String(v.prefix(upTo: idx)), "hel")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TokenizerUtils
// ─────────────────────────────────────────────────────────────────────────────

final class TokenizerUtilsTests: XCTestCase {

    func test_integerValue()  { XCTAssertEqual("42".integerValue, 42);  XCTAssertNil("abc".integerValue) }
    func test_hexValue()      { XCTAssertEqual("0xFF".hexValue, 255);   XCTAssertEqual("0x1A".hexValue, 26) }
    func test_binaryValue()   { XCTAssertEqual("0b1010".binaryValue, 10) }
    func test_octalValue()    { XCTAssertEqual("0o17".octalValue, 15) }
    func test_trimPrefix()    { XCTAssertEqual("0xFF".trim(prefix: "0x"), "FF"); XCTAssertEqual("FF".trim(prefix: "0x"), "FF") }

    func test_lineAndColumn_firstChar() {
        let s = "hello\nworld"
        let (line, col) = s.startIndex.lineAndColumn(in: s)
        XCTAssertEqual(line, 1); XCTAssertEqual(col, 1)
    }

    func test_lineAndColumn_secondLine() {
        let s = "hello\nworld"
        let idx = s.index(s.startIndex, offsetBy: 6) // 'w'
        let (line, _) = idx.lineAndColumn(in: s)
        XCTAssertEqual(line, 2)
    }

    func test_string_lineAndColumn_range() {
        let s = "ab\ncd"
        // 'c' is at index 3 (0-based), line 2, column 1.
        let start = s.index(s.startIndex, offsetBy: 3)
        let end   = s.index(s.startIndex, offsetBy: 4)
        let (sl, sc, el, ec) = s.lineAndColumn(for: start ..< end)
        XCTAssertEqual(sl, 2); XCTAssertEqual(sc, 1)
        XCTAssertEqual(el, 2); XCTAssertEqual(ec, 2)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Full BNF grammar end-to-end
// ─────────────────────────────────────────────────────────────────────────────

final class FullGrammarTests: XCTestCase {

    func test_multipleRules() {
        let source = """
        rule A ::= "a" ;
        rule B ::= "b" ;
        """
        XCTAssertEqual(types(bnf(source)), [
            .identifier("rule"), .identifier("A"), .symbol("::="), .literal("a"), .symbol(";"),
            .identifier("rule"), .identifier("B"), .symbol("::="), .literal("b"), .symbol(";")
        ])
    }

    func test_optionalGroup() {
        XCTAssertEqual(types(bnf("rule opt ::= [ \"x\" ] ;")), [
            .identifier("rule"), .identifier("opt"), .symbol("::="),
            .symbol("["), .literal("x"), .symbol("]"),
            .symbol(";")
        ])
    }

    func test_repetitionGroup() {
        XCTAssertEqual(types(bnf("rule rep ::= { item } ;")), [
            .identifier("rule"), .identifier("rep"), .symbol("::="),
            .symbol("{"), .identifier("item"), .symbol("}"),
            .symbol(";")
        ])
    }

    func test_hyphenatedRuleName() {
        XCTAssertEqual(types(bnf("non-terminal ::= terminal ;")), [
            .identifier("non-terminal"), .symbol("::="),
            .identifier("terminal"), .symbol(";")
        ])
    }

    func test_angleBacketRule() {
        XCTAssertEqual(types(bnf("<expr> ::= <term> | <expr>")), [
            .symbol("<"), .identifier("expr"), .symbol(">"), .symbol("::="),
            .symbol("<"), .identifier("term"), .symbol(">"), .symbol("|"),
            .symbol("<"), .identifier("expr"), .symbol(">")
        ])
    }

    func test_blockCommentBetweenRules() {
        let source = "rule A ::= \"a\" ;\n(* separator *)\nrule B ::= \"b\" ;"
        let t = bnf(source)
        // 5 tokens for A, 1 comment, 5 tokens for B
        XCTAssertEqual(t.count, 11)
        if case .comment(_) = t[5].type { } else { XCTFail("Token 5 should be comment") }
    }

    func test_regexInRule() {
        let source = "DIGIT /[0-9]+/ ;"
        let t = bnf(source)
        XCTAssertEqual(t.count, 3)
        XCTAssertEqual(t[0].type, .identifier("DIGIT"))
        if case .regex(let pat) = t[1].type { XCTAssertEqual(pat, "[0-9]+") }
        else { XCTFail() }
        XCTAssertEqual(t[2].type, .symbol(";"))
    }

    func test_numberLiteralInRule() {
        XCTAssertEqual(types(bnf("limit ::= 42 ;")), [
            .identifier("limit"), .symbol("::="), .number(.decimal(42)), .symbol(";")
        ])
    }

    func test_lineCommentedRule() {
        let source = "// Define start\nstart ::= expr ;"
        let t = bnf(source)
        XCTAssertEqual(t.count, 5)
        if case .comment(_) = t[0].type { } else { XCTFail() }
        XCTAssertEqual(t[1].type, .identifier("start"))
    }

    func test_parserInput_drivingBnfGrammar() {
        // Simulate a minimal recursive-descent BNF parser step.
        // rule: "rule" identifier "::=" rhs ";"
        let source = "rule greeting ::= \"hello\" ;"
        let scanner = GrammarTokenizer(source, extraKeywords: ["rule"])
        var input   = ParserInput(scanner, source: source)

        XCTAssertTrue(input.match(.keyword("rule")))

        let name = input.consume()
        XCTAssertEqual(name?.type, .identifier("greeting"))

        XCTAssertTrue(input.match(.symbol("::=")))

        let rhs = input.consume()
        XCTAssertEqual(rhs?.type, .literal("hello"))

        XCTAssertTrue(input.match(.symbol(";")))
        XCTAssertTrue(input.isEmpty)
    }
}
