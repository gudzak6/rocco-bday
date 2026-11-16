import SwiftUI

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
                QuestPixel.pop()
                if cards.allSatisfy(\.matched) { session.succeed() }
            } else {
                QuestPixel.miss()
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
            QuestPixel.blip()
        }
        publish()
    }

    private func publish() {
        session.hud.primary = "Pairs \(cards.filter(\.matched).count / 2)/6"
        session.hud.secondary = "Attempts \(attempts)"
        session.hud.lives = nil
    }
}

struct MatchCard: Identifiable {
    let id = UUID()
    let pair: Int
    let symbol: String
    var up = false
    var matched = false

    static func deck() -> [MatchCard] {
        let symbols = ["figure.run", "birthday.cake", "heart.fill", "star.fill", "photo", "figure.climbing"]
        return symbols.enumerated().flatMap { index, symbol in
            [MatchCard(pair: index, symbol: symbol), MatchCard(pair: index, symbol: symbol)]
        }.shuffled()
    }
}

struct OrderMemoryGame: View {
    @ObservedObject var session: QuestSession
    private let cards: [(name: String, symbol: String)] = [
        ("Cookie", "birthday.cake.fill"),
        ("Flowers", "camera.macro"),
        ("Note", "envelope.fill"),
        ("Song", "music.note"),
    ]
    private let goal = 6
    @State private var sequence: [Int] = []
    @State private var step = 0
    @State private var misses = 0
    @State private var lit: Int?
    @State private var inputOn = false
    @State private var ended = false
    @State private var prompt = "Watch the order"
    @State private var ticket = UUID()

    var body: some View {
        VStack(spacing: 22) {
            Text(prompt)
                .font(.system(.title3, design: .rounded, weight: .black))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(cards.indices, id: \.self) { index in
                    card(index)
                }
            }
            .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 1, green: 0.94, blue: 0.86))
        .onAppear { publish() }
        .onChange(of: session.phase) { _, phase in
            ticket = UUID()
            lit = nil
            inputOn = false
            guard phase == .playing, !ended else { return }
            if sequence.isEmpty {
                sequence = [Int.random(in: 0..<cards.count)]
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard session.phase == .playing, !ended else { return }
                playSequence()
            }
        }
    }

    private func card(_ index: Int) -> some View {
        let active = lit == index
        return Button {
            tap(index)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: cards[index].symbol)
                    .font(.system(size: 34, weight: .black))
                Text(cards[index].name)
                    .font(.caption.weight(.black))
            }
            .foregroundStyle(active ? Color.white : Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 128)
            .background(active ? Color.birthdayPurple : Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black, lineWidth: 3))
            .scaleEffect(active ? 1.04 : 1)
            .animation(.easeInOut(duration: 0.12), value: active)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cards[index].name)
    }

    private func playSequence() {
        guard session.phase == .playing, !ended, !sequence.isEmpty else { return }
        inputOn = false
        step = 0
        lit = nil
        prompt = "Watch the order"
        publish()
        let stamp = UUID()
        ticket = stamp
        var delay = 0.35
        for card in sequence {
            let shown = card
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard ticket == stamp, session.phase == .playing, !ended else { return }
                lit = shown
                QuestPixel.blip()
            }
            delay += 0.55
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard ticket == stamp, lit == shown else { return }
                lit = nil
            }
            delay += 0.22
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard ticket == stamp, session.phase == .playing, !ended else { return }
            lit = nil
            inputOn = true
            prompt = "Repeat the order"
            publish()
        }
    }

    private func tap(_ index: Int) {
        guard inputOn, session.phase == .playing, !ended, step < sequence.count else { return }
        lit = index
        if index != sequence[step] {
            QuestPixel.miss()
            inputOn = false
            misses += 1
            prompt = misses >= 3 ? "Not this time" : "Watch it again"
            publish()
            if misses >= 3 {
                ended = true
                session.fail()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { playSequence() }
            return
        }
        step += 1
        if step < sequence.count {
            QuestPixel.blip()
            publish()
            return
        }
        QuestPixel.pop()
        inputOn = false
        if sequence.count >= goal {
            ended = true
            prompt = "You remembered"
            publish()
            session.succeed()
            return
        }
        sequence.append(Int.random(in: 0..<cards.count))
        prompt = "Watch the order"
        publish()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { playSequence() }
    }

    private func publish() {
        session.hud.primary = "Order \(sequence.count)/\(goal)"
        session.hud.secondary = prompt
        session.hud.lives = 3 - misses
    }
}

