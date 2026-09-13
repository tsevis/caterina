import Foundation

/// Decoding the replies behind a photo's record.
enum InsightsResponse {
    typealias LooseInt = FlickrResponse.LooseInt

    struct Text: Decodable { let _content: String? }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data, _ what: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw FlickrError.malformedResponse("Flickr sent \(what) in an unexpected shape.")
        }
    }

    static func info(from data: Data) throws -> PhotoInfo {
        struct Envelope: Decodable { let photo: Photo }
        struct Photo: Decodable {
            let id: String
            let license: String?
            let views: LooseInt?
            let owner: Owner?
            let title: Text?
            let description: Text?
            let visibility: Visibility?
            let dates: Dates?
            let comments: Text?
            let tags: Tags?
            let location: Location?
            let urls: URLs?
        }
        struct Owner: Decodable { let nsid: String?; let username: String?; let realname: String? }
        struct Visibility: Decodable { let ispublic: LooseInt?; let isfriend: LooseInt?; let isfamily: LooseInt? }
        struct Dates: Decodable { let posted: LooseInt?; let taken: String?; let takenunknown: LooseInt? }
        struct Tags: Decodable { let tag: [Tag]? }
        struct Tag: Decodable { let raw: String?; let _content: String? }
        struct Location: Decodable {
            let latitude: LooseDouble?; let longitude: LooseDouble?; let accuracy: LooseInt?
            let locality: Text?; let country: Text?
        }
        struct URLs: Decodable { let url: [URLEntry]? }
        struct URLEntry: Decodable { let type: String?; let _content: String? }

        let photo = try decode(Envelope.self, data, "the photo's details").photo
        let flag = { (value: LooseInt?) in (value?.value ?? 0) != 0 }
        let location = photo.location.flatMap { location -> LibraryPhoto.Location? in
            guard let latitude = location.latitude?.value, let longitude = location.longitude?.value,
                  latitude != 0 || longitude != 0 else { return nil }
            return .init(latitude: latitude, longitude: longitude, accuracy: location.accuracy?.value ?? 0)
        }
        let place = [photo.location?.locality?._content, photo.location?.country?._content]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return PhotoInfo(
            id: photo.id, title: photo.title?._content ?? "", description: photo.description?._content ?? "",
            owner: .init(nsid: photo.owner?.nsid ?? "", username: photo.owner?.username ?? "",
                         realName: photo.owner?.realname ?? ""),
            views: photo.views?.value ?? 0,
            commentCount: Int(photo.comments?._content ?? "") ?? 0,
            license: photo.license.flatMap(License.init(rawValue:)),
            tags: (photo.tags?.tag ?? []).compactMap { $0.raw ?? $0._content },
            posted: photo.dates?.posted?.value.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            taken: flag(photo.dates?.takenunknown) ? nil : photo.dates?.taken,
            visibility: .init(isPublic: flag(photo.visibility?.ispublic), isFriend: flag(photo.visibility?.isfriend),
                              isFamily: flag(photo.visibility?.isfamily)),
            location: location, place: place.isEmpty ? nil : place.joined(separator: ", "),
            pageURL: photo.urls?.url?.first { $0.type == "photopage" }?._content.flatMap(URL.init(string:)))
    }

    static func favorites(from data: Data) throws -> FavePage {
        struct Envelope: Decodable { let photo: Photo }
        struct Photo: Decodable {
            let page: LooseInt?; let pages: LooseInt?; let total: LooseInt?
            let person: [FlickrResponse.Lenient<Person>]?
        }
        struct Person: Decodable { let nsid: String; let username: String?; let favedate: LooseInt }
        let photo = try decode(Envelope.self, data, "who faved the photo").photo
        let faves = (photo.person ?? []).compactMap(\.value).compactMap { person -> Fave? in
            guard let date = person.favedate.value else { return nil }
            return Fave(nsid: person.nsid, username: person.username ?? "",
                        date: Date(timeIntervalSince1970: TimeInterval(date)))
        }
        return FavePage(page: max(1, photo.page?.value ?? 1), pages: max(1, photo.pages?.value ?? 1),
                        total: photo.total?.value ?? faves.count, faves: faves)
    }

    static func comments(from data: Data) throws -> [PhotoComment] {
        struct Envelope: Decodable { let comments: Comments }
        struct Comments: Decodable { let comment: [FlickrResponse.Lenient<Comment>]? }
        struct Comment: Decodable {
            let id: String; let authorname: String?; let datecreate: LooseInt?; let _content: String?
        }
        return try decode(Envelope.self, data, "the comments").comments.comment?.compactMap(\.value).map {
            PhotoComment(id: $0.id, authorName: $0.authorname ?? "",
                         date: Date(timeIntervalSince1970: TimeInterval($0.datecreate?.value ?? 0)),
                         text: $0._content ?? "")
        } ?? []
    }

    static func contexts(from data: Data) throws -> PhotoContexts {
        struct Envelope: Decodable { let set: [Entry]?; let pool: [Entry]? }
        struct Entry: Decodable { let id: String; let title: String? }
        let envelope = try decode(Envelope.self, data, "where the photo appears")
        let places = { (entries: [Entry]?) in
            (entries ?? []).map { PhotoContexts.Place(id: $0.id, title: $0.title ?? "") }
        }
        return PhotoContexts(albums: places(envelope.set), groups: places(envelope.pool))
    }

    static func exif(from data: Data) throws -> PhotoExif {
        struct Envelope: Decodable { let photo: Photo }
        struct Photo: Decodable { let camera: String?; let exif: [FlickrResponse.Lenient<Entry>]? }
        struct Entry: Decodable { let label: String?; let tag: String?; let raw: Text?; let clean: Text? }
        let photo = try decode(Envelope.self, data, "the camera data").photo
        let fields = (photo.exif ?? []).compactMap(\.value).compactMap { entry -> ExifField? in
            guard let value = entry.clean?._content ?? entry.raw?._content, !value.isEmpty else { return nil }
            return ExifField(label: entry.label ?? entry.tag ?? "", value: value)
        }
        return PhotoExif(camera: photo.camera.flatMap { $0.isEmpty ? nil : $0 }, fields: fields, isHidden: false)
    }
}

/// A decimal that may arrive as a number or a string.
struct LooseDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) { value = number; return }
        value = (try? container.decode(String.self)).flatMap(Double.init)
    }
}
