import SwiftUI

struct ClimbingGame: View {
    @ObservedObject var session: QuestSession
    @State private var current = 0
    @State private var mistakes = 0

    private let holds: [(id: Int, x: CGFloat, y: CGFloat, unstable: Bool)] = [
        (0, 0.50, 0.08, false),
        (1, 0.30, 0.20, false),
        (2, 0.72, 0.22, true),
        (3, 0.48, 0.33, false),
        (4, 0.24, 0.44, false),
        (5, 0.66, 0.46, true),
        (6, 0.42, 0.58, false),
        (7, 0.70, 0.68, false),
        (8, 0.34, 0.76, false),
        (9, 0.55, 0.88, false),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color.mint.opacity(0.35), Color.warmWhite], startPoint: .top, endPoint: .bottom)
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(red: 0.55, green: 0.62, blue: 0.7))
                    .padding(.horizontal, 36)
                    .padding(.vertical, 24)
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(.black, lineWidth: 4).padding(.horizontal, 36).padding(.vertical, 24))
                ForEach(holds, id: \.id) { hold in
                    holdView(hold, in: geo.size)
                        .position(x: 36 + hold.x * (geo.size.width - 72), y: geo.size.height - 40 - hold.y * (geo.size.height - 80))
                }
            }
        }
        .onAppear { publish() }
        .onChange(of: session.phase) { _, _ in publish() }
    }

    private func holdView(_ hold: (id: Int, x: CGFloat, y: CGFloat, unstable: Bool), in size: CGSize) -> some View {
        let reachable = isReachable(hold.id)
        return Button {
            guard session.phase == .playing else { return }
            if reachable && !hold.unstable {
                current = hold.id
                if hold.id == holds.last?.id { session.succeed() }
            } else {
                mistakes += 1
                if mistakes >= 3 { session.fail() }
            }
            publish()
        } label: {
            Circle()
                .fill(hold.id == current ? Color.golden : (reachable ? Color.mint : Color.white.opacity(0.8)))
                .frame(width: hold.id == current ? 36 : 28, height: hold.id == current ? 36 : 28)
                .overlay(Circle().stroke(.black, lineWidth: 3))
                .shadow(color: reachable && session.phase == .playing ? Color.mint : .clear, radius: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reachable ? "Reachable hold" : "Hold")
    }

    private func isReachable(_ id: Int) -> Bool {
        guard let hold = holds.first(where: { $0.id == id }), let here = holds.first(where: { $0.id == current }) else { return false }
        let dx = hold.x - here.x
        let dy = hold.y - here.y
        return id != current && dy > -0.02 && hypot(dx, dy) < 0.28
    }

    private func publish() {
        guard session.phase == .playing || session.phase == .ready else { return }
        session.primary = "Climb"
        session.secondary = "Reach the gold top"
        session.lives = 3 - mistakes
    }
}

struct LoyaltyGame: View {
    @ObservedObject var session: QuestSession
    @State private var rocco = CGPoint(x: 80, y: 220)
    @State private var carrying: Int?
    @State private var delivered: Set<Int> = []
    @State private var elapsed = 0
    private let friends: [(id: Int, name: String, gift: String, spot: CGPoint, item: CGPoint)] = [
        (0, "Sharon", "Note", CGPoint(x: 300, y: 120), CGPoint(x: 70, y: 80)),
        (1, "Joey", "Cookie", CGPoint(x: 80, y: 420), CGPoint(x: 280, y: 300)),
        (2, "Derek", "Ticket", CGPoint(x: 300, y: 460), CGPoint(x: 160, y: 160)),
    ]

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 360, geo.size.height / 560)
            ZStack {
                Color.warmWhite
                RoundedRectangle(cornerRadius: 24).fill(Color.skyBlue.opacity(0.25)).padding(16)
                ForEach(friends, id: \.id) { friend in
                    marker(friend.gift, at: scaled(friend.item, scale, geo.size), done: carrying == friend.id || delivered.contains(friend.id))
                    VStack(spacing: 2) {
                        Text(friend.name).font(.caption.weight(.black))
                        Text(delivered.contains(friend.id) ? "Helped" : "Needs \(friend.gift)")
                            .font(.caption2.weight(.bold))
                    }
                    .padding(6)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black, lineWidth: 2))
                    .position(scaled(friend.spot, scale, geo.size))
                }
                RoccoSprite(shirt: .golden)
                    .frame(width: 42, height: 56)
                    .position(scaled(rocco, scale, geo.size))
                if let next = friends.first(where: { !delivered.contains($0.id) }) {
                    Image(systemName: "arrow.up")
                        .font(.title2.weight(.black))
                        .foregroundStyle(Color.birthdayPurple)
                        .position(arrowTarget(next, scale, geo.size))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard session.phase == .playing else { return }
                rocco = CGPoint(x: value.location.x / scale, y: (value.location.y - (geo.size.height - 560 * scale) / 2) / scale)
                resolve()
            })
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                guard session.phase == .playing else { return }
                elapsed += 1
                session.primary = "Friends \(delivered.count)/3"
                session.secondary = "\(elapsed)s on the clock"
                session.lives = nil
            }
        }
    }

    private func scaled(_ point: CGPoint, _ scale: CGFloat, _ size: CGSize) -> CGPoint {
        CGPoint(x: (size.width - 360 * scale) / 2 + point.x * scale, y: (size.height - 560 * scale) / 2 + point.y * scale)
    }

    private func arrowTarget(_ friend: (id: Int, name: String, gift: String, spot: CGPoint, item: CGPoint), _ scale: CGFloat, _ size: CGSize) -> CGPoint {
        let target = carrying == friend.id ? friend.spot : friend.item
        return scaled(CGPoint(x: target.x, y: target.y - 36), scale, size)
    }

    private func marker(_ title: String, at point: CGPoint, done: Bool) -> some View {
        Text(done ? "✓" : title)
            .font(.caption.weight(.black))
            .padding(8)
            .background(done ? Color.mint : Color.golden, in: Circle())
            .overlay(Circle().stroke(.black, lineWidth: 2))
            .position(point)
    }

    private func resolve() {
        for friend in friends where !delivered.contains(friend.id) {
            if carrying == nil, hypot(rocco.x - friend.item.x, rocco.y - friend.item.y) < 36 {
                carrying = friend.id
            }
            if carrying == friend.id, hypot(rocco.x - friend.spot.x, rocco.y - friend.spot.y) < 42 {
                delivered.insert(friend.id)
                carrying = nil
                if delivered.count == 3 { session.succeed() }
            }
        }
    }
}

struct MemoryMatchGame: View {
    @ObservedObject var session: QuestSession
    @State private var cards: [MatchCard] = MatchCard.deck()
    @State private var first: Int?
    @State private var attempts = 0
    @State private var lock = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(cards) { card in
                Button { flip(card) } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(card.up || card.matched ? Color.white : Color.birthdayPurple)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: 3))
                        if card.up || card.matched {
                            Image(systemName: card.symbol).font(.title).foregroundStyle(Color.birthdayPurple)
                        } else {
                            Text("?").font(.title.weight(.black)).foregroundStyle(.white)
                        }
                    }
                    .frame(height: 96)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.matched ? "Matched" : "Card")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.warmWhite)
        .onAppear { publish() }
    }

    private func flip(_ card: MatchCard) {
        guard session.phase == .playing, !lock, let index = cards.firstIndex(where: { $0.id == card.id }), !cards[index].up, !cards[index].matched else { return }
        cards[index].up = true
        if let first, first != index {
            attempts += 1
            if cards[first].pair == cards[index].pair {
                cards[first].matched = true
                cards[index].matched = true
                self.first = nil
                if cards.allSatisfy(\.matched) { session.succeed() }
            } else {
                lock = true
                let previous = first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    cards[previous].up = false
                    cards[index].up = false
                    lock = false
                }
                self.first = nil
            }
        } else {
            first = index
        }
        publish()
    }

    private func publish() {
        session.primary = "Pairs \(cards.filter(\.matched).count / 2)/6"
        session.secondary = "Attempts \(attempts)"
        session.lives = nil
    }
}

struct MatchCard: Identifiable {
    let id = UUID()
    let pair: Int
    let symbol: String
    var up = false
    var matched = false

    static func deck() -> [MatchCard] {
        let symbols = ["figure.run", "birthday.cake", "heart.fill", "gamecontroller.fill", "tram.fill", "photo"]
        return symbols.enumerated().flatMap { index, symbol in
            [MatchCard(pair: index, symbol: symbol), MatchCard(pair: index, symbol: symbol)]
        }.shuffled()
    }
}

struct BakeOffGame: View {
    @ObservedObject var session: QuestSession
    private let recipe = ["Cake", "Frosting", "Cookie", "Candle", "Cake", "Frosting", "Cookie", "Candle"]
    @State private var step = 0
    @State private var wobble = false

    var body: some View {
        VStack(spacing: 18) {
            Text(step < recipe.count ? "Next: \(recipe[step])" : "Cake complete")
                .font(.system(.title3, design: .rounded, weight: .black))
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.white).frame(height: 220)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black, lineWidth: 3))
                VStack(spacing: 4) {
                    ForEach(Array(recipe.prefix(step).enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(.caption.weight(.black))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(color(item), in: Capsule())
                    }
                }
                .offset(x: wobble ? 10 : 0)
            }
            .padding(.horizontal, 28)
            HStack(spacing: 10) {
                ForEach(["Cake", "Frosting", "Cookie", "Candle"], id: \.self) { item in
                    Text(item)
                        .font(.caption.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(color(item), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: 3))
                        .draggable(item) {
                            Text(item).padding().background(.white, in: RoundedRectangle(cornerRadius: 8))
                        }
                }
            }
            .padding(.horizontal, 16)
            Color.clear.frame(height: 80)
                .overlay(Text("Drop the next ingredient here").font(.caption.weight(.bold)))
                .dropDestination(for: String.self) { items, _ in
                    guard session.phase == .playing, let item = items.first else { return false }
                    if step < recipe.count, item == recipe[step] {
                        step += 1
                        if step == recipe.count { session.succeed() }
                    } else {
                        withAnimation(.default) { wobble = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { wobble = false }
                    }
                    publish()
                    return true
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 1, green: 0.94, blue: 0.86))
        .onAppear { publish() }
    }

    private func color(_ item: String) -> Color {
        switch item {
        case "Cake": Color(red: 0.95, green: 0.8, blue: 0.55)
        case "Frosting": Color.pink.opacity(0.7)
        case "Cookie": Color.orange.opacity(0.8)
        default: Color.golden
        }
    }

    private func publish() {
        session.primary = "Steps \(step)/8"
        session.secondary = step < recipe.count ? "Add \(recipe[step])" : "Done"
        session.lives = nil
    }
}

struct LegendaryGame: View {
    @ObservedObject var session: QuestSession
    @State private var stage = 0
    @State private var stageToken = 0

    var body: some View {
        VStack(spacing: 8) {
            Text("Stage \(stage + 1) of 4")
                .font(.system(.headline, design: .rounded, weight: .black))
                .padding(.top, 56)
            Group {
                switch stage {
                case 0: LegendRun(playing: session.phase == .playing, token: stageToken) { advance() } fail: { stageToken += 1 }
                case 1: LegendCatch(playing: session.phase == .playing, token: stageToken) { advance() } fail: { stageToken += 1 }
                case 2: LegendClimb(playing: session.phase == .playing, token: stageToken) { advance() } fail: { stageToken += 1 }
                default: LegendGrab(playing: session.phase == .playing) { advance() }
                }
            }
            .id(stageToken + stage * 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color.golden.opacity(0.45), Color.warmWhite], startPoint: .top, endPoint: .bottom))
        .onChange(of: stage) { _, _ in publish() }
        .onAppear { publish() }
    }

    private func advance() {
        guard session.phase == .playing else { return }
        if stage >= 3 { session.succeed() }
        else { stage += 1 }
    }

    private func publish() {
        session.primary = "Stage \(min(stage + 1, 4))/4"
        session.secondary = ["Jump the hurdles", "Catch 6 cookies", "Tap the holds", "Grab the controller"][min(stage, 3)]
        session.lives = nil
    }
}

private struct LegendRun: View {
    var playing: Bool
    var token: Int
    var win: () -> Void
    var fail: () -> Void
    @State private var jumped = false
    @State private var hits = 0
    @State private var cleared = 0
    @State private var obstacleX: CGFloat = 320
    @State private var resolved = false
    @State private var ended = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Color(red: 0.4, green: 0.75, blue: 0.4)).frame(height: 28)
                RoccoSprite(shirt: .golden).frame(width: 40, height: 54)
                    .offset(x: 36, y: jumped ? -70 : -8)
                RoundedRectangle(cornerRadius: 4).fill(.orange).frame(width: 28, height: 36)
                    .offset(x: obstacleX, y: -8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard playing, !jumped else { return }
                withAnimation(.easeOut(duration: 0.18)) { jumped = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { jumped = false }
            }
            .onReceive(Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()) { _ in
                guard playing, !ended else { return }
                obstacleX -= 5
                if obstacleX < 78 && obstacleX > 28 && !jumped && !resolved {
                    hits += 1
                    resolved = true
                }
                if obstacleX < -30 {
                    if !resolved { cleared += 1 }
                    resolved = false
                    obstacleX = geo.size.width + 20
                    if hits >= 3 { ended = true; fail() }
                    else if cleared >= 4 { ended = true; win() }
                }
            }
        }
        .padding(.bottom, 40)
    }
}

private struct LegendCatch: View {
    var playing: Bool
    var token: Int
    var win: () -> Void
    var fail: () -> Void
    @State private var x: CGFloat = 160
    @State private var cookies = 0
    @State private var bad = 0
    @State private var drops: [FallingBit] = []
    @State private var ended = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(drops) { drop in
                    Circle().fill(drop.good ? Color.orange : Color.green).frame(width: 28, height: 28).position(drop.point)
                }
                RoccoSprite(shirt: .orange).frame(width: 40, height: 54).position(CGPoint(x: x, y: geo.size.height - 50))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard playing else { return }
                x = min(max(value.location.x, 30), geo.size.width - 30)
            })
            .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
                guard playing, !ended else { return }
                if drops.count < 4, Int.random(in: 0...6) == 0 {
                    drops.append(FallingBit(good: Int.random(in: 0...3) > 0, point: CGPoint(x: CGFloat.random(in: 20...(geo.size.width - 20)), y: -10)))
                }
                for index in drops.indices { drops[index].point.y += 7 }
                drops.removeAll { bit in
                    let caught = abs(bit.point.x - x) < 36 && bit.point.y > geo.size.height - 80
                    if caught {
                        if bit.good { cookies += 1 } else { bad += 1 }
                    }
                    return caught || bit.point.y > geo.size.height
                }
                if cookies >= 6 { ended = true; win() }
                if bad >= 3 { ended = true; fail() }
            }
        }
    }
}

private struct FallingBit: Identifiable {
    let id = UUID()
    var good: Bool
    var point: CGPoint
}

private struct LegendClimb: View {
    var playing: Bool
    var token: Int
    var win: () -> Void
    var fail: () -> Void
    @State private var step = 0
    @State private var misses = 0
    private let route = [0, 1, 2, 3]

    var body: some View {
        VStack(spacing: 18) {
            Text("Tap the glowing hold").font(.headline.weight(.bold))
            ForEach(route, id: \.self) { hold in
                Button {
                    guard playing else { return }
                    if hold == step {
                        step += 1
                        if step >= route.count { win() }
                    } else {
                        misses += 1
                        if misses >= 3 { fail() }
                    }
                } label: {
                    Circle()
                        .fill(hold == step ? Color.mint : Color.white)
                        .frame(width: 54, height: 54)
                        .overlay(Circle().stroke(.black, lineWidth: 3))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LegendGrab: View {
    var playing: Bool
    var win: () -> Void
    @State private var x: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Text("Tap the controller")
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .position(x: geo.size.width / 2, y: 40)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.golden)
                    .padding(16)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(.black, lineWidth: 3))
                    .position(x: x, y: geo.size.height / 2)
                    .onTapGesture { if playing { win() } }
            }
            .onReceive(Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()) { _ in
                guard playing else { return }
                x += 3
                if x > geo.size.width - 20 { x = 20 }
            }
        }
    }
}
