import Foundation
import Testing

@testable import FlickrKit

/// Ported from `tests/test_group_search.py`.
@Suite struct GroupResolverTests {

    @Test(arguments: [
        ("https://www.flickr.com/groups/nightphotography/", "nightphotography"),
        ("https://flickr.com/groups/nightphotography", "nightphotography"),
        ("www.flickr.com/groups/abc/pool/", "abc"),
        ("nightphotography", "nightphotography"),
        ("  spaced  ", "spaced"),
        ("12345@N00", "12345@N00"),
    ])
    func parsesAGroupIdentifier(input: String, expected: String) throws {
        #expect(try GroupResolver.identifier(from: input) == expected)
    }

    @Test(arguments: ["", "   ", "https://www.flickr.com/photos/someone/",
                      "https://www.flickr.com/", "https://www.flickr.com/groups/"])
    func rejectsInputThatIsNotAGroup(input: String) {
        #expect(throws: FlickrError.self) { try GroupResolver.identifier(from: input) }
    }

    @Test func recognisesAnNSID() {
        #expect(GroupResolver.isNSID("12345@N00"))
        #expect(!GroupResolver.isNSID("nightphotography"))
    }

    @Test func buildsTheCanonicalGroupURL() {
        #expect(GroupResolver.lookupURL(for: "abc")
            == "https://www.flickr.com/groups/abc/")
    }

    /// `flickr.groups.search` is a fuzzy name search, so taking its first
    /// result silently loaded an unrelated group.
    @Test func anExactNameMatchIsChosenNotTheFirstResult() {
        let results = [
            GroupSummary(nsid: "1@N1", name: "Night Photography Addicts"),
            GroupSummary(nsid: "2@N2", name: "Night Photography"),
            GroupSummary(nsid: "3@N3", name: "Night Photography Club"),
        ]
        #expect(GroupResolver.exactMatch(in: results, identifier: "Night Photography") == "2@N2")
    }

    @Test func matchingIgnoresSpacingCaseAndHTMLEntities() {
        let results = [GroupSummary(nsid: "7@N7", name: "Black &amp; White")]
        #expect(GroupResolver.exactMatch(in: results, identifier: "black & white") == "7@N7")
        #expect(GroupResolver.exactMatch(in: results, identifier: "BLACK&WHITE") == "7@N7")
    }

    @Test func noConfidentMatchReturnsNothingRatherThanGuessing() {
        let results = [GroupSummary(nsid: "1@N1", name: "Something Else"),
                       GroupSummary(nsid: "2@N2", name: "Another Thing")]
        #expect(GroupResolver.exactMatch(in: results, identifier: "Night Photography") == nil)
        #expect(GroupResolver.exactMatch(in: [], identifier: "anything") == nil)
        #expect(GroupResolver.exactMatch(in: results, identifier: "") == nil)
    }

    @Test func aBlankQueryListsThePoolAndATypedOneSearchesIt() {
        #expect(GroupResolver.query(groupID: "9@N1", text: "   ")
            == .groupPool(groupID: "9@N1"))
        #expect(GroupResolver.query(groupID: "9@N1", text: "boats")
            == .groupSearch(groupID: "9@N1", text: "boats"))
    }
}
