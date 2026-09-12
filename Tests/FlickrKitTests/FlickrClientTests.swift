import Foundation
import Testing

@testable import FlickrKit

/// Ported from `tests/test_api.py`.
///
/// Flickr intermittently answers `stat=fail` with "the Flickr API service is
/// not currently available" — around one call in three during a blip, and a
/// blip lasts a few seconds. Surfacing that as an error dialog is wrong: the
/// same request usually succeeds immediately afterwards.
@Suite struct FlickrClientTests {

    private func client(_ transport: ScriptedTransport,
                        sleeper: SleepRecorder = SleepRecorder(),
                        credentials: OAuth1.Credentials = Fixtures.credentials) -> FlickrClient {
        FlickrClient(credentials: credentials, transport: transport, sleep: sleeper.sleep)
    }

    // MARK: - The happy path

    @Test func aSuccessfulCallIsReturnedUnchanged() async throws {
        let transport = ScriptedTransport(always: Fixtures.page(ids: ["1", "2"]))
        let page = try await client(transport).photos(PhotoRequest(query: .search(text: "x")))
        #expect(page.photos.map(\.id) == ["1", "2"])
        #expect(await transport.callCount == 1)
    }

    // MARK: - Retrying

    @Test func aTransientFailureIsRetriedAndSucceeds() async throws {
        let transport = ScriptedTransport([
            .body(Fixtures.failure(code: 201)),
            .body(Fixtures.page(ids: ["7"])),
        ])
        let page = try await client(transport).photos(PhotoRequest(query: .search(text: "x")))
        #expect(page.photos.map(\.id) == ["7"])
        #expect(await transport.callCount == 2)
    }

    @Test func severalBlipsInARowStillRecover() async throws {
        let transport = ScriptedTransport([
            .body(Fixtures.failure(code: 201)),
            .body(Fixtures.failure(code: 105)),
            .body(Fixtures.failure(code: 111)),
            .body(Fixtures.page(ids: ["7"])),
        ])
        let page = try await client(transport).photos(PhotoRequest(query: .search(text: "x")))
        #expect(page.photos.count == 1)
        #expect(await transport.callCount == 4)
    }

    @Test func itGivesUpAfterTheAttemptLimit() async throws {
        let transport = ScriptedTransport(always: Fixtures.failure(code: 201))
        await #expect(throws: FlickrError.self) {
            _ = try await client(transport).photos(PhotoRequest(query: .search(text: "x")))
        }
        #expect(await transport.callCount == RetryPolicy.standard.attempts)
    }

    @Test func givingUpReadsAsBusyRatherThanAsAnError() async throws {
        let transport = ScriptedTransport(always: Fixtures.failure(code: 201))
        do {
            _ = try await client(transport).photos(PhotoRequest(query: .search(text: "x")))
            Issue.record("expected the call to fail")
        } catch let error as FlickrError {
            #expect(error.isTransient)
            #expect(error.message.isEmpty == false)
        }
    }

    /// "Photo not found" is not going to become true by asking again.
    @Test func aPermanentErrorIsNotRetried() async throws {
        let transport = ScriptedTransport(
            always: Fixtures.failure(code: 1, message: "Photo not found"))
        await #expect(throws: FlickrError.self) {
            _ = try await client(transport).photos(PhotoRequest(query: .search(text: "x")))
        }
        #expect(await transport.callCount == 1)
    }

    @Test func everyBlipCodeIsTreatedAsTransient() async throws {
        for code in [105, 106, 111, 112, 201] {
            let transport = ScriptedTransport([
                .body(Fixtures.failure(code: code)),
                .body(Fixtures.page(ids: ["1"])),
            ])
            _ = try await client(transport).photos(PhotoRequest(query: .search(text: "x")))
            #expect(await transport.callCount == 2)
        }
    }

    @Test func transportErrorsAreRetried() async throws {
        let transport = ScriptedTransport([
            .failure(.transport("connection lost")),
            .body(Fixtures.page(ids: ["1"])),
        ])
        _ = try await client(transport).photos(PhotoRequest(query: .search(text: "x")))
        #expect(await transport.callCount == 2)
    }

    @Test func aPersistentTransportFailureIsReportedAsTransient() async throws {
        let transport = ScriptedTransport(
            [.failure(.transport("offline")), .failure(.transport("offline")),
             .failure(.transport("offline")), .failure(.transport("offline"))])
        do {
            _ = try await client(transport).photos(PhotoRequest(query: .search(text: "x")))
            Issue.record("expected the call to fail")
        } catch let error as FlickrError {
            #expect(error.isTransient)
        }
    }

    /// A malformed body is not a blip; asking again will produce the same bytes.
    @Test func anUnreadableReplyIsNotRetried() async throws {
        let transport = ScriptedTransport(always: "<html>502</html>")
        await #expect(throws: FlickrError.self) {
            _ = try await client(transport).photos(PhotoRequest(query: .search(text: "x")))
        }
        #expect(await transport.callCount == 1)
    }

    // MARK: - Backing off

    @Test func itBacksOffBetweenAttempts() async throws {
        let recorder = SleepRecorder()
        let transport = ScriptedTransport(always: Fixtures.failure(code: 201))
        _ = try? await client(transport, sleeper: recorder)
            .photos(PhotoRequest(query: .search(text: "x")))
        #expect(recorder.durations == RetryPolicy.standard.backoff)
    }

    @Test func thereIsNoSleepAfterTheFinalAttempt() async throws {
        let recorder = SleepRecorder()
        let transport = ScriptedTransport(always: Fixtures.failure(code: 201))
        _ = try? await client(transport, sleeper: recorder)
            .photos(PhotoRequest(query: .search(text: "x")))
        #expect(recorder.durations.count == RetryPolicy.standard.attempts - 1)
    }

    @Test func theRetryBudgetSpansSecondsNotMilliseconds() {
        #expect(RetryPolicy.standard.attempts == 4)
        #expect(RetryPolicy.standard.backoff == [.milliseconds(500), .milliseconds(1500),
                                                 .seconds(3)])
    }

    @Test func aSuccessfulCallNeverSleeps() async throws {
        let recorder = SleepRecorder()
        let transport = ScriptedTransport(always: Fixtures.page(ids: ["1"]))
        _ = try await client(transport, sleeper: recorder)
            .photos(PhotoRequest(query: .search(text: "x")))
        #expect(recorder.durations.isEmpty)
    }

    // MARK: - What goes out

    @Test func theOutgoingQueryCarriesTheRequestsParameters() async throws {
        let transport = ScriptedTransport(always: Fixtures.page(ids: ["1"]))
        let filters = SearchFilters(licenses: [.allRightsReserved, .by],
                                    sort: .dateTakenDescending)
        _ = try await client(transport).photos(
            PhotoRequest(query: .search(text: "blue sky"), filters: filters, page: 3))

        let sent = await transport.lastQueryItems
        #expect(sent["method"] == "flickr.photos.search")
        #expect(sent["text"] == "blue sky")
        #expect(sent["sort"] == "date-taken-desc")
        #expect(sent["license"] == "0,4")
        #expect(sent["page"] == "3")
        #expect(sent["oauth_signature"] != nil)
    }

    @Test func theSizeFilterIsAppliedToTheResultsNotSent() async throws {
        let transport = ScriptedTransport(always: """
        {"photos":{"page":1,"pages":1,"perpage":25,"total":2,"photo":[
          {"id":"big","url_o":"https://live.staticflickr.com/o.jpg"},
          {"id":"small","url_sq":"https://live.staticflickr.com/sq.jpg"}
        ]},"stat":"ok"}
        """)
        let page = try await client(transport).photos(
            PhotoRequest(query: .search(text: "x"), filters: SearchFilters(sizes: [.large])))
        #expect(page.photos.map(\.id) == ["big"])
        #expect(await transport.lastQueryItems["size"] == nil)
    }

    @Test func anUnsignedRequestStillCarriesTheAPIKey() async throws {
        let transport = ScriptedTransport(always: Fixtures.page(ids: ["1"]))
        _ = try await client(transport, credentials: Fixtures.unauthenticated)
            .photos(PhotoRequest(query: .search(text: "x")))
        let sent = await transport.lastQueryItems
        #expect(sent["oauth_consumer_key"] == "key")
        #expect(sent["oauth_token"] == nil)
    }

    /// Asking for "my photos" without a token would come back as an OAuth
    /// failure the user cannot act on. It is refused before it is sent.
    @Test func askingForYourOwnPhotosWithoutATokenFailsBeforeTheRequest() async throws {
        let transport = ScriptedTransport(always: Fixtures.page(ids: ["1"]))
        await #expect(throws: FlickrError.self) {
            _ = try await client(transport, credentials: Fixtures.unauthenticated)
                .photos(PhotoRequest(query: .myPhotos))
        }
        #expect(await transport.callCount == 0)
    }

    // MARK: - Resolving people and groups

    @Test func aNumericUserIDIsUsedWithoutALookup() async throws {
        let transport = ScriptedTransport(always: Fixtures.page(ids: ["1"]))
        let resolved = try await client(transport).resolveUser(from: "12345@N00")
        #expect(resolved == "12345@N00")
        #expect(await transport.callCount == 0)
    }

    @Test func aPhotostreamURLYieldsTheUsernameToLookUp() async throws {
        let transport = ScriptedTransport(
            always: #"{"user":{"id":"99@N99","username":{"_content":"someone"}},"stat":"ok"}"#)
        let resolved = try await client(transport)
            .resolveUser(from: "https://www.flickr.com/photos/someone/")
        #expect(resolved == "99@N99")
        #expect(await transport.lastQueryItems["username"] == "someone")
    }

    @Test func aUserThatDoesNotExistIsAMessageNotACrash() async throws {
        let transport = ScriptedTransport(
            always: Fixtures.failure(code: 1, message: "User not found"))
        await #expect(throws: FlickrError.self) {
            _ = try await client(transport).resolveUser(from: "nobody")
        }
    }

    @Test func aGroupSlugIsLookedUpBeforeItIsSearchedFor() async throws {
        let transport = ScriptedTransport([
            .body(#"{"group":{"id":"55@N55"},"stat":"ok"}"#),
            .body(#"{"group":{"id":"55@N55","name":{"_content":"Night Photography"}},"stat":"ok"}"#),
        ])
        let group = try await client(transport).resolveGroup(from: "nightphotography")
        #expect(group.nsid == "55@N55")
        #expect(group.name == "Night Photography")
    }

    /// `flickr.groups.search` is fuzzy, so an unrelated first result must not be
    /// loaded as though it were the group asked for.
    @Test func aFuzzySearchResultIsOnlyAcceptedOnAnExactNameMatch() async throws {
        let transport = ScriptedTransport([
            // "Night Photography" as a slug, then "NightPhotography" — neither
            // is a group URL — before the name search is consulted.
            .body(Fixtures.failure(code: 1, message: "Group not found")),
            .body(Fixtures.failure(code: 1, message: "Group not found")),
            .body("""
            {"groups":{"group":[{"nsid":"1@N1","name":"Night Photography Addicts"},
            {"nsid":"2@N2","name":"Night Photography"}]},"stat":"ok"}
            """),
            .body(#"{"group":{"id":"2@N2","name":{"_content":"Night Photography"}},"stat":"ok"}"#),
        ])
        let group = try await client(transport).resolveGroup(from: "Night Photography")
        #expect(group.nsid == "2@N2")
    }

    @Test func noExactGroupMatchIsReportedRatherThanGuessed() async throws {
        let transport = ScriptedTransport([
            .body(Fixtures.failure(code: 1, message: "Group not found")),
            .body(Fixtures.failure(code: 1, message: "Group not found")),
            .body(#"{"groups":{"group":[{"nsid":"1@N1","name":"Something Else"}]},"stat":"ok"}"#),
        ])
        await #expect(throws: FlickrError.self) {
            _ = try await client(transport).resolveGroup(from: "Night Photography")
        }
    }
}

/// Resolving a group by a name that is really a slug.
///
/// Measured against the live API: `flickr.groups.search` for "black and white"
/// returns eight groups, the first of which is "Black and White Unlimited" —
/// while `flickr.urls.lookupGroup` on `/groups/blackandwhite/` finds the group
/// actually named "Black and White". The name search never surfaces it, so
/// refusing at that point told the user a group does not exist when it does.
@Suite struct GroupSlugResolutionTests {

    private func client(_ transport: ScriptedTransport) -> FlickrClient {
        FlickrClient(credentials: Fixtures.credentials, transport: transport,
                     sleep: { _ in })
    }

    @Test func aNameWithSpacesIsAlsoTriedWithoutThem() async throws {
        let transport = ScriptedTransport([
            // "Black and White" as a slug: Flickr has no such URL.
            .body(Fixtures.failure(code: 1, message: "Group not found")),
            // "blackandwhite" as a slug: it does.
            .body(#"{"group":{"id":"16978849@N00"},"stat":"ok"}"#),
            .body(#"{"group":{"id":"16978849@N00","name":{"_content":"Black and White"}},"stat":"ok"}"#),
        ])
        let group = try await client(transport).resolveGroup(from: "Black and White")
        #expect(group.nsid == "16978849@N00")
        #expect(group.name == "Black and White")
    }

    /// The despaced slug is still an *exact* route — but the group living at
    /// that URL has to be the one that was asked for, or this would be guessing
    /// by another name.
    @Test func aDespacedSlugNamingSomethingElseIsNotAccepted() async throws {
        let transport = ScriptedTransport([
            .body(Fixtures.failure(code: 1, message: "Group not found")),
            .body(#"{"group":{"id":"99@N99"},"stat":"ok"}"#),
            // The slug resolves, but to a group of another name entirely.
            .body(#"{"group":{"id":"99@N99","name":{"_content":"Something Else"}},"stat":"ok"}"#),
            // …so the fuzzy search is still consulted, and still finds nothing.
            .body(#"{"groups":{"group":[]},"stat":"ok"}"#),
        ])
        await #expect(throws: FlickrError.self) {
            _ = try await client(transport).resolveGroup(from: "Black and White")
        }
    }

    @Test func aNameWithoutSpacesIsNotLookedUpTwice() async throws {
        let transport = ScriptedTransport([
            .body(Fixtures.failure(code: 1, message: "Group not found")),
            .body(#"{"groups":{"group":[{"nsid":"1@N1","name":"Nightshots"}]},"stat":"ok"}"#),
            .body(#"{"group":{"id":"1@N1","name":{"_content":"Nightshots"}},"stat":"ok"}"#),
        ])
        let group = try await client(transport).resolveGroup(from: "Nightshots")
        #expect(group.nsid == "1@N1")
        // lookupGroup, groups.search, getInfo — no second slug attempt.
        #expect(await transport.callCount == 3)
    }
}
