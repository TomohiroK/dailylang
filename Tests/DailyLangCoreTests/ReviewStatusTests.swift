import Testing
@testable import DailyLangCore

@Suite("Review status")
struct ReviewStatusTests {
    @Test("all statuses are persisted display states")
    func statusesRemainDisplayStates() {
        #expect(ReviewStatus.new.title == "未復習")
        #expect(ReviewStatus.again.title == "もう一度")
        #expect(ReviewStatus.remembered.title == "覚えた")
    }

    @Test("persisted raw values restore expected statuses")
    func rawValuesRestoreStatuses() {
        #expect(ReviewStatus(rawValue: "new") == .new)
        #expect(ReviewStatus(rawValue: "again") == .again)
        #expect(ReviewStatus(rawValue: "remembered") == .remembered)
        #expect(ReviewStatus(rawValue: "unknown") == nil)
    }
}
