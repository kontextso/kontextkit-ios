import Testing
@testable import KontextKit

struct JSONParsingTests {

    @Test func parsesValidJSON() {
        let dict = JSONParsing.parse("{\"key\": \"value\"}")
        #expect(dict?["key"] as? String == "value")
    }

    @Test func parsesNestedJSON() {
        let dict = JSONParsing.parse("{\"outer\": {\"inner\": 42}}")
        let outer = dict?["outer"] as? [String: Any]
        #expect(outer?["inner"] as? Int == 42)
    }

    @Test func returnsNilForInvalidJSON() {
        #expect(JSONParsing.parse("not json") == nil)
    }

    @Test func returnsNilForEmptyString() {
        #expect(JSONParsing.parse("") == nil)
    }

    @Test func returnsNilForArrayJSON() {
        // parse expects a dictionary, not an array
        #expect(JSONParsing.parse("[1, 2, 3]") == nil)
    }

    @Test func parsesJSONWithSpecialCharacters() {
        let dict = JSONParsing.parse("{\"emoji\": \"🎯\", \"url\": \"https://example.com\"}")
        #expect(dict?["emoji"] as? String == "🎯")
        #expect(dict?["url"] as? String == "https://example.com")
    }
}
