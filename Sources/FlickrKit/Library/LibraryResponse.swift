import Foundation

/// Decoding `flickr.people.getPhotos` and `flickr.photos.recentlyUpdated`.
public enum LibraryResponse {

    /// `container` is the key the list arrives under: `photos` for nearly
    /// every method, `photoset` for an album's.
    public static func page(from data: Data, container key: String = "photos") throws -> LibraryPage {
        try FlickrResponse.throwIfFailed(data)
        let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard top?[key] != nil else {
            throw FlickrError.malformedResponse("Flickr's reply contained no photos.")
        }
        let container: Container
        do {
            let decoder = JSONDecoder()
            decoder.userInfo[Keyed.key] = key
            container = try decoder.decode(Keyed.self, from: data).container
        } catch {
            throw FlickrError.malformedResponse("Flickr sent the photos in an unexpected shape.")
        }
        let entries = container.photo ?? []
        let photos = entries.compactMap(\.value).map(\.photo)
        let page = max(1, container.page?.value ?? 1)
        // `people.getPhotosOf` says only whether another page follows.
        let pages = container.pages?.value ?? (container.has_next_page?.value == 1 ? page + 1 : page)
        return LibraryPage(page: page,
                           pages: max(1, pages),
                           total: max(0, container.total?.value ?? 0),
                           photos: photos,
                           skippedEntries: entries.count - photos.count)
    }

    /// The list under whichever key the method uses, with its real decoding
    /// error if its shape is wrong.
    private struct Keyed: Decodable {
        static let key = CodingUserInfoKey(rawValue: "container")!
        let container: Container

        init(from decoder: Decoder) throws {
            let name = decoder.userInfo[Self.key] as? String ?? "photos"
            let keyed = try decoder.container(keyedBy: FlickrResponse.DynamicKey.self)
            container = try keyed.decode(Container.self, forKey: FlickrResponse.DynamicKey(stringValue: name)!)
        }
    }

    private struct Container: Decodable {
        let page: FlickrResponse.LooseInt?
        let pages: FlickrResponse.LooseInt?
        let total: FlickrResponse.LooseInt?
        let has_next_page: FlickrResponse.LooseInt?
        let photo: [FlickrResponse.Lenient<Entry>]?
    }

    private struct Entry: Decodable {
        let photo: LibraryPhoto

        init(from decoder: Decoder) throws {
            let fields = try Fields(decoder)
            guard let id = fields.text("id")?.trimmingCharacters(in: .whitespaces), !id.isEmpty else {
                throw FlickrError.malformedResponse("Photo entry with no id.")
            }
            photo = LibraryPhoto(
                id: id,
                title: fields.text("title") ?? "",
                description: fields.content("description"),
                tags: (fields.text("tags") ?? "").split(separator: " ").map(String.init),
                license: fields.text("license").flatMap(License.init(rawValue:)),
                visibility: .init(isPublic: fields.flag("ispublic"),
                                  isFriend: fields.flag("isfriend"),
                                  isFamily: fields.flag("isfamily")),
                uploaded: fields.date("dateupload"),
                lastUpdated: fields.date("lastupdate"),
                taken: fields.flag("datetakenunknown") ? nil : fields.text("datetaken"),
                views: fields.number("views") ?? 0,
                media: fields.text("media").flatMap(LibraryPhoto.Media.init(rawValue:)) ?? .photo,
                location: fields.location(),
                thumbnailURL: fields.text("url_q"),
                mediumURL: fields.text("url_z"),
                ownerID: fields.text("owner"),
                ownerName: fields.text("ownername"))
        }
    }

    /// Flickr sends most numbers as strings and some as numbers, varying by
    /// field and by method. Everything is read loosely.
    private struct Fields {
        let container: KeyedDecodingContainer<FlickrResponse.DynamicKey>

        init(_ decoder: Decoder) throws {
            container = try decoder.container(keyedBy: FlickrResponse.DynamicKey.self)
        }

        private func key(_ name: String) -> FlickrResponse.DynamicKey {
            FlickrResponse.DynamicKey(stringValue: name)!
        }

        func text(_ name: String) -> String? {
            if let string = try? container.decode(String.self, forKey: key(name)) { return string }
            if let number = try? container.decode(Int.self, forKey: key(name)) { return String(number) }
            return nil
        }

        func number(_ name: String) -> Int? {
            (try? container.decode(FlickrResponse.LooseInt.self, forKey: key(name)))?.value
        }

        func decimal(_ name: String) -> Double? {
            if let value = try? container.decode(Double.self, forKey: key(name)) { return value }
            return text(name).flatMap(Double.init)
        }

        func flag(_ name: String) -> Bool { (number(name) ?? 0) != 0 }

        func date(_ name: String) -> Date? {
            number(name).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }

        /// `{"_content": "…"}`, Flickr's wrapper for free text.
        func content(_ name: String) -> String {
            struct Wrapped: Decodable { let _content: String? }
            return (try? container.decode(Wrapped.self, forKey: key(name)))?._content ?? ""
        }

        func location() -> LibraryPhoto.Location? {
            guard let latitude = decimal("latitude"), let longitude = decimal("longitude"),
                  latitude != 0 || longitude != 0 else { return nil }
            return .init(latitude: latitude, longitude: longitude, accuracy: number("accuracy") ?? 0)
        }
    }
}
