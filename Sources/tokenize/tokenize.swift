import Foundation
import ArgumentParser
import Tokenizer

@main
struct Tokenize: ParsableCommand {

    // Source input is either a command line argument or a file
    // containing the input to be tokenized.
    enum Source {
        case arg(String)
        case url(URL)
        
        init(_ string: String) {
            if string.isEmpty {
                self = .arg(string)
            } else if FileManager.default.fileExists(atPath: string) {
                self = .url(URL(fileURLWithPath: string))
            } else {
                self = .arg(string)
            }
        }
    }
    
    @Option(name: [.short, .long], help: "Input to be tokenized.", transform: Source.init)
    var input: Source = Source("")
    
    @Option(name: [.short, .long], help: "strings tokenized as symbols")
    var symbols: String = ""
    
    @Option(name: [.short, .long], parsing: .upToNextOption, help: "strings tokenized as keywords")
    var keywords: [String] = []
    
    mutating func run() throws {
        switch input {
        case .arg(let input):
            let tokens = GrammarTokenizer(input).tokenize()

            for token in tokens {
                let location = token.location(in: input)
                print("\(token.type) location: (\(location.start),\(location.end))")
            }

        case .url(let url):
            let source = try String(contentsOf: url)
            let tokens = GrammarTokenizer(source).tokenize()

            for token in tokens {
                let location = token.location(in: source)
                print("\(token.type) location: (\(location.start),\(location.end))")
            }
        }
    }
}
