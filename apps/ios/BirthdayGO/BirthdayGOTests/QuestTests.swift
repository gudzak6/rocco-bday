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

    @Test func catalogHasTenLevelsInOrder() {
        #expect(QuestCatalog.levels.map(\.number) == Array(1...10))
        #expect(Set(QuestCatalog.levels.map(\.title)).count == 10)
    }
}

struct QuestPhotoUnlockTests {
    @Test func tenWinsUnlockEveryPhotoExactlyOnce() {
        let names = (1...40).map { "photo-\($0).jpg" }
        var taken = Set<String>()
        var unlocked: [String] = []
        for level in 1...10 {
            let picked = QuestPhotoUnlocks.choose(level: level, filenames: names, taken: taken)
            #expect(picked.count == 4)
            #expect(Set(picked).isDisjoint(with: taken))
            taken.formUnion(picked)
            unlocked.append(contentsOf: picked)
        }
        #expect(unlocked.count == 40)
        #expect(Set(unlocked) == Set(names))
    }
}
