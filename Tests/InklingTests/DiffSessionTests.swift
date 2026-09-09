import Testing
@testable import Inkling

@Suite("Diff navigation")
@MainActor
struct DiffSessionTests {
    @Test("next and previous recenter on distinct hunks")
    func hunkNavigation() {
        let session = DiffSession()
        session.result = DiffResult(
            leftHighlights: [],
            rightHighlights: [],
            hunks: [
                DiffHunk(
                    id: 0,
                    leftRange: 1..<2,
                    rightRange: 1..<2,
                    leftNavigationOffset: 10,
                    rightNavigationOffset: 12
                ),
                DiffHunk(
                    id: 1,
                    leftRange: 8..<9,
                    rightRange: 9..<10,
                    leftNavigationOffset: 80,
                    rightNavigationOffset: 90
                ),
            ]
        )

        session.nextHunk()
        #expect(session.currentHunkIndex == 0)
        #expect(session.leftNavigationOffset == 10)
        #expect(session.rightNavigationOffset == 12)
        let firstRevision = session.navigationRevision

        session.nextHunk()
        #expect(session.currentHunkIndex == 1)
        #expect(session.leftNavigationOffset == 80)
        #expect(session.rightNavigationOffset == 90)
        #expect(session.navigationRevision == firstRevision + 1)

        session.previousHunk()
        #expect(session.currentHunkIndex == 0)
    }
}
