import SwiftUI

struct QuestMapView: View {
    @EnvironmentObject private var progress: QuestProgress
    @State private var playing: QuestLevel?
    @State private var showBook = false
    @State private var focusedLevel: Int?
    private let stride: CGFloat = 230

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let inset = max(0, geo.size.width / 2 - stride / 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    map(in: geo.size, inset: inset)
                        .frame(width: mapWidth(viewport: geo.size.width), height: geo.size.height)
                }
                .scrollPosition(id: $focusedLevel, anchor: .center)
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
        .onAppear {
            if focusedLevel == nil {
                focusedLevel = QuestRules.currentLevel(completed: progress.completed)
            }
        }
        .fullScreenCover(item: $playing) { level in
            QuestPlayView(level: level) {
                progress.complete(level.number)
            } onClose: {
                let finished = level.number
                let won = progress.completed.contains(finished)
                playing = nil
                guard won else { return }
                let next = min(finished + 1, QuestCatalog.levels.count)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeInOut(duration: 0.9)) {
                        focusedLevel = next
                    }
                }
            }
        }
        .sheet(isPresented: $showBook) {
            QuestMemoryBook(progress: progress)
        }
    }

    private var footer: String {
        let done = progress.completed.count
        if done == 0 { return "Level 1 is open. Clear it to light the next flag." }
        let total = QuestCatalog.levels.count
        if done >= total { return "Every flag is lit. The book is full." }
        return "\(done) of \(total) flags lit. Level \(QuestRules.currentLevel(completed: progress.completed)) is next."
    }

    private func mapWidth(viewport: CGFloat) -> CGFloat {
        viewport + CGFloat(QuestCatalog.levels.count - 1) * stride
    }

    private func map(in size: CGSize, inset: CGFloat) -> some View {
        let spots = QuestCatalog.levels.map { point($0.number, height: size.height, viewport: size.width) }
        return ZStack(alignment: .topLeading) {
            hills(height: size.height)
            path(spots)
            HStack(spacing: 0) {
                ForEach(QuestCatalog.levels) { level in
                    let spot = point(level.number, height: size.height, viewport: size.width)
                    node(level)
                        .offset(y: spot.y - size.height / 2)
                        .frame(width: stride, height: size.height)
                        .id(level.number)
                }
            }
            .padding(.leading, inset)
            .scrollTargetLayout()
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

    private func point(_ number: Int, height: CGFloat, viewport: CGFloat) -> CGPoint {
        let x = viewport / 2 + CGFloat(number - 1) * stride
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
    var unlockedFilenames: [String] = []
    var onContinue: () -> Void
    @State private var opened = false
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var unlockLabel: String {
        unlockedFilenames.count == 1 ? "1 photo unlocked" : "\(unlockedFilenames.count) photos unlocked"
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [level.accent.opacity(0.45), Color.warmWhite], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if !reduceMotion { ConfettiBurst().ignoresSafeArea() }
            ScrollView {
                VStack(spacing: 18) {
                    Text("Level \(level.number) clear")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                    chest
                    if revealed {
                        if !unlockedFilenames.isEmpty {
                            photoNotice
                        }
                        memory
                        Button("Keep going", action: onContinue)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
                .padding(24)
            }
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

    private var photoNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(unlockLabel, systemImage: "photo.on.rectangle.angled")
                .font(.system(.headline, design: .rounded, weight: .black))
            Text("Swipe through them here. They stay on the Birthday Dex.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(unlockedFilenames, id: \.self) { name in
                        if let image = PhotoDropImage.preview(filename: name) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 150, height: 190)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black, lineWidth: 3))
                                .accessibilityLabel("Unlocked photo")
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.black, lineWidth: 3))
        .accessibilityElement(children: .combine)
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
    @State private var selection: UUID?

    private var photos: [PhotoDrop] {
        let byName = Dictionary(uniqueKeysWithValues: PhotoDropCatalog.drops().map { ($0.filename, $0) })
        return progress.unlockedPhotos.compactMap { byName[$0] }
    }

    private var remaining: Int {
        max(PhotoDropCatalog.drops().count - photos.count, 0)
    }

    private var remainingLabel: String {
        remaining == 1 ? "1 photo left to unlock" : "\(remaining) photos left to unlock"
    }

    private var selectedID: UUID? {
        if let selection, photos.contains(where: { $0.id == selection }) { return selection }
        return photos.first?.id
    }

    private var pageLabel: String {
        guard let selectedID, let index = photos.firstIndex(where: { $0.id == selectedID }) else { return "" }
        return "\(index + 1) of \(photos.count)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if photos.isEmpty {
                    Spacer()
                    Text("Win a level and photos from the adventure show up here.")
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
                Text(remainingLabel)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.warmWhite)
            .navigationTitle("Birthday Dex")
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
        .accessibilityLabel("Unlocked photo")
    }
}
