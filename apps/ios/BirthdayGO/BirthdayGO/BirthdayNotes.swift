import Foundation
import SwiftData
import SwiftUI

struct BirthdayFriendMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let senderName: String
    let body: String
    var imageAsset: String? = nil

    var initial: String {
        String(senderName.prefix(1))
    }
}

enum BirthdayMessages {
    static let all: [BirthdayFriendMessage] = [
        BirthdayFriendMessage(
            id: UUID(uuidString: "B1DA1001-0000-4000-8000-000000000001")!,
            senderName: "Sharon",
            body: "HAPPY BIRTHDAY ROCCO!!",
            imageAsset: "SharonMessage"
        ),
        BirthdayFriendMessage(
            id: UUID(uuidString: "B1DA1001-0000-4000-8000-000000000003")!,
            senderName: "Mary",
            body: "Happy birthday Rocky!! The big 2-7!! Enjoy your final year of your mid-twenties 😮 Hope you’re having a blast playing this game and that it makes up for the heartbreak of chip city closing. xx Mary",
            imageAsset: "MaryMessage"
        ),
        BirthdayFriendMessage(
            id: UUID(uuidString: "B1DA1001-0000-4000-8000-000000000007")!,
            senderName: "Sheba",
            body: "Happiest of birthdays Rocco!!! Hope this year is the best one yet. Looking forward to more yap session with you in and out of the office. Have the best day ever!",
            imageAsset: "ShebaMessage"
        ),
        BirthdayFriendMessage(
            id: UUID(uuidString: "B1DA1001-0000-4000-8000-000000000004")!,
            senderName: "Joey",
            body: "Happy birthday, Rocco!! Hope you had an amazing birthday and are off to a great start to your 27th year! Wishing you a year filled with lots of adventures, great memories, and of course, plenty of cookies and sweet treats along the way. Hope this is your best year yet!",
            imageAsset: "JoeyMessage"
        ),
        BirthdayFriendMessage(
            id: UUID(uuidString: "B1DA1001-0000-4000-8000-000000000005")!,
            senderName: "Derek",
            body: "HAPPY BIRTHDAY!! Wishing you the happiest 27th to add to what’s already a huge year for ya! Excited for you to try out the game and manifesting a jets win for your bday 🤞🏻",
            imageAsset: "DerekMessage"
        ),
        BirthdayFriendMessage(
            id: UUID(uuidString: "B1DA1001-0000-4000-8000-000000000006")!,
            senderName: "Anya",
            body: "[REPLACE] Placeholder birthday message from Anya. Swap this text later."
        ),
    ]

    static func avatarColor(at index: Int) -> Color {
        let colors = [Color.birthdayPurple, Color.skyBlue, Color.golden, Color.mint]
        return colors[index % colors.count]
    }
}

@Model
final class NotePreference {
    @Attribute(.unique) var noteId: UUID
    var isFavorite: Bool
    var isRead: Bool
    var updatedAt: Date

    init(noteId: UUID, isFavorite: Bool = false, isRead: Bool = false, updatedAt: Date = .now) {
        self.noteId = noteId
        self.isFavorite = isFavorite
        self.isRead = isRead
        self.updatedAt = updatedAt
    }
}

@Model
final class LocalPassportStamp {
    @Attribute(.unique) var stampKey: String
    var earnedAt: Date

    init(stampKey: String, earnedAt: Date = .now) {
        self.stampKey = stampKey
        self.earnedAt = earnedAt
    }
}

enum MemoryPassport {
    static let stamps: [(key: String, title: String, symbol: String)] = [
        ("grand-central", "Grand Central Terminal", "tram.fill"),
        ("penn-station", "Penn Station", "sparkles"),
        ("runcenter", "NYRR RUNCENTER", "figure.run"),
        ("chip-city-rockefeller", "Chip City Rockefeller", "birthday.cake.fill"),
        ("chip-city-chelsea", "Chip City Chelsea", "cup.and.saucer.fill"),
        ("williamsburg", "Williamsburg", "person.2.fill"),
        ("upper-east-side", "Upper East Side", "star.fill"),
    ]

    static func stampKey(forLocationTitle title: String) -> String? {
        stamps.first { $0.title == title }?.key
    }

    static func title(for key: String) -> String {
        stamps.first { $0.key == key }?.title ?? key
    }

    static func symbol(for key: String) -> String {
        stamps.first { $0.key == key }?.symbol ?? "seal.fill"
    }
}

struct BirthdayNoteCard: Identifiable, Hashable {
    let pin: MessagePin
    let letter: FriendMessage?

    var id: UUID { pin.id }
    var isUnlocked: Bool { pin.unlocked || letter != nil }
}

enum BirthdayNoteRules {
    static func isEligible(
        _ pin: MessagePin,
        snapshot: PlayerSnapshot,
        stamps: Set<String>
    ) -> Bool {
        if pin.unlocked { return true }
        let type = pin.unlockType ?? (pin.visibility == "immediate" ? "immediate" : "location")
        let locationOK = pin.locationId == nil || locationSatisfied(pin.locationId, snapshot)
        let characterOK = pin.characterId == nil || snapshot.characters.contains { $0.id == pin.characterId && $0.captured }
        let stampOK = pin.passportStampKey == nil || stamps.contains(pin.passportStampKey!)
        switch type {
        case "immediate": return true
        case "location": return locationOK && pin.locationId != nil
        case "character": return characterOK && pin.characterId != nil
        case "passport": return stampOK && pin.passportStampKey != nil
        default:
            let checks = [
                pin.locationId == nil ? nil : locationOK,
                pin.characterId == nil ? nil : characterOK,
                pin.passportStampKey == nil ? nil : stampOK,
            ].compactMap { $0 }
            guard !checks.isEmpty else { return false }
            return pin.unlockRule == "any" ? checks.contains(true) : checks.allSatisfy { $0 }
        }
    }

    private static func locationSatisfied(_ locationId: UUID?, _ snapshot: PlayerSnapshot) -> Bool {
        guard let locationId else { return true }
        if snapshot.landmarks.contains(where: { $0.locationId == locationId && $0.visited }) { return true }
        if snapshot.characters.contains(where: { $0.locationId == locationId && $0.captured }) { return true }
        return false
    }

    static func spoilerSafeSender(_ pin: MessagePin) -> String {
        if pin.unlocked { return pin.senderName ?? "A friend" }
        if pin.revealSender == true, let name = pin.senderName, !name.isEmpty { return name }
        return "A friend"
    }

    static func spoilerSafePreview(_ pin: MessagePin, letter: FriendMessage?) -> String {
        if let letter {
            let preview = letter.body.trimmingCharacters(in: .whitespacesAndNewlines)
            return preview.count > 90 ? String(preview.prefix(87)) + "…" : preview
        }
        return pin.lockedHint ?? "A birthday wish is sealed until you unlock it."
    }

    static func associationLabel(pin: MessagePin, letter: FriendMessage?, snapshot: PlayerSnapshot?) -> String? {
        if let locationId = letter?.locationId ?? pin.locationId,
           let title = snapshot?.locations.first(where: { $0.id == locationId })?.title {
            return title
        }
        if let characterId = letter?.characterId ?? pin.characterId,
           let name = snapshot?.characters.first(where: { $0.id == characterId })?.name {
            return name
        }
        if let stamp = letter?.passportStampKey ?? pin.passportStampKey {
            return MemoryPassport.title(for: stamp)
        }
        return nil
    }

    static func cards(from snapshot: PlayerSnapshot) -> [BirthdayNoteCard] {
        var seen = Set<UUID>()
        var cards: [BirthdayNoteCard] = snapshot.messagePins.map { pin in
            seen.insert(pin.id)
            return BirthdayNoteCard(pin: pin, letter: snapshot.unlockedMessages.first { $0.id == pin.id })
        }
        for letter in snapshot.unlockedMessages where !seen.contains(letter.id) {
            cards.append(
                BirthdayNoteCard(
                    pin: MessagePin(
                        id: letter.id, locationId: letter.locationId, title: letter.title,
                        senderName: letter.senderName, visibility: "immediate", required: false, unlocked: true,
                        hasPhoto: letter.media.contains { $0.kind == "image" },
                        hasAudio: letter.media.contains { $0.kind == "audio" }
                    ),
                    letter: letter
                )
            )
        }
        return cards.sorted { lhs, rhs in
            if lhs.isUnlocked != rhs.isUnlocked { return lhs.isUnlocked && !rhs.isUnlocked }
            let leftDate = lhs.letter?.unlockedAt ?? .distantPast
            let rightDate = rhs.letter?.unlockedAt ?? .distantPast
            return leftDate > rightDate
        }
    }
}
