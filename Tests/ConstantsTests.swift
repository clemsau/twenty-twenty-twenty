import Testing
@testable import Twenty_twenty_twenty

@Suite("Constants")
struct ConstantsTests {
    @Test("Reminder interval is exactly twenty minutes")
    func interval() {
        #expect(Twenty.interval == 1200)
    }

    @Test("Notifications are removed ten seconds after posting")
    func removalDelay() {
        #expect(Twenty.notificationRemovalDelay == 10)
    }
}
