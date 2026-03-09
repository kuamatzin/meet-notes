import Testing
@testable import MeetNotes

@MainActor
struct SummaryMarkdownParserTests {

    @Test func parsesThreeSectionsFromValidMarkdown() {
        let markdown = """
            ## Decisions
            - Approved the budget for Q3
            - Chose vendor A over vendor B

            ## Action Items
            - Alice: send the report by Friday
            - Bob to review the contract

            ## Key Topics
            - Q3 planning
            - Budget review
            """

        let sections = SummaryMarkdownParser.parse(markdown)
        #expect(sections.count == 3)
        #expect(sections[0].title == "Decisions")
        #expect(sections[0].items.count == 2)
        #expect(sections[1].title == "Action Items")
        #expect(sections[1].items.count == 2)
        #expect(sections[1].isActionItems == true)
        #expect(sections[2].title == "Key Topics")
        #expect(sections[2].items.count == 2)
    }

    @Test func parsesEmptyMarkdownReturnsNoSections() {
        let sections = SummaryMarkdownParser.parse("")
        #expect(sections.isEmpty)
    }

    @Test func parsesPartialStreamingMarkdown() {
        let partial = """
            ## Decisions
            - First decision
            ## Action Items
            """
        let sections = SummaryMarkdownParser.parse(partial)
        #expect(sections.count == 2)
        #expect(sections[0].title == "Decisions")
        #expect(sections[0].items.count == 1)
        #expect(sections[1].title == "Action Items")
        #expect(sections[1].items.isEmpty)
    }

    @Test func sectionIdentifiesActionItemsCorrectly() {
        let markdown = """
            ## Action Items
            - Alice: send report
            """
        let sections = SummaryMarkdownParser.parse(markdown)
        #expect(sections[0].isActionItems == true)
    }

    @Test func nonActionItemSectionsAreNotActionItems() {
        let markdown = """
            ## Decisions
            - Approved budget
            """
        let sections = SummaryMarkdownParser.parse(markdown)
        #expect(sections[0].isActionItems == false)
    }
}
