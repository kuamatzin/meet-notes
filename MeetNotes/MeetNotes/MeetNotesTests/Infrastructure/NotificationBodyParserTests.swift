import Testing
@testable import MeetNotes

@MainActor
struct NotificationBodyParserTests {
    // MARK: - extractNotificationBody

    @Test func extractsFirstDecisionAndActionItem() {
        let markdown = """
        ## Decisions
        - Approved the Q3 budget
        - Delayed the launch by two weeks

        ## Action Items
        - Alice to send the final report by Friday
        - Bob to update the roadmap

        ## Key Topics
        - Q3 planning and budget review
        """

        let (decision, action) = NotificationService.extractNotificationBody(from: markdown)
        #expect(decision == "Approved the Q3 budget")
        #expect(action == "Alice to send the final report by Friday")
    }

    @Test func returnsNilForEmptySections() {
        let markdown = """
        ## Decisions

        ## Action Items

        ## Key Topics
        - General discussion
        """

        let (decision, action) = NotificationService.extractNotificationBody(from: markdown)
        #expect(decision == nil)
        #expect(action == nil)
    }

    @Test func handlesNoDecisionsRecordedPlaceholder() {
        let markdown = """
        ## Decisions
        - No decisions recorded.

        ## Action Items
        - No action items identified.

        ## Key Topics
        - Discussed project timeline
        """

        let (decision, action) = NotificationService.extractNotificationBody(from: markdown)
        #expect(decision == "No decisions recorded.")
        #expect(action == "No action items identified.")
    }

    @Test func handlesMissingSections() {
        let markdown = """
        ## Key Topics
        - Just a discussion with no decisions or action items
        """

        let (decision, action) = NotificationService.extractNotificationBody(from: markdown)
        #expect(decision == nil)
        #expect(action == nil)
    }

    @Test func handlesEmptyString() {
        let (decision, action) = NotificationService.extractNotificationBody(from: "")
        #expect(decision == nil)
        #expect(action == nil)
    }

    // MARK: - formatBody

    @Test func formatBodyWithBothFields() {
        let body = NotificationService.formatBody(firstDecision: "Budget approved", firstAction: "Alice sends report")
        #expect(body == "Decision: Budget approved\nAction: Alice sends report")
    }

    @Test func formatBodyWithDecisionOnly() {
        let body = NotificationService.formatBody(firstDecision: "Budget approved", firstAction: nil)
        #expect(body == "Decision: Budget approved")
    }

    @Test func formatBodyWithActionOnly() {
        let body = NotificationService.formatBody(firstDecision: nil, firstAction: "Alice sends report")
        #expect(body == "Action: Alice sends report")
    }

    @Test func formatBodyWithNilFieldsReturnsFallback() {
        let body = NotificationService.formatBody(firstDecision: nil, firstAction: nil)
        #expect(body == "Your meeting summary is ready.")
    }

    @Test func formatBodyFiltersPlaceholderStrings() {
        let body = NotificationService.formatBody(
            firstDecision: "No decisions recorded.",
            firstAction: "No action items identified."
        )
        #expect(body == "Your meeting summary is ready.")
    }

    @Test func formatBodyTruncatesLongDecision() {
        let longDecision = String(repeating: "A", count: 200)
        let body = NotificationService.formatBody(firstDecision: longDecision, firstAction: nil)
        #expect(body.count <= 110) // "Decision: " prefix + 100 max
        #expect(body.hasSuffix("…"))
    }

    @Test func formatBodyTruncatesLongAction() {
        let longAction = String(repeating: "B", count: 200)
        let body = NotificationService.formatBody(firstDecision: nil, firstAction: longAction)
        #expect(body.count <= 108) // "Action: " prefix + 100 max
        #expect(body.hasSuffix("…"))
    }

    @Test func extractsFirstBulletWithAsterisk() {
        let markdown = """
        ## Decisions
        * Approved the Q3 budget
        * Delayed the launch

        ## Action Items
        * Alice to send the report
        """

        let (decision, action) = NotificationService.extractNotificationBody(from: markdown)
        #expect(decision == "Approved the Q3 budget")
        #expect(action == "Alice to send the report")
    }
}
