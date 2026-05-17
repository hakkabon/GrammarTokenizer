import Testing
@testable import Tokenizer

@Test
func testIterator() async throws {
    let symbols: [String] = []
    let keywords: [String] = []
    let input = "abc"
    let tokenizer = Tokenizer(input, symbols: Set(symbols), keywords: Set(keywords))
    while let token = tokenizer.next() {
        switch token.type {
        case .identifier(_): break
        default: break
        }
    }
    #expect(tokenizer.isEmpty == true)
}

@Test
func testStringIdentifier() async throws {
    let symbols: [String] = []
    let keywords: [String] = []
    let input = "abc"
    let tokenizer = Tokenizer(input, symbols: Set(symbols), keywords: Set(keywords))
    let tokens = tokenizer.tokenize()
    #expect(tokens == [Token(type: .identifier("abc"), range: input.startIndex ..< input.endIndex)])
}
/*
@Test
func testMaximumMunch() async throws {
    let symbols = ["|", "\\", "^", ":", ",", "$", ".", "\"", "¶", ">", "#", "-", "{","[", "<", "(",
                   "(?:", "(?|", "[:", "+", "+?", "'", "}", "]", ":]", ")", ";", "/", "*", "*?", "?", "??"]
    let keywords = ["alnum", "alpha", "ascii", "blank", "cntrl", "digit",
                    "graph", "lower", "print", "punct", "space", "upper", "word", "xdigit"]
    let input = "((?:(?|ab??*?+?"
    let tokenizer = Tokenizer(input, symbols: Set(symbols), keywords: Set(keywords))
    
    if tokenizer.peek(ahead: 1)?.type == .symbol("(") { tokenizer.consume() }
    if case .symbol(let symbol) = tokenizer.next()?.type { #expect(symbol == "(?:") }
    if case .symbol(let symbol) = tokenizer.next()?.type { #expect(symbol == "(?|") }
    if tokenizer.peek(ahead: 1)?.type == .identifier("ab") { tokenizer.consume() }
    if case .symbol(let symbol) = tokenizer.next()?.type { #expect(symbol == "??") }
    if case .symbol(let symbol) = tokenizer.next()?.type { #expect(symbol == "*?") }
    if case .symbol(let symbol) = tokenizer.next()?.type { #expect(symbol == "+?") }
    #expect(tokenizer.isEmpty == true)
}
*/
@Test
func testTokens() async throws {
    let symbols = ["|", "\\", "^", ":", "=", "*", "+"]
    let keywords = ["alnum", "alpha", "ascii", "blank", "cntrl" ]
    let input =  "5 + 23 * 3 = 74"
    let tokenizer = Tokenizer(input, symbols: Set(symbols), keywords: Set(keywords))
    
    if case .number(let decimal) = tokenizer.next()?.type { #expect(decimal == .decimal(5)) }
    if case .symbol(let symbol) = tokenizer.next()?.type { #expect(symbol == "+") }
    if case .number(let decimal) = tokenizer.next()?.type { #expect(decimal == .decimal(23)) }
    if case .symbol(let symbol) = tokenizer.next()?.type { #expect(symbol == "*") }
    if case .number(let decimal) = tokenizer.next()?.type { #expect(decimal == .decimal(3)) }
    if case .symbol(let symbol) = tokenizer.next()?.type { #expect(symbol == "=") }
    if case .number(let decimal) = tokenizer.next()?.type { #expect(decimal == .decimal(74)) }
}

@Test
func testBNF() async throws {
    let symbols = ["<", ">", ":", "=", ":=", "::=", "|", "{", "[", "(", "}", "]", ")"]
    let keywords: [String] = []
    let input = """
        <expr> ::= <term>|<expr><addop><term>
    """
    let tokens = Tokenizer(input, symbols: Set(symbols), keywords: Set(keywords)).tokenize()
    #expect(tokens == [
    Token(type: .symbol("<"),           range: input.index(input.startIndex, offsetBy: 4) ..< input.index(input.startIndex, offsetBy: 5)),
    Token(type: .identifier("expr"),    range: input.index(input.startIndex, offsetBy: 5) ..< input.index(input.startIndex, offsetBy: 9)),
    Token(type: .symbol(">"),           range: input.index(input.startIndex, offsetBy: 9) ..< input.index(input.startIndex, offsetBy: 10)),
    Token(type: .symbol("::="),     	range: input.index(input.startIndex, offsetBy: 11) ..< input.index(input.startIndex, offsetBy: 14)),
    Token(type: .symbol("<"),       	range: input.index(input.startIndex, offsetBy: 15) ..< input.index(input.startIndex, offsetBy: 16)),
    Token(type: .identifier("term"),    range: input.index(input.startIndex, offsetBy: 16) ..< input.index(input.startIndex, offsetBy: 20)),
    Token(type: .symbol(">"),           range: input.index(input.startIndex, offsetBy: 20) ..< input.index(input.startIndex, offsetBy: 21)),
    Token(type: .symbol("|"),           range: input.index(input.startIndex, offsetBy: 21) ..< input.index(input.startIndex, offsetBy: 22)),
    Token(type: .symbol("<"),           range: input.index(input.startIndex, offsetBy: 22) ..< input.index(input.startIndex, offsetBy: 23)),
    Token(type: .identifier("expr"),    range: input.index(input.startIndex, offsetBy: 23) ..< input.index(input.startIndex, offsetBy: 27)),
    Token(type: .symbol(">"),           range: input.index(input.startIndex, offsetBy: 27) ..< input.index(input.startIndex, offsetBy: 28)),
    Token(type: .symbol("<"),           range: input.index(input.startIndex, offsetBy: 28) ..< input.index(input.startIndex, offsetBy: 29)),
    Token(type: .identifier("addop"),   range: input.index(input.startIndex, offsetBy: 29) ..< input.index(input.startIndex, offsetBy: 34)),
    Token(type: .symbol(">"),           range: input.index(input.startIndex, offsetBy: 34) ..< input.index(input.startIndex, offsetBy: 35)),
    Token(type: .symbol("<"),           range: input.index(input.startIndex, offsetBy: 35) ..< input.index(input.startIndex, offsetBy: 36)),
    Token(type: .identifier("term"),    range: input.index(input.startIndex, offsetBy: 36) ..< input.index(input.startIndex, offsetBy: 40)),
    Token(type: .symbol(">"),           range: input.index(input.startIndex, offsetBy: 40) ..< input.endIndex)
    ])
}

@Test
func testEBNF() async throws {
    let symbols = ["<", ">", ":", "=", ":=", "::=", "|", "{", "[", "(", "}", "]", ")"]
    let keywords: [String] = []
    let input = """
        Expression  : Term { '|' Term }
        Term        : Factor { Factor }
    """
    let tokens = Tokenizer(input, symbols: Set(symbols), keywords: Set(keywords)).tokenize()
    
    for token in tokens {
        print(token)
    }
//    #expect(tokens == [
//    Token(type: .identifier("Expression"),  range: input.index(input.startIndex, offsetBy: +4) ..< input.index(input.startIndex, offsetBy: +14)),
//    Token(type: .symbol(":"),               range: input.index(input.startIndex, offsetBy: +16) ..< input.index(input.startIndex, offsetBy: +17)),
//    Token(type: .identifier("Term"),        range: input.index(input.startIndex, offsetBy: +18) ..< input.index(input.startIndex, offsetBy: +22)),
//    Token(type: .symbol("{"),               range: input.index(input.startIndex, offsetBy: +23) ..< input.index(input.startIndex, offsetBy: +24)),
//    Token(type: .literal("|"),              range: input.index(input.startIndex, offsetBy: +26) ..< input.index(input.startIndex, offsetBy: +27)),
//    Token(type: .identifier("Term"),        range: input.index(input.startIndex, offsetBy: +29) ..< input.index(input.startIndex, offsetBy: +33)),
//    Token(type: .symbol("}"),               range: input.index(input.startIndex, offsetBy: +34) ..< input.index(input.startIndex, offsetBy: +35)),
//    Token(type: .identifier("Term"),        range: input.index(input.startIndex, offsetBy: +40) ..< input.index(input.startIndex, offsetBy: +44)),
//    Token(type: .symbol(":"),               range: input.index(input.startIndex, offsetBy: +52) ..< input.index(input.startIndex, offsetBy: +53)),
//    Token(type: .identifier("Factor"),      range: input.index(input.startIndex, offsetBy: +54) ..< input.index(input.startIndex, offsetBy: +60)),
//    Token(type: .symbol("{"),               range: input.index(input.startIndex, offsetBy: +61) ..< input.index(input.startIndex, offsetBy: +62)),
//    Token(type: .identifier("Factor"),      range: input.index(input.startIndex, offsetBy: +63) ..< input.index(input.startIndex, offsetBy: +69)),
//    Token(type: .symbol("}"),               range: input.index(input.startIndex, offsetBy: +70) ..< input.index(input.startIndex, offsetBy: +71)),
//    ])
}

