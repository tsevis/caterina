import Foundation

extension FlickrClient {

    public func photoList(_ list: PhotoList, page: Int) async throws -> LibraryPage {
        let data = try await send(list.parameters(page: page))
        return try LibraryResponse.page(from: data, container: list.container)
    }

    public func groups(of userID: String) async throws -> [AccountGroup] {
        let data = try await call("flickr.people.getGroups", ["user_id": userID])
        struct Envelope: Decodable { let groups: Groups }
        struct Groups: Decodable { let group: [FlickrResponse.Lenient<Entry>]? }
        struct Entry: Decodable {
            let nsid: String; let name: String?
            let members: FlickrResponse.LooseInt?; let pool_count: FlickrResponse.LooseInt?; let admin: FlickrResponse.LooseInt?
        }
        return (try InsightsResponse.decode(Envelope.self, data, "your groups").groups.group ?? [])
            .compactMap(\.value).map {
                AccountGroup(id: $0.nsid, name: $0.name ?? "", members: $0.members?.value ?? 0,
                             photos: $0.pool_count?.value ?? 0, isAdmin: ($0.admin?.value ?? 0) != 0)
            }
    }

    /// Your galleries, newest first. Galleries hold other people's photos.
    public func galleries() async throws -> [Gallery] {
        var all: [Gallery] = []
        var page = 1
        var pages = 1
        repeat {
            let reply = try await galleryPage(page)
            all += reply.galleries
            pages = reply.pages
            page += 1
        } while page <= pages
        return all
    }

    private func galleryPage(_ page: Int) async throws -> (galleries: [Gallery], pages: Int) {
        let data = try await call("flickr.galleries.getList",
                                  ["continuation": "0", "per_page": "500", "page": String(page)])
        struct Envelope: Decodable { let galleries: Galleries }
        struct Galleries: Decodable { let pages: FlickrResponse.LooseInt?; let gallery: [FlickrResponse.Lenient<Entry>]? }
        struct Entry: Decodable {
            let id: String; let title: InsightsResponse.Text?; let description: InsightsResponse.Text?
            let count_photos: FlickrResponse.LooseInt?; let count_videos: FlickrResponse.LooseInt?
        }
        let reply = try InsightsResponse.decode(Envelope.self, data, "your galleries").galleries
        return ((reply.gallery ?? []).compactMap(\.value).map {
            Gallery(id: $0.id, title: $0.title?._content ?? "", description: $0.description?._content ?? "",
                    itemCount: ($0.count_photos?.value ?? 0) + ($0.count_videos?.value ?? 0))
        }, max(1, reply.pages?.value ?? 1))
    }

    /// Your collections, as the tree you built on flickr.com.
    public func collections() async throws -> [PhotoCollection] {
        let data = try await call("flickr.collections.getTree", [:])
        struct Envelope: Decodable { let collections: Level }
        struct Level: Decodable { let collection: [Node]? }
        return (try InsightsResponse.decode(Envelope.self, data, "your collections").collections.collection ?? [])
            .map(\.tree)
    }

    /// People you follow, 1,000 a page.
    public func contacts(page: Int) async throws -> ContactPage {
        let data = try await call("flickr.contacts.getList", ["page": String(page), "per_page": "1000", "sort": "name"])
        struct Envelope: Decodable { let contacts: Contacts }
        struct Contacts: Decodable {
            let page: FlickrResponse.LooseInt?; let pages: FlickrResponse.LooseInt?
            let contact: [FlickrResponse.Lenient<Entry>]?
        }
        struct Entry: Decodable {
            let nsid: String; let username: String?; let realname: String?
            let friend: FlickrResponse.LooseInt?; let family: FlickrResponse.LooseInt?
        }
        let contacts = try InsightsResponse.decode(Envelope.self, data, "your contacts").contacts
        return ContactPage(page: max(1, contacts.page?.value ?? 1), pages: max(1, contacts.pages?.value ?? 1),
                           contacts: (contacts.contact ?? []).compactMap(\.value).map {
                               Contact(id: $0.nsid, username: $0.username ?? "", realName: $0.realname ?? "",
                                       isFriend: ($0.friend?.value ?? 0) != 0, isFamily: ($0.family?.value ?? 0) != 0)
                           })
    }
}

/// One level of `flickr.collections.getTree`.
private struct Node: Decodable {
    struct Album: Decodable { let id: String; let title: String? }
    let id: String
    let title: String?
    let description: String?
    let set: [Album]?
    let collection: [Node]?

    var tree: PhotoCollection {
        PhotoCollection(id: id, title: title ?? "", description: description ?? "",
                        albums: (set ?? []).map { .init(id: $0.id, title: $0.title ?? "") },
                        children: (collection ?? []).map(\.tree))
    }
}
