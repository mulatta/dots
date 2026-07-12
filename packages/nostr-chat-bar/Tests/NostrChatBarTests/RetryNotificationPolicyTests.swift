import XCTest

@testable import NostrChatBar

final class RetryNotificationPolicyTests: XCTestCase {
    func testNotifiesOnFirstFailureOfAnEpisode() {
        XCTAssertTrue(
            RetryNotificationPolicy.shouldNotify(
                previousTries: 0, newTries: 1, alreadyNotified: false))
    }

    func testStaysSilentDuringBackoff() {
        XCTAssertFalse(
            RetryNotificationPolicy.shouldNotify(
                previousTries: 1, newTries: 2, alreadyNotified: true))
        XCTAssertFalse(
            RetryNotificationPolicy.shouldNotify(
                previousTries: 3, newTries: 4, alreadyNotified: true))
    }

    func testStaysSilentWhenAlreadyNotified() {
        // Reconnect replays can reset the mirrored tries to 0 while the
        // banner for this episode already fired.
        XCTAssertFalse(
            RetryNotificationPolicy.shouldNotify(
                previousTries: 0, newTries: 1, alreadyNotified: true))
    }

    func testIgnoresNonFailureTransitions() {
        XCTAssertFalse(
            RetryNotificationPolicy.shouldNotify(
                previousTries: 0, newTries: 0, alreadyNotified: false))
    }
}
