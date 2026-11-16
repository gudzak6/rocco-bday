import SwiftUI

enum QuestRules {
    static let levelCount = 6
    static var levelRange: ClosedRange<Int> { 1...levelCount }

    static func isUnlocked(level: Int, completed: Set<Int>) -> Bool {
        level == 1 || completed.contains(level - 1)
    }

    static func currentLevel(completed: Set<Int>) -> Int {
        levelRange.first { !completed.contains($0) && isUnlocked(level: $0, completed: completed) } ?? levelCount
    }
}

enum QuestPhotoUnlocks {
    static func count(for level: Int, total: Int, levels: Int = QuestRules.levelCount) -> Int {
        guard total > 0, (1...levels).contains(level) else { return 0 }
        let base = total / levels
        let extra = total % levels
        return base + (level <= extra ? 1 : 0)
    }

    static func choose(level: Int, filenames: [String], taken: Set<String>) -> [String] {
        var pool = filenames.filter { !taken.contains($0) }
        pool.shuffle()
        return Array(pool.prefix(count(for: level, total: filenames.count)))
    }
}

enum QuestPhase: Equatable {
    case ready, countdown, playing, paused, won, lost
}

@MainActor
final class QuestProgress: ObservableObject {
    @Published private(set) var completed: Set<Int>
    @Published private(set) var unlockedPhotos: [String]
    private let key = "roccoQuest.completedLevels"
    private let photosKey = "roccoQuest.photosByLevel"
    private var photoAssignments: [Int: [String]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateProgressIfNeeded(defaults: defaults)
        let saved = defaults.array(forKey: key) as? [Int] ?? []
        let kept = saved.filter { QuestRules.levelRange.contains($0) }
        if kept.count != saved.count {
            defaults.set(kept.sorted(), forKey: key)
        }
        completed = Set(kept)
        photoAssignments = Self.loadAssignments(from: defaults, key: photosKey)
        unlockedPhotos = []
        grantPhotosForCompletedLevels()
    }

    private let defaults: UserDefaults

    func isUnlocked(_ level: Int) -> Bool {
        QuestRules.isUnlocked(level: level, completed: completed)
    }

    func photos(for level: Int) -> [String] {
        photoAssignments[level] ?? []
    }

    func complete(_ level: Int) {
        guard QuestRules.levelRange.contains(level), !completed.contains(level) else { return }
        guard QuestRules.isUnlocked(level: level, completed: completed) else { return }
        completed.insert(level)
        defaults.set(completed.sorted(), forKey: key)
        grantPhotosForCompletedLevels()
    }

    private func grantPhotosForCompletedLevels() {
        let filenames = PhotoDropCatalog.drops().map(\.filename)
        let valid = Set(filenames)
        var next: [Int: [String]] = [:]
        var changed = false
        for (level, names) in photoAssignments {
            guard QuestRules.levelRange.contains(level) else {
                changed = true
                continue
            }
            let cleaned = names.filter(valid.contains)
            if cleaned != names { changed = true }
            if !cleaned.isEmpty { next[level] = cleaned }
        }
        for level in QuestRules.levelRange {
            var have = next[level] ?? []
            let need = QuestPhotoUnlocks.count(for: level, total: filenames.count)
            if have.count < need {
                let taken = Set(next.values.flatMap { $0 })
                var pool = filenames.filter { !taken.contains($0) }
                pool.shuffle()
                have.append(contentsOf: pool.prefix(need - have.count))
                next[level] = have
                changed = true
            }
        }
        var moved = 0
        while moved < 80 {
            moved += 1
            let short = QuestRules.levelRange.first {
                (next[$0]?.count ?? 0) < QuestPhotoUnlocks.count(for: $0, total: filenames.count)
            }
            let fat = QuestRules.levelRange.last {
                (next[$0]?.count ?? 0) > QuestPhotoUnlocks.count(for: $0, total: filenames.count)
            }
            guard let short, let fat, var from = next[fat], let name = from.popLast() else { break }
            next[fat] = from
            var into = next[short] ?? []
            into.append(name)
            next[short] = into
            changed = true
        }
        if changed {
            photoAssignments = next
            saveAssignments()
        } else {
            photoAssignments = next
        }
        unlockedPhotos = QuestRules.levelRange.flatMap { photoAssignments[$0] ?? [] }
    }

    private func saveAssignments() {
        let raw = Dictionary(uniqueKeysWithValues: photoAssignments.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: photosKey)
        }
    }

    private static func migrateProgressIfNeeded(defaults: UserDefaults) {
        let versionKey = "roccoQuest.progressVersion"
        let version = defaults.integer(forKey: versionKey)
        guard version < 3 else { return }
        var levels = Set(defaults.array(forKey: "roccoQuest.completedLevels") as? [Int] ?? [])
        var photos = loadAssignments(from: defaults, key: "roccoQuest.photosByLevel")
        if version < 2 {
            levels = Set(levels.compactMap(remapRetiredLevel))
            var remapped: [Int: [String]] = [:]
            for (level, names) in photos {
                if let mapped = remapRetiredLevel(level), remapped[mapped] == nil {
                    remapped[mapped] = names
                }
            }
            photos = remapped
        }
        var shiftedLevels = Set<Int>()
        for level in levels {
            if level < 3 { shiftedLevels.insert(level) }
            else if level > 3 { shiftedLevels.insert(level - 1) }
        }
        var shiftedPhotos: [Int: [String]] = [:]
        for (level, names) in photos {
            if level < 3 { shiftedPhotos[level] = names }
            else if level > 3 { shiftedPhotos[level - 1] = names }
        }
        defaults.set(shiftedLevels.sorted(), forKey: "roccoQuest.completedLevels")
        let raw = Dictionary(uniqueKeysWithValues: shiftedPhotos.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: "roccoQuest.photosByLevel")
        }
        defaults.set(3, forKey: versionKey)
    }

    private static func remapRetiredLevel(_ level: Int) -> Int? {
        switch level {
        case 1, 2, 3, 4: level
        case 8: 5
        case 9: 6
        case 10: 7
        default: nil
        }
    }

    private static func loadAssignments(from defaults: UserDefaults, key: String) -> [Int: [String]] {
        guard let data = defaults.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        var map: [Int: [String]] = [:]
        for (level, names) in raw {
            if let number = Int(level) { map[number] = names }
        }
        return map
    }
}

@MainActor
final class QuestHUD: ObservableObject {
    @Published var primary = ""
    @Published var secondary = ""
    @Published var lives: Int?

    func reset() {
        primary = ""
        secondary = ""
        lives = nil
    }
}

@MainActor
final class QuestSession: ObservableObject {
    @Published var phase: QuestPhase = .ready
    @Published var countdown = 3
    @Published var runID = UUID()
    let hud = QuestHUD()
    private var countdownTask: Task<Void, Never>?

    func startCountdown() {
        guard phase == .ready || phase == .paused else { return }
        countdownTask?.cancel()
        phase = .countdown
        countdown = 3
        countdownTask = Task { @MainActor in
            for tick in [3, 2, 1] {
                if Task.isCancelled { return }
                countdown = tick
                try? await Task.sleep(nanoseconds: 650_000_000)
            }
            if Task.isCancelled { return }
            phase = .playing
        }
    }

    func pause() {
        guard phase == .playing else { return }
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .playing
    }

    func succeed() {
        guard phase == .playing else { return }
        phase = .won
    }

    func fail() {
        guard phase == .playing else { return }
        phase = .lost
    }

    func retry() {
        countdownTask?.cancel()
        phase = .ready
        hud.reset()
        runID = UUID()
    }
}

struct QuestLevel: Identifiable, Hashable {
    let number: Int
    let title: String
    let theme: String
    let instructions: String
    let accentName: String
    let memorySender: String
    let memoryTitle: String
    let memoryBody: String
    let memoryAsset: String?

    var id: Int { number }

    var accent: Color {
        switch accentName {
        case "sky": .skyBlue
        case "gold": .golden
        case "mint": .mint
        case "pink": Color(red: 0.98, green: 0.45, blue: 0.62)
        case "orange": Color(red: 0.95, green: 0.55, blue: 0.25)
        default: .birthdayPurple
        }
    }
}

enum QuestCatalog {
    static let levels: [QuestLevel] = [
        QuestLevel(
            number: 1,
            title: "Marathon Madness",
            theme: "NYC marathon",
            instructions: "Rocco runs on his own. Tap to jump, and double-tap for a higher jump. Clear cones and puddles with a hop, and hurdles with the higher jump. Reach 500 meters and collect 5 energy gels. Three hits ends the run.",
            accentName: "sky",
            memorySender: "Sharon",
            memoryTitle: "HAPPY BIRTHDAY ROCCO!!",
            memoryBody: "HAPPY BIRTHDAY ROCCO!!",
            memoryAsset: "SharonMessage"
        ),
        QuestLevel(
            number: 2,
            title: "Cookie Chaos",
            theme: "Cookie bakery",
            instructions: "Drag Rocco to catch falling cookies. Broccoli and burnt cookies are out. Collect 20 cookies. Three bad catches end the round.",
            accentName: "orange",
            memorySender: "Joey",
            memoryTitle: "Plenty of cookies",
            memoryBody: "Happy birthday, Rocco!! Hope you had an amazing birthday and are off to a great start to your 27th year! Wishing you a year filled with lots of adventures, great memories, and of course, plenty of cookies and sweet treats along the way. Hope this is your best year yet!",
            memoryAsset: "JoeyMessage"
        ),
        QuestLevel(
            number: 3,
            title: "Boyfriend of the Year",
            theme: "Date-night sky",
            instructions: "Press Left or Right to run, and press Jump to hop. Collect 10 hearts and reach the date-night door. Three falls or bumps ends the date.",
            accentName: "pink",
            memorySender: "Sheba",
            memoryTitle: "Show up",
            memoryBody: "Happiest of birthdays Rocco!!! Hope this year is the best one yet. Looking forward to more yap session with you in and out of the office. Have the best day ever!",
            memoryAsset: "ShebaMessage"
        ),
        QuestLevel(
            number: 4,
            title: "Memory Lane",
            theme: "Scrapbook room",
            instructions: "Tap cards to flip them. Find all 6 pairs. There is no fail state. Attempts are just part of the story.",
            accentName: "gold",
            memorySender: "Mary",
            memoryTitle: "A page from the book",
            memoryBody: "Happy birthday Rocky!! The big 2-7!! Enjoy your final year of your mid-twenties 😮 Hope you’re having a blast playing this game and that it makes up for the heartbreak of chip city closing. xx Mary",
            memoryAsset: "MaryMessage"
        ),
        QuestLevel(
            number: 5,
            title: "Remember This",
            theme: "Four cards",
            instructions: "Watch the four cards light up, then tap them in that order. The pattern grows to 6. A miss plays the same pattern again. Three misses end the round.",
            accentName: "orange",
            memorySender: "Everyone",
            memoryTitle: "Birthday wishes",
            memoryBody: "Sharon, Mary, Sheba, Joey, and Derek saved you a seat, a cookie, and a note. Happy birthday, Rocco.",
            memoryAsset: nil
        ),
        QuestLevel(
            number: 6,
            title: "The Legendary Rocco",
            theme: "Cookie maze",
            instructions: "Tap an arrow or swipe. Rocco stays still until you steer, then keeps going and turns at the next opening. A reverse is instant. Eat every cookie. A big cookie makes the chasers run, and you can eat them while they are scared. Three catches end the run.",
            accentName: "gold",
            memorySender: "Birthday GO",
            memoryTitle: "The Legendary Rocco",
            memoryBody: "Six levels, one birthday, and a city full of people who showed up. This card is yours.",
            memoryAsset: "ProfileCard"
        ),
    ]

    static func level(_ number: Int) -> QuestLevel {
        levels.first { $0.number == number } ?? levels[0]
    }
}
