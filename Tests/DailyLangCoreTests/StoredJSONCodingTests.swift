import Testing
@testable import DailyLangCore

@Suite("Stored JSON coding")
struct StoredJSONCodingTests {
    @Test("valid stored JSON decodes with value")
    func validJSONDecodes() throws {
        let encoded = try StoredJSONCoding.encode([
            VocabularyItem(id: "kopi", jp: "コーヒー"),
        ])

        let state = StoredJSONCoding.decodeState([VocabularyItem].self, from: encoded)

        #expect(state.value == [.init(id: "kopi", jp: "コーヒー")])
        #expect(!state.isUnreadable)
    }

    @Test("broken stored JSON is reported as unreadable")
    func brokenJSONIsUnreadable() {
        let state = StoredJSONCoding.decodeState([VocabularyItem].self, from: "{")

        #expect(state.value == nil)
        #expect(state.isUnreadable)
    }

    @Test("legacy image keywords without counts still decode")
    func legacyImageKeywordsDecodeWithDefaultCount() {
        let state = StoredJSONCoding.decodeState(
            [ImageKeyword].self,
            from: #"[{"label":"banana","confidence":0.91}]"#
        )

        #expect(state.value == [ImageKeyword(label: "banana", confidence: 0.91, count: 1)])
        #expect(!state.isUnreadable)
    }
}
