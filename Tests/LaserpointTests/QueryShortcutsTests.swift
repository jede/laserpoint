import XCTest
@testable import Laserpoint

final class QueryShortcutsTests: XCTestCase {
    private let defs = ShortcutDefinition.defaults + [
        ShortcutDefinition(key: "g", name: "GitHub", systemImage: "link",
                           action: .urlTemplate("https://github.com/search?q={query}"))
    ]

    private func result(_ query: String) -> QueryShortcut? {
        QueryShortcuts.result(for: query, definitions: defs)
    }

    func testWebSearchBuildsGoogleQuery() {
        let shortcut = result("w swift docs")
        XCTAssertEqual(shortcut?.url.absoluteString, "https://www.google.com/search?q=swift%20docs")
    }

    func testWebOpensDirectURLWhenArgumentLooksLikeOne() {
        XCTAssertEqual(result("w github.com")?.url.absoluteString, "https://github.com")
        XCTAssertEqual(result("w https://apple.com/x")?.url.absoluteString, "https://apple.com/x")
    }

    func testClaudeUsesDeepLink() {
        XCTAssertEqual(result("c write a haiku")?.url.absoluteString,
                       "claude://claude.ai/new?q=write%20a%20haiku")
    }

    func testCustomTemplateSubstitutesQuery() {
        XCTAssertEqual(result("g laserpoint")?.url.absoluteString,
                       "https://github.com/search?q=laserpoint")
    }

    func testUnknownKeyReturnsNil() {
        XCTAssertNil(result("x foo"))
    }

    func testMissingArgumentReturnsNil() {
        XCTAssertNil(result("w"))
        XCTAssertNil(result("w "))
        XCTAssertNil(result("c   "))
    }

    func testKeyMatchingIsCaseInsensitive() {
        XCTAssertNotNil(result("W something"))
    }

    func testEmptyKeyDefinitionNeverMatches() {
        let blank = [ShortcutDefinition(key: "", name: "Blank", systemImage: "link",
                                        action: .urlTemplate("https://x/?q={query}"))]
        XCTAssertNil(QueryShortcuts.result(for: "hello world", definitions: blank))
    }
}
