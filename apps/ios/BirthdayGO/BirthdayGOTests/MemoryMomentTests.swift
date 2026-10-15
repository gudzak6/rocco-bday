import Foundation
import Testing
@testable import BirthdayGO

struct MemoryMomentTests {
    @Test func londonMemoryIsAvailableWithoutProximity() {
        let london = MemoryMomentCatalog.entry(id: MemoryMomentCatalog.londonId)
        #expect(london?.title == "London Memories 🇬🇧")
        #expect(london?.locationName == "London, England")
        #expect(london?.caption == "London was never ready for us.")
        #expect(london?.photos.map(\.assetName) == ["LondonMemories"])
        #expect(london?.date == nil)
        #expect(abs((london?.latitude ?? 0) - 51.508039) < 1.5)
        #expect(abs((london?.longitude ?? 0) + 0.128069) < 1.5)
    }

    @Test func centralParkMemoryUsesProvidedPhoto() {
        let park = MemoryMomentCatalog.entry(id: MemoryMomentCatalog.centralParkId)
        #expect(park?.title == "Central Park Memories")
        #expect(park?.locationName == "Central Park, New York")
        #expect(park?.photos.map(\.assetName) == ["CentralParkMemories"])
        #expect(abs((park?.latitude ?? 0) - 40.775347) < 0.02)
        #expect(abs((park?.longitude ?? 0) + 73.970812) < 0.02)
    }

    @Test func allAnticoMemoryUsesProvidedPhotoAndAddress() {
        let shop = MemoryMomentCatalog.entry(id: MemoryMomentCatalog.allAnticoId)
        #expect(shop?.title == "All'Antico Vinaio")
        #expect(shop?.locationName == "729 8th Avenue, New York")
        #expect(shop?.photos.map(\.assetName) == ["AllAnticoMemories"])
        #expect(abs((shop?.latitude ?? 0) - 40.7596992) < 0.002)
        #expect(abs((shop?.longitude ?? 0) + 73.9882202) < 0.002)
    }

    @Test func stoutMemoryUsesProvidedPhotoAndAddress() {
        let stout = MemoryMomentCatalog.entry(id: MemoryMomentCatalog.stoutId)
        #expect(stout?.title == "Stout")
        #expect(stout?.locationName == "109 West 39th Street, New York")
        #expect(stout?.photos.map(\.assetName) == ["StoutMemories"])
        #expect(abs((stout?.latitude ?? 0) - 40.7531121) < 0.002)
        #expect(abs((stout?.longitude ?? 0) + 73.9856854) < 0.002)
    }

    @Test func mergeAddsLondonWithoutDuplicating() {
        let first = MemoryMomentCatalog.merging(.uiTest)
        let second = MemoryMomentCatalog.merging(first)
        #expect(second.locations.filter { $0.title == "London, England" }.count == 1)
        #expect(second.locations.filter { $0.title == "Central Park, New York" }.count == 1)
        #expect(second.locations.filter { $0.title == "729 8th Avenue, New York" }.count == 1)
        #expect(second.locations.filter { $0.title == "109 West 39th Street, New York" }.count == 1)
        #expect(second.locations.contains { $0.id == MemoryMomentCatalog.londonLocationId })
        #expect(second.locations.contains { $0.id == MemoryMomentCatalog.centralParkLocationId })
        #expect(second.locations.contains { $0.id == MemoryMomentCatalog.allAnticoLocationId })
        #expect(second.locations.contains { $0.id == MemoryMomentCatalog.stoutLocationId })
        #expect(!second.characters.contains { $0.name == "London Memories 🇬🇧" })
        #expect(!second.landmarks.contains { $0.title == "London Memories 🇬🇧" })
    }

    @Test func memoryMomentsUseTheirOwnPins() {
        for moment in MemoryMomentCatalog.entries {
            #expect(!CheckpointCatalog.entries.contains { $0.locationId == moment.locationId })
            #expect(!CatCatalog.entries.contains { $0.locationId == moment.locationId })
            for stop in CheckpointCatalog.entries {
                let meters = Proximity.distanceMeters(
                    latitude: moment.latitude, longitude: moment.longitude,
                    targetLatitude: stop.latitude, targetLongitude: stop.longitude
                )
                #expect(meters > 200)
            }
            for cat in CatCatalog.entries {
                let meters = Proximity.distanceMeters(
                    latitude: moment.latitude, longitude: moment.longitude,
                    targetLatitude: cat.latitude, targetLongitude: cat.longitude
                )
                #expect(meters > 200)
            }
        }
    }
}
