import Flutter
import UIKit
import XCTest
@testable import Runner

@available(iOS 16.1, *)
class RunnerTests: XCTestCase {
    func testParseLessonsUsesStartOfProvidedDay() throws {
        let now = Date(timeIntervalSince1970: 1_752_200_000)
        let base = Calendar.current.startOfDay(for: now)
        let lessons = try LiveActivityPlugin.parseLessons([
            "lessons": [[
                "subject": "数学",
                "room": "A101",
                "teacher": "李老师",
                "startMs": 28_800_000,
                "endMs": 31_500_000,
            ]],
        ], now: now)

        XCTAssertEqual(lessons.count, 1)
        XCTAssertEqual(lessons[0].subject, "数学")
        XCTAssertEqual(lessons[0].start, base.addingTimeInterval(28_800))
        XCTAssertEqual(lessons[0].end, base.addingTimeInterval(31_500))
    }

    func testParseDirectState() throws {
        let state = try LiveActivityPlugin.parseState([
            "subject": " 数学 ",
            "room": " A101 ",
            "teacher": "李老师",
            "phase": "上课中",
            "statusLabel": "距下课",
            "countdownStartEpochMs": 1_752_200_000_000,
            "countdownEndEpochMs": 1_752_202_700_000,
        ])

        XCTAssertEqual(state.subject, "数学")
        XCTAssertEqual(state.room, "A101")
        XCTAssertEqual(state.countdownStart.timeIntervalSince1970, 1_752_200_000, accuracy: 0.001)
        XCTAssertEqual(state.countdownEnd.timeIntervalSince1970, 1_752_202_700, accuracy: 0.001)
    }

    func testParseStateRejectsMissingRequiredString() {
        XCTAssertThrowsError(try LiveActivityPlugin.parseState([
            "subject": "",
            "room": "A101",
            "teacher": "李老师",
            "phase": "上课中",
            "statusLabel": "距下课",
            "countdownStartEpochMs": 1_000,
            "countdownEndEpochMs": 2_000,
        ]))
    }

    func testParseStateRejectsInvalidInterval() {
        XCTAssertThrowsError(try LiveActivityPlugin.parseState([
            "subject": "数学",
            "room": "A101",
            "teacher": "李老师",
            "phase": "上课中",
            "statusLabel": "距下课",
            "countdownStartEpochMs": 2_000,
            "countdownEndEpochMs": 1_000,
        ]))
    }
}
