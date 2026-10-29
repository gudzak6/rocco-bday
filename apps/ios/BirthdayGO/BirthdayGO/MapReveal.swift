import CoreLocation
import Foundation
import ImageIO
import UIKit

enum MapReveal {
    /// Photos use the same walk-up radius as memory stops.
    static let photoRadiusMeters = 75

    static func isWithinRange(
        distance: Double?,
        accuracy: Double?,
        radius: Double,
        maximumAccuracy: Double
    ) -> Bool {
        guard let distance, let accuracy else { return false }
        return Proximity.isEligible(
            distance: distance,
            radius: radius,
            accuracy: accuracy,
            maximumAccuracy: maximumAccuracy
        )
    }

    /// A stable point 120–400 meters from one of the anchors. The same seed always lands in the same place.
    static func coordinate(seed: String, anchors: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let anchors = anchors.isEmpty
            ? [CLLocationCoordinate2D(latitude: 40.758, longitude: -73.986)]
            : anchors
        let hash = fnv(seed)
        let anchor = anchors[Int(hash % UInt64(anchors.count))]
        let distance = 120.0 + Double(hash % 281)
        let bearing = Double((hash / 281) % 360) * .pi / 180
        let earth = 6_371_000.0
        let lat1 = anchor.latitude * .pi / 180
        let lon1 = anchor.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(distance / earth) + cos(lat1) * sin(distance / earth) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(distance / earth) * cos(lat1),
            cos(distance / earth) - sin(lat1) * sin(lat2)
        )
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    static func stableID(for filename: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let first = fnv(filename)
        let second = fnv("drop-\(filename)")
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: first >> (index * 8))
            bytes[8 + index] = UInt8(truncatingIfNeeded: second >> (index * 8))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func fnv(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

struct PhotoDrop: Identifiable, Hashable, Sendable {
    let id: UUID
    let filename: String
    let latitude: Double
    let longitude: Double

    var asLocation: GameLocation {
        GameLocation(
            id: id,
            title: "Photo",
            latitude: latitude,
            longitude: longitude,
            radiusMeters: MapReveal.photoRadiusMeters,
            maxAccuracyMeters: 250,
            dwellSeconds: 0,
            hint: "Walk up to this photo to reveal it.",
            sortOrder: 200,
            hasFallback: false
        )
    }
}

enum PhotoDropCatalog {
    /// Manhattan stops the photos scatter around. Airports and London are left out so every photo stays walkable.
    static let anchors: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 40.752726, longitude: -73.977229),
        CLLocationCoordinate2D(latitude: 40.750580, longitude: -73.993584),
        CLLocationCoordinate2D(latitude: 40.76694, longitude: -73.98300),
        CLLocationCoordinate2D(latitude: 40.758740, longitude: -73.978674),
        CLLocationCoordinate2D(latitude: 40.74579, longitude: -73.99477),
        CLLocationCoordinate2D(latitude: 40.72148, longitude: -73.95236),
        CLLocationCoordinate2D(latitude: 40.77203, longitude: -73.95431),
        CLLocationCoordinate2D(latitude: 40.775347, longitude: -73.970812),
        CLLocationCoordinate2D(latitude: 40.7596992, longitude: -73.9882202),
        CLLocationCoordinate2D(latitude: 40.7531121, longitude: -73.9856854),
    ]

    private static let stored = load(bundle: .main)

    static func drops() -> [PhotoDrop] { stored }

    static func drop(id: UUID) -> PhotoDrop? {
        stored.first { $0.id == id }
    }

    static func makeDrops(filenames: [String], anchors: [CLLocationCoordinate2D] = anchors) -> [PhotoDrop] {
        filenames.map { name in
            let coordinate = MapReveal.coordinate(seed: name, anchors: anchors)
            return PhotoDrop(
                id: MapReveal.stableID(for: name),
                filename: name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }

    private static func load(bundle: Bundle) -> [PhotoDrop] {
        let urls = bundle.urls(forResourcesWithExtension: "jpg", subdirectory: "PhotoDrops") ?? []
        return makeDrops(filenames: urls.map(\.lastPathComponent).sorted())
    }
}

@MainActor
enum PhotoDropImage {
    private static let thumbs = NSCache<NSString, UIImage>()
    private static let opened = NSCache<NSString, UIImage>()

    static func thumbnail(filename: String) -> UIImage? {
        cached(filename: filename, maxPixel: 96, cache: thumbs, costLimit: 8 * 1024 * 1024)
    }

    static func image(filename: String) -> UIImage? {
        cached(filename: filename, maxPixel: 1200, cache: opened, costLimit: 18 * 1024 * 1024)
    }

    private static func cached(filename: String, maxPixel: Int, cache: NSCache<NSString, UIImage>, costLimit: Int) -> UIImage? {
        cache.totalCostLimit = costLimit
        cache.countLimit = maxPixel <= 96 ? 80 : 2
        let key = filename as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let name = (filename as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "PhotoDrops"),
              let image = downsampled(url: url, maxPixel: maxPixel) else { return nil }
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    private static func downsampled(url: URL, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

enum WalkCloserTaunts {
    static let all = [
        "Walk closer ya bum for more details",
        "Your feet called. They said you forgot them.",
        "This pin does not do curbside pickup.",
        "Closer, birthday boy. The surprise has standards.",
        "GPS can see you loafing.",
        "Nice zoom. Your legs still work, though.",
        "Details are on the other side of a short walk.",
        "You can't tap your way into this one.",
        "Warm. Still a bum's distance away.",
        "The good part starts when you get here.",
        "Standing still is a bold strategy. A wrong one.",
        "Come here. The map is not a delivery app.",
        "That's the not-yet pin, pal.",
        "Shake a leg. The cookies are not walking to you.",
        "If you want the story, earn the steps.",
        "Almost curious. Not almost close.",
        "The pin says hi. It also says walk.",
        "No spoilers from the sidewalk across town.",
        "Move those legs. Twenty-seven looks better in motion.",
        "Ya bum. The details are over there.",
    ]

    static func next(after previous: String?) -> String {
        let choices = all.filter { $0 != previous }
        return choices.randomElement() ?? all[0]
    }
}

struct WalkCloserTaunt: Identifiable {
    let id = UUID()
    let text: String
}

enum HiddenPlacePreview {
    static let defaultsKey = "showHiddenMapItems"
}

enum DiscoveredPlaces {
    private static let key = "discoveredMapMarkerIds"

    static func ids() -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    static func remember(_ id: UUID) {
        var current = ids()
        guard current.insert(id).inserted else { return }
        UserDefaults.standard.set(current.map(\.uuidString).sorted(), forKey: key)
    }
}
