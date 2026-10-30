import SwiftUI

struct QuestMapView: View {
    @EnvironmentObject private var progress: QuestProgress
    @State private var playing: QuestLevel?
    @State private var showBook = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    map(in: geo.size)
                        .frame(width: 150 + CGFloat(QuestRules.levelCount - 1) * 230 + 180, height: geo.size.height)
                }
            }
            .background(mapSky)
            .navigationTitle("Rocco's Quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button {
                    showBook = true
                } label: {
                    Label("Memories", systemImage: "book.fill")
                }
                .accessibilityLabel("Memory book")
            }
            .safeAreaInset(edge: .bottom) {
                Text(footer)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            }
        }
        .fullScreenCover(item: $playing) { level in
            QuestPlayView(level: level) {
                progress.complete(level.number)
            } onClose: {
                playing = nil
            }
        }
        .sheet(isPresented: $showBook) {
            QuestMemoryBook(progress: progress)
        }
    }

    private var footer: String {
        let done = progress.completed.count
        if done == 0 { return "Level 1 is open. Clear it to light the next flag." }
        if done >= QuestRules.levelCount { return "Every flag is lit. The book is full." }
        return "\(done) of \(QuestRules.levelCount) flags lit. Level \(QuestRules.currentLevel(completed: progress.completed)) is next."
    }

    private func map(in size: CGSize) -> some View {
        let spots = QuestRules.levelRange.map { point($0, height: size.height) }
        return ZStack(alignment: .topLeading) {
            hills(height: size.height)
            path(spots)
            ForEach(QuestCatalog.levels) { level in
                node(level)
                    .position(spots[level.number - 1])
            }
        }
    }

    private var mapSky: some View {
        LinearGradient(colors: [Color.skyBlue.opacity(0.85), Color.warmWhite], startPoint: .top, endPoint: .bottom)
    }

    private func hills(height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 70, height: 36)
                    .offset(x: CGFloat(index) * 300 + 40, y: 28)
            }
            Capsule()
                .fill(Color(red: 0.42, green: 0.78, blue: 0.38))
                .frame(height: height * 0.28)
                .overlay(alignment: .top) {
                    Capsule().fill(Color(red: 0.55, green: 0.86, blue: 0.42)).frame(height: 18)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private func path(_ spots: [CGPoint]) -> some View {
        Path { path in
            guard let first = spots.first else { return }
            path.move(to: first)
            for spot in spots.dropFirst() {
                path.addLine(to: spot)
            }
        }
        .stroke(Color(red: 0.45, green: 0.28, blue: 0.16), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
        .overlay {
            Path { path in
                guard let first = spots.first else { return }
                path.move(to: first)
                for spot in spots.dropFirst() { path.addLine(to: spot) }
            }
            .stroke(Color.golden, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [10, 12]))
        }
        .allowsHitTesting(false)
    }

    private func point(_ number: Int, height: CGFloat) -> CGPoint {
        let x = 150 + CGFloat(number - 1) * 230
        let wave = sin(CGFloat(number) * 0.9) * min(110, height * 0.16)
        return CGPoint(x: x, y: height * 0.46 + wave)
    }

    private func node(_ level: QuestLevel) -> some View {
        let unlocked = progress.isUnlocked(level.number)
        let done = progress.completed.contains(level.number)
        let current = QuestRules.currentLevel(completed: progress.completed) == level.number && !done
        return Button {
            if unlocked { playing = level }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(unlocked ? level.accent : Color.gray.opacity(0.35))
                        .frame(width: 74, height: 74)
                        .overlay(Circle().stroke(Color.black.opacity(0.8), lineWidth: 4))
                        .shadow(color: .black.opacity(0.18), radius: 0, y: 4)
                    if done {
                        Image(systemName: "star.fill")
                            .font(.title2.weight(.black))
                            .foregroundStyle(Color.golden)
                    } else if unlocked {
                        Text("\(level.number)")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    if current {
                        RoccoBadge()
                            .offset(y: -48)
                    }
                }
                Text(level.title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(width: 110)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel("\(level.title), \(done ? "complete" : unlocked ? "open" : "locked")")
    }
}

struct RoccoBadge: View {
    var body: some View {
        RoccoSprite(shirt: .skyBlue)
            .frame(width: 36, height: 48)
            .accessibilityHidden(true)
    }
}

struct RoccoSprite: View {
    var shirt: Color = .skyBlue
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.22, green: 0.14, blue: 0.1)).frame(width: 28, height: 12).offset(y: -8)
                RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.93, green: 0.76, blue: 0.62)).frame(width: 22, height: 18)
                HStack(spacing: 6) {
                    Circle().fill(.black).frame(width: 3, height: 3)
                    Circle().fill(.black).frame(width: 3, height: 3)
                }
                .offset(y: 1)
            }
            .frame(height: 24)
            RoundedRectangle(cornerRadius: 3).fill(shirt).frame(width: 22, height: 16)
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1).fill(.black).frame(width: 6, height: 8)
                RoundedRectangle(cornerRadius: 1).fill(.black).frame(width: 6, height: 8)
            }
        }
    }
}

struct LevelCompleteView: View {
    let level: QuestLevel
    var onContinue: () -> Void
    @State private var opened = false
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [level.accent.opacity(0.45), Color.warmWhite], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if !reduceMotion { ConfettiBurst().ignoresSafeArea() }
            VStack(spacing: 18) {
                Text("Level \(level.number) clear")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                chest
                if revealed {
                    memory
                    Button("Keep going", action: onContinue)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .padding(24)
        }
        .onAppear {
            if reduceMotion {
                opened = true
                revealed = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.25)) { opened = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    withAnimation(.easeOut(duration: 0.35)) { revealed = true }
                }
            }
        }
    }

    private var chest: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.62, green: 0.38, blue: 0.16))
                .frame(width: 120, height: 72)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black, lineWidth: 4))
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.golden)
                .frame(width: 128, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black, lineWidth: 4))
                .offset(y: opened ? -48 : -24)
                .rotationEffect(.degrees(opened ? -28 : 0), anchor: .bottom)
            Circle().fill(Color.golden).frame(width: 16, height: 16).overlay(Circle().stroke(.black, lineWidth: 3))
        }
        .frame(height: 130)
        .accessibilityLabel(opened ? "Treasure chest open" : "Treasure chest")
    }

    private var memory: some View {
        VStack(spacing: 10) {
            if let asset = level.memoryAsset {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black, lineWidth: 3))
            }
            Text(level.memoryTitle)
                .font(.system(.title2, design: .rounded, weight: .black))
            Text(level.memorySender)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(level.memoryBody)
                .font(.body)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.black, lineWidth: 3))
    }
}

struct QuestMemoryBook: View {
    @ObservedObject var progress: QuestProgress
    @Environment(\.dismiss) private var dismiss
    @State private var selected: QuestLevel?

    private var unlocked: [QuestLevel] {
        QuestCatalog.levels.filter { progress.completed.contains($0.number) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if unlocked.isEmpty {
                    ContentUnavailableView("No memories yet", systemImage: "book.closed", description: Text("Clear a level and the page opens here."))
                } else {
                    List(unlocked) { level in
                        Button {
                            selected = level
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(level.memoryTitle)
                                    .font(.system(.headline, design: .rounded, weight: .bold))
                                Text("Level \(level.number) · \(level.memorySender)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Memory Book")
            .toolbar { Button("Done") { dismiss() } }
            .navigationDestination(item: $selected) { level in
                ScrollView {
                    VStack(spacing: 12) {
                        if let asset = level.memoryAsset {
                            Image(asset)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        Text(level.memoryTitle)
                            .font(.system(.title, design: .rounded, weight: .black))
                        Text(level.memorySender)
                            .foregroundStyle(.secondary)
                        Text(level.memoryBody)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
                .navigationTitle("Level \(level.number)")
                .navigationBarTitleDisplayMode(.inline)
                .background(Color.warmWhite)
            }
        }
    }
}

struct BirthdayDexView: View {
    @EnvironmentObject private var progress: QuestProgress

    private var remaining: Int {
        max(PhotoDropCatalog.drops().count - progress.unlockedPhotos.count, 0)
    }

    private var remainingLabel: String {
        remaining == 1 ? "1 photo left to unlock" : "\(remaining) photos left to unlock"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(remainingLabel)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .padding(.horizontal)
                    Text("Each album is a level. Win the flag to open its photos.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    LazyVStack(spacing: 12) {
                        ForEach(QuestCatalog.levels) { level in
                            albumCard(for: level)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical)
            }
            .background(Color.warmWhite)
            .navigationTitle("Birthday Dex")
        }
    }

    @ViewBuilder
    private func albumCard(for level: QuestLevel) -> some View {
        let photos = photos(for: level)
        let isOpen = progress.completed.contains(level.number)
        if isOpen {
            NavigationLink {
                BirthdayDexAlbumView(level: level, photos: photos)
            } label: {
                DexAlbumCard(level: level, photos: photos, isOpen: true)
            }
            .buttonStyle(.plain)
        } else {
            DexAlbumCard(level: level, photos: photos, isOpen: false)
        }
    }

    private func photos(for level: QuestLevel) -> [PhotoDrop] {
        let byName = Dictionary(uniqueKeysWithValues: PhotoDropCatalog.drops().map { ($0.filename, $0) })
        return progress.photos(for: level.number).compactMap { byName[$0] }
    }
}

private struct DexAlbumCard: View {
    let level: QuestLevel
    let photos: [PhotoDrop]
    let isOpen: Bool

    private var expectedCount: Int {
        max(photos.count, QuestPhotoUnlocks.count(for: level.number, total: PhotoDropCatalog.drops().count))
    }

    private var subtitle: String {
        if isOpen {
            return photos.count == 1 ? "1 photo" : "\(photos.count) photos"
        }
        return expectedCount == 1 ? "1 photo waiting" : "\(expectedCount) photos waiting"
    }

    var body: some View {
        HStack(spacing: 14) {
            DexAlbumCover(level: level, photos: photos, isOpen: isOpen)
            VStack(alignment: .leading, spacing: 4) {
                Text("Level \(level.number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(level.accent)
                Text(level.title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: isOpen ? "chevron.right" : "lock.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(isOpen ? Color.secondary : level.accent.opacity(0.7))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(level.accent.opacity(isOpen ? 0.45 : 0.18), lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isOpen ? .isButton : [])
    }

    private var accessibilityText: String {
        if isOpen {
            return "Level \(level.number) \(level.title) album, \(subtitle)"
        }
        return "Level \(level.number) \(level.title) album, locked. Win this level to open it."
    }
}

private struct DexAlbumCover: View {
    let level: QuestLevel
    let photos: [PhotoDrop]
    let isOpen: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(level.accent.opacity(isOpen ? 0.9 : 0.4))
            if isOpen, let name = photos.first?.filename, let image = PhotoDropImage.cover(filename: name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: isOpen ? "photo.on.rectangle.angled" : "lock.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct BirthdayDexAlbumView: View {
    let level: QuestLevel
    let photos: [PhotoDrop]
    @State private var selection: UUID?

    private var selectedID: UUID? {
        if let selection, photos.contains(where: { $0.id == selection }) { return selection }
        return photos.first?.id
    }

    private var pageLabel: String {
        guard let selectedID, let index = photos.firstIndex(where: { $0.id == selectedID }) else { return "" }
        return "\(index + 1) of \(photos.count)"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(level.theme)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(level.accent)
            if photos.isEmpty {
                Spacer()
                Text("This album is open, and photos will land here.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            } else {
                GeometryReader { geo in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(photos) { drop in
                                carouselPage(drop, size: geo.size)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .id(drop.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $selection)
                    .scrollIndicators(.hidden)
                }
                Text(pageLabel)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Photo \(pageLabel)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.warmWhite)
        .navigationTitle(level.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selection == nil {
                selection = photos.first?.id
            }
        }
    }

    private func carouselPage(_ drop: PhotoDrop, size: CGSize) -> some View {
        Group {
            if let image = PhotoDropImage.image(filename: drop.filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width - 32, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel("Photo from \(level.title)")
    }
}
