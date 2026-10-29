import Testing
@testable import BirthdayGO

struct QuestUnlockTests {
    @Test func onlyLevelOneStartsOpen() {
        let done: Set<Int> = []
        #expect(QuestRules.isUnlocked(level: 1, completed: done))
        #expect(!QuestRules.isUnlocked(level: 2, completed: done))
        #expect(QuestRules.currentLevel(completed: done) == 1)
    }

    @Test func clearingALevelOpensTheNext() {
        var done: Set<Int> = [1]
        #expect(QuestRules.isUnlocked(level: 2, completed: done))
        #expect(!QuestRules.isUnlocked(level: 3, completed: done))
        done.insert(2)
        #expect(QuestRules.isUnlocked(level: 3, completed: done))
        #expect(QuestRules.currentLevel(completed: done) == 3)
    }

    @Test func catalogHasNineLevelsInOrder() {
        #expect(QuestCatalog.levels.map(\.number) == Array(1...9))
        #expect(Set(QuestCatalog.levels.map(\.title)).count == 9)
        #expect(!QuestCatalog.levels.contains { $0.title == "Rock Climbing Rush" })
    }
}

struct QuestPhotoUnlockTests {
    @Test func everyWinUnlocksPhotosExactlyOnce() {
        let names = (1...40).map { "photo-\($0).jpg" }
        var taken = Set<String>()
        var unlocked: [String] = []
        let count = QuestCatalog.levels.count
        for level in 1...count {
            let picked = QuestPhotoUnlocks.choose(level: level, filenames: names, taken: taken)
            #expect(picked.count == QuestPhotoUnlocks.count(for: level, total: names.count, levels: count))
            #expect(Set(picked).isDisjoint(with: taken))
            taken.formUnion(picked)
            unlocked.append(contentsOf: picked)
        }
        #expect(unlocked.count == 40)
        #expect(Set(unlocked) == Set(names))
    }
}
