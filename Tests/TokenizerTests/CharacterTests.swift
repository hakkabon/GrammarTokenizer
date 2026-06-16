import Testing
@testable import Tokenizer

@Test
func testCharIdentifier() async throws {
    let symbols: [String] = []
    let keywords: [String] = []
    let input = "abc"
    let tokenizer = RegexTokenizer(input, symbols: Set(symbols), keywords: Set(keywords), lexeme: .char)
    let tokens = tokenizer.tokenize()
    #expect(tokens == [
        Token(type: .char("a"), range: input.startIndex ..< input.index(after: input.startIndex)),
        Token(type: .char("b"), range: input.index(after: input.startIndex) ..< input.index(input.startIndex, offsetBy: 2)),
        Token(type: .char("c"), range: input.index(input.startIndex, offsetBy: 2) ..< input.endIndex)
    ])
}

@Test
func testPeek() async throws {
    let symbols = ["|", "\\", "^", ":", ",", "$", ".", "\"", "¶", ">", "#", "-", "{","[", "<", "(",
                   "(?:", "(?|", "[:", "+", "+?", "'", "}", "]", ":]", ")", ";", "/", "*", "*?", "?", "??"]
    
    let keywords = ["alnum", "alpha", "ascii", "blank", "cntrl", "digit",
                    "graph", "lower", "print", "punct", "space", "upper", "word", "xdigit"]
    let input = "[a-z]"
    let tokenizer = RegexTokenizer(input, symbols: Set(symbols), keywords: Set(keywords), lexeme: .char)
    if tokenizer.peek(ahead: 1)?.type == .symbol("[") {
        tokenizer.consume()
    }
    if tokenizer.peek(ahead: 1)?.type == .symbol("a") {
        tokenizer.consume()
    }
    if tokenizer.peek(ahead: 1)?.type == .symbol("-") {
        tokenizer.consume()
    }
    if tokenizer.peek(ahead: 1)?.type == .symbol("z") {
        tokenizer.consume()
    }
    if tokenizer.peek(ahead: 1)?.type == .symbol("]") {
        tokenizer.consume()
    }
    #expect(tokenizer.isEmpty == true)
}

@Test
func testMatchMix() async throws {
    let symbols = ["|", "\\", "^", ":", ",", "$", ".", "\"", "¶", ">", "#", "-", "{","[", "<", "(",
                   "(?:", "(?|", "[:", "+", "+?", "'", "}", "]", ":]", ")", ";", "/", "*", "*?", "?", "??"]
    let keywords = ["alnum", "alpha", "ascii", "blank", "cntrl", "digit",
                    "graph", "lower", "print", "punct", "space", "upper", "word", "xdigit"]
    let input = "[a-z]"
    let tokenizer = RegexTokenizer(input, symbols: Set(symbols), keywords: Set(keywords), lexeme: .char)

    if tokenizer.peek(ahead: 1)?.type == .symbol("[") { tokenizer.consume() }
    if case .identifier(let identifier) = tokenizer.next()?.type { #expect(identifier == "a") }
    if tokenizer.peek(ahead: 1)?.type == .symbol("-") { tokenizer.consume() }
    if case .identifier(let identifier) = tokenizer.next()?.type { #expect(identifier == "z") }
    if case .symbol(let symbol) = tokenizer.next()?.type { #expect(symbol == "]") }
    #expect(tokenizer.isEmpty == true)
}

@Test
func testRegexp() async throws {
    let symbols = ["|", "\\", "^", ":", ",", "$", ".", "\"", "¶", ">", "#", "-", "{","[", "<", "(",
                   "(?:", "(?|", "[:", "+", "+?", "'", "}", "]", ":]", ")", ";", "/", "*", "*?", "?", "??"]
    let keywords = ["alnum", "alpha", "ascii", "blank", "cntrl", "digit", "graph", "lower", "print",
                    "punct", "space", "upper", "word", "xdigit"]
    let input = "[a-z]"
    let tokens = RegexTokenizer(input, symbols: Set(symbols), keywords: Set(keywords), lexeme: .char).tokenize()
    #expect(tokens == [
        Token(type: .symbol("["),   range: input.index(input.startIndex, offsetBy: 0) ..< input.index(input.startIndex, offsetBy: 1)),
        Token(type: .char("a"),     range: input.index(input.startIndex, offsetBy: 1) ..< input.index(input.startIndex, offsetBy: 2)),
        Token(type: .symbol("-"),   range: input.index(input.startIndex, offsetBy: 2) ..< input.index(input.startIndex, offsetBy: 3)),
        Token(type: .char("z"),     range: input.index(input.startIndex, offsetBy: 3) ..< input.index(input.startIndex, offsetBy: 4)),
        Token(type: .symbol("]"),   range: input.index(input.startIndex, offsetBy: 4) ..< input.endIndex),
    ])
}
