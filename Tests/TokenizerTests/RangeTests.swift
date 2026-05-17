import Testing
@testable import Tokenizer

@Test
func testRangeRecognition() async throws {
    let input = """
        r1 ::= "a".."z" ;
        r2 ::= "A".."Z" ;
        r3 ::= "a".. "z" ;
        r4 ::= "a" .."z" ;
        r5 ::= "a" .. "z" ;
    """
    let symbols = ["<", ">", ":", "=", ":=", "::=", "|", "{", "[", "(", "}", "]", ")", ".."]
    let keywords: [String] = []
    let tokenizer = Tokenizer(input, symbols: Set(symbols), keywords: Set(keywords))
    let tokens = tokenizer.tokenize()

    #expect(tokenizer.isEmpty == true)
    print(tokens.map { $0.type })
//    let tokenTypes = Set<TokenType>(tokens.map { $0.type })
//    let expectedTokenTypes = Set<TokenType>([
//        .identifier("float"), .symbol("::="), .regex("[0-9]+\\.[0-9]+"), .symbol(";"),
//        .identifier("integer"), .symbol("::="), .regex("[0-9]+"), .symbol(";"),
//        .identifier("range"), .symbol("::="), .identifier("integer"), .literal(".."), .identifier("integer"), .symbol(";")
//    ])
//    #expect(tokenTypes == expectedTokenTypes)
}

@Test
func testRangeUnicode() async throws {
    let input = """
        r1 ::= '\u{0400}' .. '\u{04FF}' ;
        r2 ::= "\u{0400}" .. "\u{04FF}" ;
    """
    let symbols = ["<", ">", ":", "=", ":=", "::=", "|", "{", "[", "(", "}", "]", ")", ".."]
    let keywords: [String] = []
    let tokenizer = Tokenizer(input, symbols: Set(symbols), keywords: Set(keywords))
    let tokens = tokenizer.tokenize()
    
    #expect(tokenizer.isEmpty == true)
    print(tokens.map { $0.type })
//    let tokenTypes = Set<TokenType>(tokens.map { $0.type })
//    let expectedTokenTypes = Set<TokenType>([
//        .comment(" this is a comment"),
//        .identifier("integer"), .symbol("::="), .regex("[0-9]+"), .symbol(";")
//    ])
//    #expect(tokenTypes == expectedTokenTypes)
}

@Test
func testListUnicode() async throws {
    let input = """
        r1 ::= '\u{1F600}' | '\u{1F602}' ;
    """
    let symbols = ["<", ">", ":", "=", ":=", "::=", "|", "{", "[", "(", "}", "]", ")", ".."]
    let keywords: [String] = []
    let tokenizer = Tokenizer(input, symbols: Set(symbols), keywords: Set(keywords))
    let tokens = tokenizer.tokenize()
    
    #expect(tokenizer.isEmpty == true)
    print(tokens.map { $0.type })
//    let tokenTypes = Set<TokenType>(tokens.map { $0.type })
//    let expectedTokenTypes = Set<TokenType>([
//        .comment(" this is a comment"),
//        .identifier("integer"), .symbol("::="), .regex("[0-9]+"), .symbol(";")
//    ])
//    #expect(tokenTypes == expectedTokenTypes)
}
