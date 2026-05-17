import Testing
@testable import Tokenizer

@Test
func testRegexRecognition() async throws {
    let input = """
        float   ::= /[0-9]+\\.[0-9]+/ ;
        integer ::= /[0-9]+/ ;
        range   ::= integer ".." integer ;
    """
    let symbols = ["<", ">", ":", "=", ":=", "::=", "|", "{", "[", "(", "}", "]", ")"]
    let keywords: [String] = []
    let tokenizer = Tokenizer(input, symbols: Set(symbols), keywords: Set(keywords))
    let tokens = tokenizer.tokenize()

    #expect(tokenizer.isEmpty == true)
    let tokenTypes = Set<TokenType>(tokens.map { $0.type })
    let expectedTokenTypes = Set<TokenType>([
        .identifier("float"), .symbol("::="), .regex("[0-9]+\\.[0-9]+"), .symbol(";"),
        .identifier("integer"), .symbol("::="), .regex("[0-9]+"), .symbol(";"),
        .identifier("range"), .symbol("::="), .identifier("integer"), .literal(".."), .identifier("integer"), .symbol(";")
    ])
    #expect(tokenTypes == expectedTokenTypes)
}

@Test
func testRegexAndCommentRecognition() async throws {
    let input = """
        // this is a comment
        integer ::= /[0-9]+/ ;
    """
    let symbols = ["<", ">", ":", "=", ":=", "::=", "|", "{", "[", "(", "}", "]", ")"]
    let keywords: [String] = []
    let tokenizer = Tokenizer(input, symbols: Set(symbols), keywords: Set(keywords))
    let tokens = tokenizer.tokenize()
    
    #expect(tokenizer.isEmpty == true)
    let tokenTypes = Set<TokenType>(tokens.map { $0.type })
    let expectedTokenTypes = Set<TokenType>([
        .comment(" this is a comment"),
        .identifier("integer"), .symbol("::="), .regex("[0-9]+"), .symbol(";")
    ])
    #expect(tokenTypes == expectedTokenTypes)
}
