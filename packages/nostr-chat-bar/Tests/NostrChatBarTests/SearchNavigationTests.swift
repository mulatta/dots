import Cocoa
import XCTest

@testable import NostrChatBar

final class SearchNavigationTests: XCTestCase {
    func testReturnUsesShiftToChooseDirection() {
        let newline = #selector(NSResponder.insertNewline(_:))
        XCTAssertEqual(SearchNavigation.direction(for: newline, shift: false), 1)
        XCTAssertEqual(SearchNavigation.direction(for: newline, shift: true), -1)
    }

    func testArrowKeysChooseDirection() {
        XCTAssertEqual(
            SearchNavigation.direction(for: #selector(NSResponder.moveDown(_:)), shift: false),
            1)
        XCTAssertEqual(
            SearchNavigation.direction(for: #selector(NSResponder.moveUp(_:)), shift: false),
            -1)
    }

    func testOtherCommandsAreIgnored() {
        XCTAssertNil(
            SearchNavigation.direction(
                for: #selector(NSResponder.insertTab(_:)), shift: false))
    }
}
