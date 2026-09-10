import Foundation
import Testing
@testable import Inkling

@Suite("Diff navigation")
@MainActor
struct DiffSessionTests {
    @Test("next and previous recenter on semantic changes")
    func changeNavigation() {
        let session = DiffSession()
        session.result = DiffResult(
            leftHighlights: [],
            rightHighlights: [],
            hunks: [
                DiffHunk(
                    id: 0,
                    leftRange: 1..<2,
                    rightRange: 1..<2,
                    leftNavigationOffset: 0,
                    rightNavigationOffset: 0
                ),
            ],
            changes: [
                DiffChange(
                    id: 0,
                    hunkID: 0,
                    leftRange: NSRange(location: 10, length: 5),
                    rightRange: NSRange(location: 12, length: 4),
                    leftNavigationOffset: 10,
                    rightNavigationOffset: 12
                ),
                DiffChange(
                    id: 1,
                    hunkID: 0,
                    leftRange: NSRange(location: 80, length: 5),
                    rightRange: NSRange(location: 90, length: 5),
                    leftNavigationOffset: 80,
                    rightNavigationOffset: 90
                ),
            ]
        )

        session.nextChange()
        #expect(session.currentChangeIndex == 0)
        #expect(session.leftNavigationOffset == 10)
        #expect(session.rightNavigationOffset == 12)
        let firstRevision = session.navigationRevision

        session.nextChange()
        #expect(session.currentChangeIndex == 1)
        #expect(session.leftNavigationOffset == 80)
        #expect(session.rightNavigationOffset == 90)
        #expect(session.navigationRevision == firstRevision + 1)
        #expect(session.currentHunk?.id == 0)

        session.previousChange()
        #expect(session.currentChangeIndex == 0)
    }
}
