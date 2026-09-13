import MapKit
import SwiftUI

import FlickrKit

/// Place the tray on a map, take its location away, or say who can see it.
struct LocationForm: View {
    @Binding var draft: EditDraft
    @State private var camera = MapCameraPosition.automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $draft.locationMode) {
                Text("Place").tag(EditDraft.LocationMode.set)
                Text("Remove").tag(EditDraft.LocationMode.remove)
                Text("Who can see").tag(EditDraft.LocationMode.privacy)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch draft.locationMode {
            case .set: placeForm
            case .remove:
                Text("Removes the location from every photo in the tray. Undo puts it back.")
                    .foregroundStyle(Theme.inkSecondary)
            case .privacy: privacyForm
            }
        }
    }

    private var placeForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            MapReader { proxy in
                Map(position: $camera) {
                    if hasPlace {
                        Marker("", coordinate: coordinate)
                    }
                }
                .onTapGesture { point in
                    guard let picked = proxy.convert(point, from: .local) else { return }
                    draft.latitude = picked.latitude
                    draft.longitude = picked.longitude
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
            Text("Click the map to place the photos.").font(.caption).foregroundStyle(Theme.inkSecondary)
            HStack {
                TextField("Latitude", value: $draft.latitude, format: .number.precision(.fractionLength(0...6)))
                TextField("Longitude", value: $draft.longitude, format: .number.precision(.fractionLength(0...6)))
            }
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            Stepper("Accuracy \(draft.accuracy) of 16 (street)", value: $draft.accuracy, in: 1...16)
        }
    }

    private var privacyForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Anyone", isOn: $draft.geoIsPublic)
            Group {
                Toggle("Contacts", isOn: $draft.geoIsContact)
                Toggle("Friends", isOn: $draft.geoIsFriend)
                Toggle("Family", isOn: $draft.geoIsFamily)
            }
            .disabled(draft.geoIsPublic)
            .padding(.leading, 18)
            Text("Photos without a location are refused by Flickr and listed in Activity.")
                .font(.caption).foregroundStyle(Theme.inkSecondary)
        }
    }

    private var hasPlace: Bool { draft.latitude != 0 || draft.longitude != 0 }
    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude)
    }
}
