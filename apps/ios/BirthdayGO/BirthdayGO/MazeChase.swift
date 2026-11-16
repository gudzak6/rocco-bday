import SpriteKit
import UIKit

enum MazeHeading: CaseIterable, Equatable {
    case up, down, left, right

    var vector: (dx: CGFloat, dy: CGFloat) {
        switch self {
        case .up: (0, -1)
        case .down: (0, 1)
        case .left: (-1, 0)
        case .right: (1, 0)
        }
    }

    var opposite: MazeHeading {
        switch self {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }

    var priority: Int {
        switch self {
        case .up: 0
        case .left: 1
        case .down: 2
        case .right: 3
        }
    }

    /// SpriteKit rotation for a mouth drawn pointing right. Scene +y is up.
    var rotation: CGFloat {
        switch self {
        case .right: 0
        case .up: .pi / 2
        case .left: .pi
        case .down: -.pi / 2
        }
    }

    func offset(_ point: CGPoint, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + vector.dx * distance, y: point.y + vector.dy * distance)
    }

    func along(from: CGPoint, to: CGPoint) -> CGFloat {
        (to.x - from.x) * vector.dx + (to.y - from.y) * vector.dy
    }

    static func upcomingCenter(from point: CGPoint, heading: MazeHeading) -> CGPoint {
        switch heading {
        case .right:
            CGPoint(x: floor(point.x) + 1, y: round(point.y))
        case .left:
            CGPoint(x: ceil(point.x) - 1, y: round(point.y))
        case .down:
            CGPoint(x: round(point.x), y: floor(point.y) + 1)
        case .up:
            CGPoint(x: round(point.x), y: ceil(point.y) - 1)
        }
    }
}

struct MazeMover {
    var position: CGPoint
    var current: MazeHeading
    var requested: MazeHeading
    var speed: CGFloat

    /// Moves continuously in tile units. A requested turn is taken as soon as that
    /// exit is open from the current tile. A reverse happens immediately.
    mutating func advance(dt: CGFloat, blocked: (CGPoint) -> Bool, onCenter: ((CGPoint, MazeHeading) -> MazeHeading?)? = nil) {
        takeQueuedTurn(blocked: blocked)
        var budget = max(0, speed * dt)
        var hops = 0
        while budget > 0.00001 && hops < 6 {
            hops += 1
            if requested == current.opposite {
                current = requested
            }
            let next = MazeHeading.upcomingCenter(from: position, heading: current)
            if blocked(next) {
                let stop = CGPoint(x: next.x - current.vector.dx, y: next.y - current.vector.dy)
                let dist = current.along(from: position, to: stop)
                if dist > 0.0001 {
                    position = current.offset(position, min(budget, dist))
                } else {
                    position = stop
                }
                let heading = current
                takeQueuedTurn(blocked: blocked)
                if current != heading { continue }
                budget = 0
                break
            }
            let dist = current.along(from: position, to: next)
            if dist <= 0 {
                let nudge = min(budget, 0.001)
                position = current.offset(position, nudge)
                budget -= nudge
                continue
            }
            if dist > budget {
                position = current.offset(position, budget)
                budget = 0
                continue
            }
            position = CGPoint(x: round(next.x), y: round(next.y))
            budget -= dist
            if let turn = onCenter?(position, current) {
                requested = turn
            }
            takeQueuedTurn(blocked: blocked)
        }
    }

    private mutating func takeQueuedTurn(blocked: (CGPoint) -> Bool) {
        guard requested != current else { return }
        if requested == current.opposite {
            current = requested
            return
        }
        let center = CGPoint(x: round(position.x), y: round(position.y))
        guard abs(position.x - center.x) < 0.5, abs(position.y - center.y) < 0.5 else { return }
        guard !blocked(requested.offset(center, 1)) else { return }
        position = center
        current = requested
    }
}

final class MazeScene: QuestArcadeScene {
    var cookiesEaten = 0
    var cookieTotal = 0
    var hits = 0
    var hint = "Clear the maze"

    private let columns = 15
    private let rows = 17
    private let step = 1.0 / 120.0
    private let playerSpeed: CGFloat = 4.7
    private let chaseSpeed: CGFloat = 4.15
    private let scaredSpeed: CGFloat = 2.7
    private let eyeSpeed: CGFloat = 6.0
    private let topInset: CGFloat = 102
    private let bottomInset: CGFloat = 196

    private var walls: Set<MazeTile> = []
    private var wallNodes: [SKSpriteNode] = []
    private var cookieNodes: [MazeTile: SKSpriteNode] = [:]
    private var remaining: Set<MazeTile> = []
    private var powers: Set<MazeTile> = []
    private var player = MazeMover(position: .zero, current: .right, requested: .right, speed: 4.7)
    private var started = false
    private var chasers: [Chaser] = []
    private var sparks: [Spark] = []
    private var playerNode = SKSpriteNode()
    private var tile: CGFloat = 24
    private var origin = CGPoint.zero
    private var accumulator = 0.0
    private var simTime: CGFloat = 0
    private var chomp: CGFloat = 0
    private var fright: CGFloat = 0
    private var invuln: CGFloat = 0
    private var finish = -1.0 as CGFloat
    private var finishWin = false
    private var built = false
    private var skipLerp = false
    private var playerFrom = CGPoint.zero
    private var strokeLast: CGPoint?
    private let start = CGPoint(x: 1, y: 1)
    private let home = CGPoint(x: 7, y: 9)
    private let map = [
        "###############",
        "#P.....#.....o#",
        "#.###.#.#.###.#",
        "#.#.........#.#",
        "#.#.###.###.#.#",
        "#o....#.#....o#",
        "###.#.#.#.#.###",
        "#...#.....#...#",
        "#.#.###.###.#.#",
        "#.#....H....#.#",
        "#.#.###.###.#.#",
        "#...#.....#...#",
        "###.#.#.#.#.###",
        "#o....#.#....o#",
        "#.#.###.###.#.#",
        "#.#.........#.#",
        "###############",
    ]

    override func setRunning(_ on: Bool) {
        super.setRunning(on)
        if !on {
            accumulator = 0
            lastTime = 0
        }
    }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 120
        view.ignoresSiblingOrder = true
        backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.14, alpha: 1)
        guard !built else {
            layout()
            render(alpha: 1)
            return
        }
        built = true
        build()
        layout()
        render(alpha: 1)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard built else { return }
        layout()
        render(alpha: 1)
    }

    override func update(_ currentTime: TimeInterval) {
        guard running, outcome == 0 else {
            lastTime = 0
            accumulator = 0
            return
        }
        if lastTime == 0 {
            lastTime = currentTime
            return
        }
        var frame = currentTime - lastTime
        lastTime = currentTime
        if frame < 0 { frame = 0 }
        if frame > 0.05 { frame = 0.05 }
        accumulator += frame
        var ticks = 0
        while accumulator >= step && ticks < 6 {
            playerFrom = player.position
            for chaser in chasers { chaser.from = chaser.mover.position }
            simulate(CGFloat(step))
            if player.current != playerHeadingBeforeStep {
                playerFrom = player.position
            }
            accumulator -= step
            ticks += 1
        }
        let alpha: CGFloat = skipLerp ? 1 : CGFloat(accumulator / step)
        skipLerp = false
        render(alpha: alpha)
    }

    private var playerHeadingBeforeStep: MazeHeading = .right

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        strokeLast = touches.first?.location(in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        steer(toward: point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let point = touches.first?.location(in: self) { steer(toward: point) }
        strokeLast = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        strokeLast = nil
    }

    @discardableResult
    func queue(_ heading: MazeHeading) -> Bool {
        let open = !isBlocked(heading.offset(player.position, 1))
        if !started {
            guard open else { return false }
            started = true
            player.current = heading
            player.requested = heading
            return true
        }
        player.requested = heading
        return true
    }

    private func steer(toward point: CGPoint) {
        guard let last = strokeLast else {
            strokeLast = point
            return
        }
        let dx = point.x - last.x
        let dy = point.y - last.y
        guard hypot(dx, dy) >= 12 else { return }
        player.requested = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)
        strokeLast = point
    }

    private func build() {
        var cookieCount = 0
        for (y, row) in map.enumerated() {
            for (x, tile) in row.enumerated() {
                let cell = MazeTile(x: x, y: y)
                switch tile {
                case "#":
                    walls.insert(cell)
                    let wall = SKSpriteNode(texture: MazeArt.wall)
                    wall.zPosition = 0
                    addChild(wall)
                    wallNodes.append(wall)
                case ".", "o":
                    let node = SKSpriteNode(texture: tile == "o" ? MazeArt.power : MazeArt.dot)
                    node.zPosition = 1
                    node.name = tile == "o" ? "power" : "dot"
                    addChild(node)
                    cookieNodes[cell] = node
                    remaining.insert(cell)
                    if tile == "o" { powers.insert(cell) }
                    cookieCount += 1
                default:
                    break
                }
            }
        }
        cookieTotal = cookieCount
        player = MazeMover(position: start, current: .right, requested: .right, speed: playerSpeed)
        playerFrom = start
        playerNode = SKSpriteNode(texture: MazeArt.mouths[0])
        playerNode.zPosition = 4
        addChild(playerNode)

        let spawns: [(CGPoint, MazeHeading, CGPoint)] = [
            (CGPoint(x: 7, y: 9), .up, CGPoint(x: 13, y: 1)),
            (CGPoint(x: 6, y: 9), .left, CGPoint(x: 1, y: 1)),
            (CGPoint(x: 8, y: 9), .right, CGPoint(x: 13, y: 15)),
        ]
        for (index, spawn) in spawns.enumerated() {
            let chaser = Chaser(index: index, position: spawn.0, heading: spawn.1, corner: spawn.2, hold: 0.35 + CGFloat(index) * 0.85)
            addChild(chaser.root)
            chasers.append(chaser)
        }
        for _ in 0..<24 {
            let spark = Spark()
            spark.node.isHidden = true
            addChild(spark.node)
            sparks.append(spark)
        }
    }

    private func layout() {
        let availW = max(40, size.width - 12)
        let availH = max(40, size.height - topInset - bottomInset)
        tile = min(availW / CGFloat(columns), availH / CGFloat(rows))
        origin = CGPoint(
            x: (size.width - CGFloat(columns) * tile) / 2 + tile * 0.5,
            y: size.height - topInset - tile * 0.5
        )
        var wallIndex = 0
        for y in 0..<rows {
            for x in 0..<columns where walls.contains(MazeTile(x: x, y: y)) {
                guard wallIndex < wallNodes.count else { break }
                let node = wallNodes[wallIndex]
                node.position = viewPoint(CGPoint(x: x, y: y))
                node.size = CGSize(width: tile + 0.6, height: tile + 0.6)
                wallIndex += 1
            }
        }
        for (cell, node) in cookieNodes {
            node.position = viewPoint(CGPoint(x: cell.x, y: cell.y))
            let side = powers.contains(cell) ? tile * 0.34 : tile * 0.15
            node.size = CGSize(width: side, height: side)
        }
        playerNode.size = CGSize(width: tile * 0.78, height: tile * 0.78)
        for chaser in chasers {
            chaser.layout(tile: tile)
        }
        for spark in sparks {
            spark.node.size = CGSize(width: tile * 0.16, height: tile * 0.16)
        }
    }

    private func simulate(_ dt: CGFloat) {
        simTime += dt
        if finish >= 0 {
            finish -= dt
            if finish <= 0 { outcome = finishWin ? 1 : 2 }
            return
        }
        if fright > 0 {
            fright -= dt
            if fright <= 0 {
                fright = 0
                hint = "Clear the maze"
                for chaser in chasers where chaser.mode == .frightened {
                    chaser.mode = .chase
                }
            }
        }
        if invuln > 0 { invuln -= dt }
        guard started else { return }
        for spark in sparks where spark.life > 0 {
            spark.life -= dt
            spark.node.position.x += spark.velocity.x * dt
            spark.node.position.y += spark.velocity.y * dt
            spark.node.alpha = max(0, spark.life / 0.34)
            if spark.life <= 0 { spark.node.isHidden = true }
        }

        let playerStart = player.position
        playerHeadingBeforeStep = player.current
        player.advance(dt: dt, blocked: isBlocked)
        let traveled = hypot(player.position.x - playerStart.x, player.position.y - playerStart.y)
        if traveled > 0.0001 { chomp += traveled * 9 }
        collect(from: playerStart, to: player.position)
        guard outcome == 0, finish < 0 else { return }

        for chaser in chasers {
            chaser.blend += ((chaser.mode == .frightened ? 1 : 0) - chaser.blend) * min(1, dt / 0.12)
            if chaser.hold > 0 {
                chaser.hold -= dt
                if chaser.hold <= 0 { chaser.mover.position = chaser.spawn }
                continue
            }
            chaser.mover.speed = chaser.mode == .eyes ? eyeSpeed : (chaser.mode == .frightened ? scaredSpeed : chaseSpeed)
            if chaser.mode == .chase {
                chaser.aim = CGPoint(x: round(player.position.x), y: round(player.position.y))
            }
            let before = chaser.mover.current
            chaser.stepStart = chaser.mover.position
            chaser.mover.advance(dt: dt, blocked: isBlocked) { center, heading in
                self.decide(chaser, at: center, heading: heading)
            }
            if chaser.mover.current != before {
                chaser.from = chaser.mover.position
            }
            if chaser.mode == .eyes {
                let dx = chaser.mover.position.x - home.x
                let dy = chaser.mover.position.y - home.y
                if dx * dx + dy * dy < 0.014 {
                    chaser.mover.position = home
                    chaser.mover.current = .up
                    chaser.mover.requested = .up
                    chaser.mode = fright > 0 ? .frightened : .chase
                    chaser.hold = 0.45
                    chaser.from = home
                }
            }
        }
        guard finish < 0 else { return }
        collide(playerStart: playerStart)
    }

    private func decide(_ chaser: Chaser, at center: CGPoint, heading: MazeHeading) -> MazeHeading? {
        let options = openHeadings(at: center, heading: heading)
        if options == [heading] { return heading }
        let flee = chaser.mode == .frightened
        return best(options, from: center, toward: chaser.aim, flee: flee)
    }

    private func collect(from start: CGPoint, to end: CGPoint) {
        let minX = Int(floor(min(start.x, end.x))) - 1
        let maxX = Int(ceil(max(start.x, end.x))) + 1
        let minY = Int(floor(min(start.y, end.y))) - 1
        let maxY = Int(ceil(max(start.y, end.y))) + 1
        var eaten: [MazeTile] = []
        for cell in remaining where cell.x >= minX && cell.x <= maxX && cell.y >= minY && cell.y <= maxY {
            let point = CGPoint(x: cell.x, y: cell.y)
            if MazeMath.distance(point, toSegment: start, end) <= 0.34 {
                eaten.append(cell)
            }
        }
        for cell in eaten {
            remaining.remove(cell)
            cookieNodes[cell]?.isHidden = true
            cookiesEaten = cookieTotal - remaining.count
            if powers.contains(cell) {
                powers.remove(cell)
                beginFright()
                burst(at: viewPoint(CGPoint(x: cell.x, y: cell.y)), color: UIColor(red: 1, green: 0.84, blue: 0.3, alpha: 1), count: 8)
                QuestPixel.blip()
            }
        }
        if remaining.isEmpty && finish < 0 {
            finish = 0.42
            finishWin = true
            hint = "Maze clear"
        }
    }

    private func beginFright() {
        fright = 6
        hint = "Chasers are scared"
        let corners = [CGPoint(x: 1, y: 1), CGPoint(x: 13, y: 1), CGPoint(x: 1, y: 15), CGPoint(x: 13, y: 15)]
        for (index, chaser) in chasers.enumerated() where chaser.mode != .eyes {
            chaser.mode = .frightened
            chaser.aim = corners[index % corners.count]
            let reverse = chaser.mover.current.opposite
            chaser.mover.current = reverse
            chaser.mover.requested = reverse
        }
    }

    private func collide(playerStart: CGPoint) {
        guard invuln <= 0 else { return }
        for chaser in chasers where chaser.mode != .eyes && chaser.hold <= 0 {
            let hit = MazeMath.sweptHit(
                playerStart, player.position,
                chaser.stepStart, chaser.mover.position,
                radius: 0.68
            )
            guard hit else { continue }
            if chaser.mode == .frightened {
                chaser.mode = .eyes
                chaser.aim = home
                chaser.mover.requested = chaser.mover.current
                burst(at: viewPoint(chaser.mover.position), color: .white, count: 6)
                QuestPixel.blip()
            } else if chaser.mode == .chase {
                hits += 1
                if hits >= 3 {
                    finish = 0.4
                    finishWin = false
                    hint = "Caught"
                } else {
                    respawn()
                }
                return
            }
        }
    }

    private func respawn() {
        invuln = 1.55
        fright = 0
        hint = "Clear the maze"
        player.position = start
        player.current = .right
        player.requested = .right
        playerFrom = start
        skipLerp = true
        for chaser in chasers {
            chaser.mover.position = chaser.spawn
            chaser.mover.current = chaser.spawnHeading
            chaser.mover.requested = chaser.spawnHeading
            chaser.mode = .chase
            chaser.hold = 0.4
            chaser.from = chaser.spawn
            chaser.blend = 0
        }
    }

    private func render(alpha: CGFloat) {
        let clamped = min(1, max(0, alpha))
        let playerPoint = MazeMath.lerp(playerFrom, player.position, clamped)
        playerNode.position = viewPoint(playerPoint)
        playerNode.zRotation = player.current.rotation
        let moving = hypot(player.position.x - playerFrom.x, player.position.y - playerFrom.y) > 0.0008
        let frame = moving ? Int((sin(chomp) * 0.5 + 0.5) * CGFloat(MazeArt.mouths.count - 1)) : 0
        playerNode.texture = MazeArt.mouths[min(frame, MazeArt.mouths.count - 1)]
        let bite: CGFloat = finish >= 0 && finishWin ? 1.18 : 1
        playerNode.setScale(bite)
        if invuln > 0 {
            playerNode.alpha = sin(simTime * 28) > 0 ? 0.35 : 1
        } else {
            playerNode.alpha = 1
        }
        for chaser in chasers {
            let point = MazeMath.lerp(chaser.from, chaser.mover.position, clamped)
            chaser.root.position = viewPoint(point)
            chaser.applyLook(tile: tile, frightened: fright > 0 && fright < 1.4 && Int(simTime * 8) % 2 == 0)
        }
        let pulse = 1 + 0.08 * sin(simTime * 6)
        for cell in powers {
            cookieNodes[cell]?.setScale(pulse)
        }
    }

    private func burst(at point: CGPoint, color: UIColor, count: Int) {
        var spawned = 0
        for spark in sparks where spark.life <= 0 {
            let angle = CGFloat(spawned) / CGFloat(count) * .pi * 2
            spark.life = 0.34
            spark.velocity = CGPoint(x: cos(angle) * 110, y: sin(angle) * 110)
            spark.node.position = point
            spark.node.isHidden = false
            spark.node.alpha = 1
            spark.node.color = color
            spark.node.colorBlendFactor = 1
            spawned += 1
            if spawned == count { break }
        }
    }

    private func openHeadings(at center: CGPoint, heading: MazeHeading) -> [MazeHeading] {
        let open = MazeHeading.allCases.filter { !isBlocked($0.offset(center, 1)) }
        let forward = open.filter { $0 != heading.opposite }
        return forward.isEmpty ? open : forward
    }

    private func best(_ options: [MazeHeading], from center: CGPoint, toward aim: CGPoint, flee: Bool) -> MazeHeading {
        options.min { a, b in
            let da = MazeMath.manhattan(a.offset(center, 1), aim)
            let db = MazeMath.manhattan(b.offset(center, 1), aim)
            if abs(da - db) > 0.001 { return flee ? da > db : da < db }
            return a.priority < b.priority
        } ?? .right
    }

    private func isBlocked(_ point: CGPoint) -> Bool {
        let x = Int(round(point.x))
        let y = Int(round(point.y))
        if x < 0 || y < 0 || x >= columns || y >= rows { return true }
        return walls.contains(MazeTile(x: x, y: y))
    }

    private func viewPoint(_ grid: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + grid.x * tile, y: origin.y - grid.y * tile)
    }
}

private struct MazeTile: Hashable {
    var x: Int
    var y: Int
}

private enum MazeMath {
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    static func manhattan(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    static func distance(_ point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let abx = end.x - start.x
        let aby = end.y - start.y
        let len2 = abx * abx + aby * aby
        if len2 < 0.0000001 { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(1, max(0, ((point.x - start.x) * abx + (point.y - start.y) * aby) / len2))
        return hypot(point.x - (start.x + abx * t), point.y - (start.y + aby * t))
    }

    static func sweptHit(_ a0: CGPoint, _ a1: CGPoint, _ b0: CGPoint, _ b1: CGPoint, radius: CGFloat) -> Bool {
        let start = CGPoint(x: a0.x - b0.x, y: a0.y - b0.y)
        let end = CGPoint(x: a1.x - b1.x, y: a1.y - b1.y)
        return distance(.zero, toSegment: start, end) < radius
    }
}

@MainActor
private final class Chaser {
    var mover: MazeMover
    var hold: CGFloat
    var mode: Mode
    var aim: CGPoint
    var blend: CGFloat
    var from: CGPoint
    var stepStart: CGPoint
    let spawn: CGPoint
    let spawnHeading: MazeHeading
    let root: SKNode
    let body: SKSpriteNode
    let scared: SKSpriteNode
    let pupils: [SKSpriteNode]

    enum Mode {
        case chase, frightened, eyes
    }

    init(index: Int, position: CGPoint, heading: MazeHeading, corner: CGPoint, hold: CGFloat) {
        mover = MazeMover(position: position, current: heading, requested: heading, speed: 6.35)
        self.hold = hold
        mode = .chase
        aim = corner
        blend = 0
        from = position
        stepStart = position
        spawn = position
        spawnHeading = heading
        let node = SKNode()
        root = node
        body = SKSpriteNode(texture: MazeArt.bodies[index % MazeArt.bodies.count])
        scared = SKSpriteNode(texture: MazeArt.scared)
        scared.alpha = 0
        body.zPosition = 3
        scared.zPosition = 3.1
        node.addChild(body)
        node.addChild(scared)
        var eyes: [SKSpriteNode] = []
        for _ in 0..<2 {
            let eye = SKSpriteNode(texture: MazeArt.eyeWhite)
            eye.zPosition = 3.2
            let pupil = SKSpriteNode(texture: MazeArt.pupil)
            pupil.zPosition = 1
            eye.addChild(pupil)
            node.addChild(eye)
            eyes.append(pupil)
        }
        pupils = eyes
        node.zPosition = 3
    }

    func layout(tile: CGFloat) {
        let side = tile * 0.76
        body.size = CGSize(width: side, height: side)
        scared.size = CGSize(width: side, height: side)
        let eye = tile * 0.2
        for (index, pupil) in pupils.enumerated() {
            guard let eyeNode = pupil.parent as? SKSpriteNode else { continue }
            eyeNode.size = CGSize(width: eye, height: eye)
            pupil.size = CGSize(width: eye * 0.5, height: eye * 0.5)
            eyeNode.position = CGPoint(x: (index == 0 ? -0.16 : 0.16) * tile, y: tile * 0.06)
        }
    }

    func applyLook(tile: CGFloat, frightened: Bool) {
        let eyesOnly = mode == .eyes
        body.isHidden = eyesOnly
        scared.isHidden = eyesOnly
        scared.alpha = eyesOnly ? 0 : blend
        if frightened && mode == .frightened {
            scared.color = .white
            scared.colorBlendFactor = 0.85
        } else {
            scared.colorBlendFactor = 0
        }
        root.setScale(eyesOnly ? 0.62 : 1)
        let look = mover.current.vector
        for pupil in pupils {
            pupil.position = CGPoint(x: look.dx * tile * 0.04, y: -look.dy * tile * 0.04)
        }
    }
}

@MainActor
private final class Spark {
    let node: SKSpriteNode
    var velocity = CGPoint.zero
    var life: CGFloat = 0

    init() {
        node = SKSpriteNode(texture: MazeArt.spark)
        node.zPosition = 6
        node.colorBlendFactor = 1
    }
}

@MainActor
private enum MazeArt {
    static let wall = rounded(UIColor(red: 0.16, green: 0.36, blue: 0.98, alpha: 1), 64, 10)
    static let dot = circle(UIColor(red: 1, green: 0.84, blue: 0.35, alpha: 1), 32)
    static let power = circle(UIColor(red: 1, green: 0.78, blue: 0.2, alpha: 1), 48)
    static let mouths: [SKTexture] = [0, 0.28, 0.55, 0.82, 1].map { mouth($0) }
    static let bodies: [SKTexture] = [
        circle(UIColor(red: 0.95, green: 0.24, blue: 0.28, alpha: 1), 64),
        circle(UIColor(red: 0.98, green: 0.52, blue: 0.74, alpha: 1), 64),
        circle(UIColor(red: 0.32, green: 0.84, blue: 0.95, alpha: 1), 64),
    ]
    static let scared = circle(UIColor(red: 0.42, green: 0.58, blue: 1, alpha: 1), 64)
    static let eyeWhite = circle(.white, 24)
    static let pupil = circle(.black, 14)
    static let spark = circle(.white, 20)

    private static func circle(_ color: UIColor, _ diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            color.setFill()
            ctx.cgContext.fillEllipse(in: rect)
            ctx.cgContext.setStrokeColor(UIColor(white: 0.08, alpha: 0.9).cgColor)
            ctx.cgContext.setLineWidth(max(1, diameter * 0.06))
            ctx.cgContext.strokeEllipse(in: rect)
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    private static func rounded(_ color: UIColor, _ side: CGFloat, _ radius: CGFloat) -> SKTexture {
        let size = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius).fill()
            ctx.cgContext.setStrokeColor(UIColor(red: 0.05, green: 0.12, blue: 0.45, alpha: 1).cgColor)
            ctx.cgContext.setLineWidth(3)
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5), cornerRadius: radius).stroke()
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    private static func mouth(_ open: CGFloat) -> SKTexture {
        let size = CGSize(width: 64, height: 64)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: 0.99, green: 0.84, blue: 0.16, alpha: 1).cgColor)
            cg.fillEllipse(in: rect)
            guard open > 0.02 else { return }
            cg.setBlendMode(.destinationOut)
            cg.beginPath()
            cg.move(to: CGPoint(x: rect.midX, y: rect.midY))
            let spread = rect.height * 0.48 * open
            cg.addLine(to: CGPoint(x: rect.maxX + 4, y: rect.midY - spread))
            cg.addLine(to: CGPoint(x: rect.maxX + 4, y: rect.midY + spread))
            cg.closePath()
            cg.fillPath()
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }
}
