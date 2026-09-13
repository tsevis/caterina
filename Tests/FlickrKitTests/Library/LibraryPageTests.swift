import Foundation
import Testing

@testable import FlickrKit

/// Reading your own photos in bulk, with everything Organize and Insights sort
/// and filter on.
///
/// **One call, 500 photos, every field.** A library of 20,000 photos is 40
/// calls; asking photo by photo would be 20,000, which is more than five hours
/// of Flickr's allowance.
@Suite struct LibraryPageTests {

    static let entry = """
    {"id":"53712","owner":"12037949@N00","secret":"a1","server":"65535","farm":66,
     "title":"Harbour at dusk","ispublic":1,"isfriend":0,"isfamily":1,
     "description":{"_content":"Piraeus, looking west."},
     "license":"4","dateupload":"1717243200","lastupdate":"1717329600",
     "datetaken":"2024-06-01 21:14:05","datetakengranularity":0,"datetakenunknown":"0",
     "views":"1842","tags":"piraeus harbour dusk","media":"photo",
     "latitude":37.9421,"longitude":23.6465,"accuracy":"16",
     "url_q":"https://live.staticflickr.com/65535/53712_a1_q.jpg",
     "url_z":"https://live.staticflickr.com/65535/53712_a1_z.jpg","ownername":"tsevis"}
    """

    static func page(_ entries: [String], page: Int = 1, pages: Int = 1, total: Int? = nil) -> Data {
        Data("""
        {"photos":{"page":\(page),"pages":\(pages),"perpage":500,"total":\(total ?? entries.count),
        "photo":[\(entries.joined(separator: ","))]},"stat":"ok"}
        """.utf8)
    }

    @Test func everyFieldIsRead() throws {
        let page = try LibraryResponse.page(from: Self.page([Self.entry]))
        let photo = try #require(page.photos.first)

        #expect(photo.id == "53712")
        #expect(photo.title == "Harbour at dusk")
        #expect(photo.description == "Piraeus, looking west.")
        #expect(photo.tags == ["piraeus", "harbour", "dusk"])
        #expect(photo.license == .by)
        #expect(photo.visibility == LibraryPhoto.Visibility(isPublic: true, isFriend: false, isFamily: true))
        #expect(photo.uploaded == Date(timeIntervalSince1970: 1_717_243_200))
        #expect(photo.lastUpdated == Date(timeIntervalSince1970: 1_717_329_600))
        #expect(photo.taken == "2024-06-01 21:14:05")
        #expect(photo.views == 1842)
        #expect(photo.media == .photo)
        #expect(photo.location == LibraryPhoto.Location(latitude: 37.9421, longitude: 23.6465, accuracy: 16))
        #expect(photo.thumbnailURL == "https://live.staticflickr.com/65535/53712_a1_q.jpg")
        #expect(photo.mediumURL == "https://live.staticflickr.com/65535/53712_a1_z.jpg")
        #expect(photo.ownerID == "12037949@N00")
        #expect(photo.ownerName == "tsevis")
    }

    /// Flickr says "no location" as a latitude and longitude of zero.
    @Test func zeroZeroIsNoLocation() throws {
        let entry = #"{"id":"1","title":"","latitude":0,"longitude":"0","accuracy":0,"ispublic":0,"isfriend":0,"isfamily":0}"#
        let photo = try #require(try LibraryResponse.page(from: Self.page([entry])).photos.first)
        #expect(photo.location == nil)
        #expect(photo.tags.isEmpty)
        #expect(photo.description == "")
        #expect(photo.visibility == LibraryPhoto.Visibility(isPublic: false, isFriend: false, isFamily: false))
    }

    /// Flickr marks an unknown date taken as unknown and fills in the upload
    /// date; showing that as when the photo was taken would be wrong.
    @Test func anUnknownDateTakenIsNotADate() throws {
        let entry = #"{"id":"1","title":"","datetaken":"2024-06-01 21:14:05","datetakenunknown":"1"}"#
        let photo = try #require(try LibraryResponse.page(from: Self.page([entry])).photos.first)
        #expect(photo.taken == nil)
    }

    @Test func aVideoIsKnownToBeOne() throws {
        let entry = #"{"id":"1","title":"","media":"video"}"#
        let photo = try #require(try LibraryResponse.page(from: Self.page([entry])).photos.first)
        #expect(photo.media == .video)
    }

    @Test func anEntryWithoutAnIdIsSkippedAndCounted() throws {
        let page = try LibraryResponse.page(from: Self.page([Self.entry, #"{"title":"orphan"}"#],
                                                            pages: 3, total: 1201))
        #expect(page.photos.map(\.id) == ["53712"])
        #expect(page.skippedEntries == 1)
        #expect(page.pages == 3)
        #expect(page.total == 1201)
    }

    @Test func aFailureIsFlickrsError() {
        #expect(throws: FlickrError.api(code: 2, message: "Unknown user", transient: false)) {
            _ = try LibraryResponse.page(from: Data(#"{"stat":"fail","code":2,"message":"Unknown user"}"#.utf8))
        }
    }

    // MARK: - The requests

    @Test func theWholeLibraryIsAskedFor500AtATime() {
        let query = LibraryQuery.everything(page: 3)
        let fields = Dictionary(uniqueKeysWithValues: query.parameters.map { ($0.name, $0.value) })
        #expect(fields["method"] == "flickr.people.getPhotos")
        #expect(fields["user_id"] == "me")
        #expect(fields["per_page"] == "500")
        #expect(fields["page"] == "3")
        let extras = Set((fields["extras"] ?? "").split(separator: ",").map(String.init))
        #expect(extras.isSuperset(of: ["description", "license", "date_upload", "date_taken",
                                       "last_update", "views", "tags", "geo", "media", "url_q",
                                       "url_z", "owner_name"]))
    }

    @Test func changesAreAskedForSinceTheLastSync() {
        let query = LibraryQuery.updated(since: Date(timeIntervalSince1970: 1_717_329_600), page: 1)
        let fields = Dictionary(uniqueKeysWithValues: query.parameters.map { ($0.name, $0.value) })
        #expect(fields["method"] == "flickr.photos.recentlyUpdated")
        #expect(fields["min_date"] == "1717329600")
        #expect(fields["user_id"] == nil)
        #expect(fields["per_page"] == "500")
    }

    @Test func theClientNeedsASignedInAccount() async throws {
        let transport = ScriptedTransport(always: String(decoding: Self.page([Self.entry]), as: UTF8.self))
        let signedOut = FlickrClient(credentials: Fixtures.unauthenticated, transport: transport,
                                     budget: .unspaced, sleep: SleepRecorder().sleep)
        await #expect(throws: FlickrError.permissionNeeded(.read)) {
            _ = try await signedOut.library(.everything(page: 1))
        }

        let signedIn = FlickrClient(credentials: Fixtures.credentials, transport: transport,
                                    budget: .unspaced, sleep: SleepRecorder().sleep)
        let page = try await signedIn.library(.everything(page: 1))
        #expect(page.photos.count == 1)
    }
}
