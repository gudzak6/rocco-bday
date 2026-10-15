import Foundation
import CoreLocation
import MapKit

enum MemoryMomentCatalog {
    struct Photo: Identifiable, Hashable, Sendable {
        let id: UUID
        let assetName: String
    }

    struct Entry: Identifiable, Hashable, Sendable {
        let id: UUID
        let locationId: UUID
        let title: String
        let locationName: String
        let caption: String?
        let date: Date?
        let photos: [Photo]
        var latitude: Double
        var longitude: Double
        let geocodeQuery: String
        let hint: String
        let sortOrder: Int

        var thumbnailAsset: String { photos.first?.assetName ?? "" }

        var asLocation: GameLocation {
            GameLocation(
                id: locationId,
                title: locationName,
                latitude: latitude,
                longitude: longitude,
                radiusMeters: 75,
                maxAccuracyMeters: 250,
                dwellSeconds: 0,
                hint: hint,
                sortOrder: sortOrder,
                hasFallback: false
            )
        }
    }

    static let londonId = UUID(uuidString: "B1DAF701-0000-4000-8000-000000000001")!
    static let londonLocationId = UUID(uuidString: "B1DAF701-0000-4000-8000-000000000101")!
    static let centralParkId = UUID(uuidString: "B1DAF701-0000-4000-8000-000000000002")!
    static let centralParkLocationId = UUID(uuidString: "B1DAF701-0000-4000-8000-000000000102")!
    static let allAnticoId = UUID(uuidString: "B1DAF701-0000-4000-8000-000000000003")!
    static let allAnticoLocationId = UUID(uuidString: "B1DAF701-0000-4000-8000-000000000103")!
    static let stoutId = UUID(uuidString: "B1DAF701-0000-4000-8000-000000000004")!
    static let stoutLocationId = UUID(uuidString: "B1DAF701-0000-4000-8000-000000000104")!

    /// Public city-center placeholder (Trafalgar Square area). Not a restaurant or private venue.
    static let londonPlaceholder = CLLocationCoordinate2D(latitude: 51.508039, longitude: -0.128069)
    /// Public Central Park landmark (Bethesda Fountain). Offset from Upper East Side catch pins.
    static let centralParkPlaceholder = CLLocationCoordinate2D(latitude: 40.775347, longitude: -73.970812)
    /// Geocoded All'Antico Vinaio at 729 8th Avenue, New York, NY 10036.
    static let allAnticoCoordinate = CLLocationCoordinate2D(latitude: 40.7596992, longitude: -73.9882202)
    /// Geocoded Stout at 109 West 39th Street, New York, NY 10018.
    static let stoutCoordinate = CLLocationCoordinate2D(latitude: 40.7531121, longitude: -73.9856854)

    private static let coordinatePrefix = "memoryMoment.coordinate."

    static var entries: [Entry] {
        baseEntries.map { entry in
            var copy = entry
            if let stored = storedCoordinate(for: entry.id) {
                copy.latitude = stored.latitude
                copy.longitude = stored.longitude
            }
            return copy
        }
    }

    static func entry(id: UUID) -> Entry? {
        entries.first { $0.id == id || $0.locationId == id }
    }

    static func containsLocation(_ id: UUID) -> Bool {
        entries.contains { $0.locationId == id }
    }

    static func merging(_ snapshot: PlayerSnapshot) -> PlayerSnapshot {
        var current = snapshot
        for entry in entries {
            if let index = current.locations.firstIndex(where: { $0.id == entry.locationId || $0.title == entry.locationName }) {
                let existing = current.locations[index]
                current.locations[index] = GameLocation(
                    id: existing.id,
                    title: entry.locationName,
                    latitude: entry.latitude,
                    longitude: entry.longitude,
                    radiusMeters: existing.radiusMeters,
                    maxAccuracyMeters: existing.maxAccuracyMeters,
                    dwellSeconds: 0,
                    hint: entry.hint,
                    sortOrder: existing.sortOrder,
                    hasFallback: existing.hasFallback
                )
            } else {
                current.locations.append(entry.asLocation)
            }
        }
        return current
    }

    @MainActor
    static func refreshCoordinates() async {
        for entry in baseEntries {
            if let coordinate = await resolve(entry.geocodeQuery) {
                store(coordinate, for: entry.id)
            }
        }
    }

    private static var baseEntries: [Entry] {
        [
            Entry(
                id: londonId,
                locationId: londonLocationId,
                title: "London Memories 🇬🇧",
                locationName: "London, England",
                caption: "London was never ready for us.",
                date: nil,
                photos: [
                    Photo(id: UUID(uuidString: "B1DAF701-0000-4000-8000-000000000201")!, assetName: "LondonMemories"),
                ],
                latitude: londonPlaceholder.latitude,
                longitude: londonPlaceholder.longitude,
                geocodeQuery: "Trafalgar Square, London, England",
                hint: "A city-level London placeholder. The organizer can move this pin later.",
                sortOrder: 90
            ),
            Entry(
                id: centralParkId,
                locationId: centralParkLocationId,
                title: "Central Park Memories",
                locationName: "Central Park, New York",
                caption: nil,
                date: nil,
                photos: [
                    Photo(id: UUID(uuidString: "B1DAF701-0000-4000-8000-000000000202")!, assetName: "CentralParkMemories"),
                ],
                latitude: centralParkPlaceholder.latitude,
                longitude: centralParkPlaceholder.longitude,
                geocodeQuery: "Bethesda Fountain, Central Park, New York",
                hint: "A public Central Park landmark. The organizer can move this pin later.",
                sortOrder: 91
            ),
            Entry(
                id: allAnticoId,
                locationId: allAnticoLocationId,
                title: "All'Antico Vinaio",
                locationName: "729 8th Avenue, New York",
                caption: nil,
                date: nil,
                photos: [
                    Photo(id: UUID(uuidString: "B1DAF701-0000-4000-8000-000000000203")!, assetName: "AllAnticoMemories"),
                ],
                latitude: allAnticoCoordinate.latitude,
                longitude: allAnticoCoordinate.longitude,
                geocodeQuery: "All'Antico Vinaio, 729 8th Avenue, New York, NY 10036",
                hint: "The Theater District sandwich shop at 729 8th Avenue.",
                sortOrder: 92
            ),
            Entry(
                id: stoutId,
                locationId: stoutLocationId,
                title: "Stout",
                locationName: "109 West 39th Street, New York",
                caption: nil,
                date: nil,
                photos: [
                    Photo(id: UUID(uuidString: "B1DAF701-0000-4000-8000-000000000204")!, assetName: "StoutMemories"),
                ],
                latitude: stoutCoordinate.latitude,
                longitude: stoutCoordinate.longitude,
                geocodeQuery: "Stout, 109 West 39th Street, New York, NY 10018",
                hint: "Stout NYC at 109 West 39th Street.",
                sortOrder: 93
            ),
        ]
    }

    private static func storedCoordinate(for id: UUID) -> CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: coordinatePrefix + id.uuidString + ".lat") != nil else { return nil }
        return CLLocationCoordinate2D(
            latitude: defaults.double(forKey: coordinatePrefix + id.uuidString + ".lat"),
            longitude: defaults.double(forKey: coordinatePrefix + id.uuidString + ".lon")
        )
    }

    private static func store(_ coordinate: CLLocationCoordinate2D, for id: UUID) {
        UserDefaults.standard.set(coordinate.latitude, forKey: coordinatePrefix + id.uuidString + ".lat")
        UserDefaults.standard.set(coordinate.longitude, forKey: coordinatePrefix + id.uuidString + ".lon")
    }

    private static func resolve(_ query: String) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.758, longitude: -73.985),
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )
        do {
            let response = try await MKLocalSearch(request: request).start()
            if let coordinate = response.mapItems.first?.placemark.coordinate {
                return coordinate
            }
        } catch {
            return nil
        }
        return nil
    }
}
