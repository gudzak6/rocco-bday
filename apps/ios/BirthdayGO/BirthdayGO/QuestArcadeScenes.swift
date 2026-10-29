import SpriteKit
import AudioToolbox

enum QuestPixel {
    static let ink = UIColor(white: 0.12, alpha: 1)
    static let skin = UIColor(red: 0.93, green: 0.76, blue: 0.62, alpha: 1)
    static let hair = UIColor(red: 0.25, green: 0.16, blue: 0.12, alpha: 1)

    static func rocco(shirt: UIColor) -> SKNode {
        let node = SKNode()
        func block(_ w: CGFloat, _ h: CGFloat, _ color: UIColor, _ x: CGFloat, _ y: CGFloat, name: String = "") -> SKSpriteNode {
            let sprite = SKSpriteNode(color: color, size: CGSize(width: w, height: h))
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
            sprite.position = CGPoint(x: x, y: y)
            sprite.name = name
            return sprite
        }
        node.addChild(block(10, 8, ink, -8, 0, name: "leg"))
        node.addChild(block(10, 8, ink, 8, 0, name: "leg"))
        node.addChild(block(26, 22, shirt, 0, 8))
        node.addChild(block(22, 16, skin, 0, 30))
        node.addChild(block(26, 8, hair, 0, 44))
        let glasses = SKSpriteNode(color: ink, size: CGSize(width: 16, height: 3))
        glasses.anchorPoint = CGPoint(x: 0.5, y: 0)
        glasses.position = CGPoint(x: 0, y: 36)
        node.addChild(glasses)
        return node
    }

    static func blip() { AudioServicesPlaySystemSound(1104) }
}

class QuestArcadeScene: SKScene {
    var outcome = 0
    var lastTime: TimeInterval = 0
    var running = false

    override init() {
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func setRunning(_ on: Bool) {
        running = on
        isPaused = false
        if on { lastTime = 0 }
    }

    func dt(_ time: TimeInterval) -> CGFloat {
        if lastTime == 0 { lastTime = time; return 0 }
        let value = min(0.033, time - lastTime)
        lastTime = time
        return CGFloat(value)
    }

    func puff(at point: CGPoint, color: UIColor) {
        let dot = SKShapeNode(circleOfRadius: 7)
        dot.fillColor = color
        dot.strokeColor = .clear
        dot.position = point
        addChild(dot)
        dot.run(.sequence([.group([.fadeOut(withDuration: 0.3), .scale(to: 2.2, duration: 0.3)]), .removeFromParent()]))
    }
}

final class MarathonScene: QuestArcadeScene {
    var meters = 0
    var gels = 0
    var hits = 0
    private var distance: CGFloat = 0
    private var py: CGFloat = 120
    private var vy: CGFloat = 0
    private var onGround = true
    private var lastTap: TimeInterval = 0
    private var doubleUsed = false
    private var spawn = 0.0
    private var invuln: CGFloat = 0
    private var finishing = false
    private var finishLeft: CGFloat = 0
    private let player = QuestPixel.rocco(shirt: UIColor(red: 0.2, green: 0.55, blue: 0.95, alpha: 1))
    private var ground: SKSpriteNode?

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.53, green: 0.82, blue: 0.98, alpha: 1)
        if player.parent == nil { addChild(player) }
        layoutCourse()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutCourse()
    }

    private func layoutCourse() {
        let bar = ground ?? SKSpriteNode(color: UIColor(red: 0.35, green: 0.72, blue: 0.38, alpha: 1), size: CGSize(width: size.width, height: 28))
        bar.anchorPoint = .zero
        bar.position = CGPoint(x: 0, y: floorY - 28)
        bar.size = CGSize(width: max(size.width, 1) + 40, height: 28)
        if bar.parent == nil { addChild(bar) }
        ground = bar
        if onGround { py = floorY }
        player.position = CGPoint(x: 120, y: py)
    }

    private var floorY: CGFloat { max(90, size.height * 0.16) }

    override func update(_ currentTime: TimeInterval) {
        let delta = dt(currentTime)
        guard running, delta > 0, outcome == 0 else { return }
        step(delta, time: currentTime)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard running, outcome == 0, let time = touches.first?.timestamp else { return }
        if onGround {
            vy = 680
            onGround = false
            doubleUsed = false
        } else if !doubleUsed, time - lastTap < 0.34 {
            vy = 860
            doubleUsed = true
        }
        lastTap = time
    }

    private func step(_ delta: CGFloat, time: TimeInterval) {
        if !finishing {
            distance += delta * 14
            meters = Int(distance)
        }
        vy -= 1700 * delta
        py += vy * delta
        if py <= floorY {
            py = floorY
            vy = 0
            onGround = true
            doubleUsed = false
        }
        player.position = CGPoint(x: 120, y: py)
        let legs = player.children.filter { $0.name == "leg" }
        if onGround {
            let swing = sin(time * 14) * 6
            legs.first?.position.x = -8 + swing
            legs.last?.position.x = 8 - swing
        }
        invuln = max(0, invuln - delta)
        player.alpha = invuln > 0 && Int(time * 12).isMultiple(of: 2) ? 0.35 : 1
        if !finishing {
            spawn -= Double(delta)
            if spawn <= 0 {
                spawn = 1.15
                dropObstacle()
                if Int.random(in: 0...2) == 0 { dropGel() }
            }
        }
        let body = CGRect(x: 100, y: py + 6, width: 36, height: 58)
        for node in children where node.name == "hazard" || node.name == "gel" || node.name == "flag" {
            node.position.x -= delta * 230
            if node.position.x < -50 { node.removeFromParent(); continue }
            guard invuln <= 0, !finishing else { continue }
            if node.name == "hazard", body.intersects(node.frame.insetBy(dx: 6, dy: 4)) {
                hits += 1
                invuln = 1
                QuestPixel.blip()
                node.removeFromParent()
                if hits >= 3 { outcome = 2 }
            } else if node.name == "gel", body.insetBy(dx: -8, dy: -8).intersects(node.frame) {
                gels += 1
                puff(at: node.position, color: .systemYellow)
                node.removeFromParent()
                QuestPixel.blip()
            }
        }
        if !finishing, distance >= 500, gels >= 5 {
            finishing = true
            finishLeft = 1.15
            let flag = SKLabelNode(text: "FINISH")
            flag.fontName = "AvenirNext-Heavy"
            flag.fontSize = 28
            flag.fontColor = .black
            flag.position = CGPoint(x: size.width - 80, y: floorY + 90)
            flag.name = "flag"
            addChild(flag)
        }
        if finishing {
            finishLeft -= delta
            if finishLeft <= 0 { outcome = 1 }
        }
    }

    private func dropObstacle() {
        let kind = Int.random(in: 0...2)
        let height: CGFloat = kind == 0 ? 26 : (kind == 1 ? 48 : 96)
        let color: UIColor = kind == 0 ? UIColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 1) : (kind == 1 ? .systemOrange : .white)
        let node = SKSpriteNode(color: color, size: CGSize(width: kind == 2 ? 18 : 36, height: height))
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.position = CGPoint(x: size.width + 30, y: floorY)
        node.name = "hazard"
        addChild(node)
    }

    private func dropGel() {
        let node = SKShapeNode(circleOfRadius: 12)
        node.fillColor = UIColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 1)
        node.strokeColor = QuestPixel.ink
        node.lineWidth = 3
        node.position = CGPoint(x: size.width + 20, y: floorY + CGFloat.random(in: 70...150))
        node.name = "gel"
        addChild(node)
    }
}

final class CookieChaosScene: QuestArcadeScene {
    var cookies = 0
    var bad = 0
    var combo = 0
    private var spawn = 0.2
    private var basketX: CGFloat = 180
    private let basket = SKShapeNode(rectOf: CGSize(width: 96, height: 28), cornerRadius: 8)
    private let rocco = QuestPixel.rocco(shirt: UIColor(red: 0.95, green: 0.55, blue: 0.25, alpha: 1))

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 1, green: 0.93, blue: 0.82, alpha: 1)
        basket.fillColor = UIColor(red: 0.55, green: 0.32, blue: 0.16, alpha: 1)
        basket.strokeColor = QuestPixel.ink
        basket.lineWidth = 3
        basket.name = "basket"
        if basket.parent == nil {
            addChild(basket)
            addChild(rocco)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        basketX = min(max(basketX, 60), size.width - 60)
        layoutBasket()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        basketX = min(max(touch.location(in: self).x, 60), size.width - 60)
        layoutBasket()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesMoved(touches, with: event)
    }

    private func layoutBasket() {
        basket.position = CGPoint(x: basketX, y: 120)
        rocco.position = CGPoint(x: basketX, y: 78)
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = dt(currentTime)
        guard running, delta > 0, outcome == 0 else { return }
        spawn -= Double(delta)
        if spawn <= 0 {
            spawn = 0.48
            drop()
        }
        let catchBox = CGRect(x: basketX - 50, y: 100, width: 100, height: 36)
        for node in children where node.name == "cookie" || node.name == "bad" {
            node.position.y -= delta * 250
            if catchBox.intersects(node.frame.insetBy(dx: 4, dy: 4)) {
                if node.name == "cookie" {
                    cookies += 1
                    combo += 1
                    puff(at: node.position, color: .systemOrange)
                    if cookies >= 20 { outcome = 1 }
                } else {
                    bad += 1
                    combo = 0
                    puff(at: node.position, color: .systemGreen)
                    if bad >= 3 { outcome = 2 }
                }
                QuestPixel.blip()
                node.removeFromParent()
            } else if node.position.y < 40 {
                if node.name == "cookie" { combo = 0 }
                node.removeFromParent()
            }
        }
    }

    private func drop() {
        let good = Int.random(in: 0...4) > 0
        let node = SKShapeNode(circleOfRadius: good ? 16 : 14)
        node.fillColor = good ? UIColor(red: 0.84, green: 0.58, blue: 0.28, alpha: 1) : (Bool.random() ? .systemGreen : UIColor(white: 0.2, alpha: 1))
        node.strokeColor = QuestPixel.ink
        node.lineWidth = 3
        node.position = CGPoint(x: CGFloat.random(in: 40...(max(80, size.width - 40))), y: size.height + 20)
        node.name = good ? "cookie" : "bad"
        addChild(node)
    }
}


final class GamerMazeScene: QuestArcadeScene {
    var found = 0
    var hits = 0
    private var grid: [[Swift.Character]] = []
    private var player = (x: 1, y: 1)
    private var enemies: [(x: Int, y: Int, dir: Int)] = []
    private var built = false
    private var acc: CGFloat = 0
    private var invuln: CGFloat = 0
    private let playerNode = QuestPixel.rocco(shirt: UIColor(red: 0.45, green: 0.3, blue: 0.95, alpha: 1))
    private var enemyNodes: [SKShapeNode] = []
    private let source = [
        "############",
        "#S  #C     #",
        "# ## # ### #",
        "#C   #   C #",
        "### ## # # #",
        "#   C  #   #",
        "# #### # #E#",
        "#C         #",
        "############",
    ]

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.08, green: 0.06, blue: 0.16, alpha: 1)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 40, !built else { return }
        built = true
        grid = source.map { Array($0) }
        for (y, row) in grid.enumerated() {
            for (x, cell) in row.enumerated() where cell == "S" { player = (x, y) }
        }
        enemies = [(8, 1, 1), (2, 5, 1)]
        drawTiles()
        addChild(playerNode)
        for _ in enemies {
            let node = SKShapeNode(circleOfRadius: cellSize * 0.28)
            node.fillColor = .systemPink
            node.strokeColor = .clear
            addChild(node)
            enemyNodes.append(node)
        }
        placeActors()
    }

    private var cellSize: CGFloat {
        min((size.width - 24) / 12, (size.height - 180) / 9)
    }

    private func origin(x: Int, y: Int) -> CGPoint {
        CGPoint(x: 12 + CGFloat(x) * cellSize + cellSize / 2, y: size.height - 80 - CGFloat(y) * cellSize)
    }

    private func drawTiles() {
        for (y, row) in grid.enumerated() {
            for (x, cell) in row.enumerated() {
                let tile = SKSpriteNode(color: cell == "#" ? UIColor(red: 0.25, green: 0.15, blue: 0.55, alpha: 1) : UIColor(white: 0.12, alpha: 1), size: CGSize(width: cellSize - 2, height: cellSize - 2))
                tile.position = origin(x: x, y: y)
                addChild(tile)
                if cell == "C" {
                    let gem = SKShapeNode(circleOfRadius: cellSize * 0.18)
                    gem.fillColor = .systemTeal
                    gem.strokeColor = .white
                    gem.position = origin(x: x, y: y)
                    gem.name = "pad-\(x)-\(y)"
                    addChild(gem)
                } else if cell == "E" {
                    let exit = SKSpriteNode(color: .systemYellow, size: CGSize(width: cellSize * 0.45, height: cellSize * 0.45))
                    exit.position = origin(x: x, y: y)
                    addChild(exit)
                }
            }
        }
    }

    private func placeActors() {
        playerNode.position = origin(x: player.x, y: player.y)
        playerNode.setScale(cellSize / 70)
        for (index, enemy) in enemies.enumerated() where index < enemyNodes.count {
            enemyNodes[index].position = origin(x: enemy.x, y: enemy.y)
        }
    }

    func move(dx: Int, dy: Int) {
        guard running, outcome == 0 else { return }
        let next = (x: player.x + dx, y: player.y + dy)
        guard grid.indices.contains(next.y), grid[next.y].indices.contains(next.x), grid[next.y][next.x] != "#" else { return }
        player = next
        if grid[next.y][next.x] == "C" {
            grid[next.y][next.x] = " "
            found += 1
            childNode(withName: "pad-\(next.x)-\(next.y)")?.removeFromParent()
            QuestPixel.blip()
        }
        if grid[next.y][next.x] == "E", found >= 5 { outcome = 1 }
        bumpEnemies()
        placeActors()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let start = touch.previousLocation(in: self)
        let end = touch.location(in: self)
        let dx = end.x - start.x
        let dy = end.y - start.y
        if abs(dx) < 12 && abs(dy) < 12 { return }
        if abs(dx) > abs(dy) { move(dx: dx > 0 ? 1 : -1, dy: 0) }
        else { move(dx: 0, dy: dy > 0 ? -1 : 1) }
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = dt(currentTime)
        guard running, delta > 0, outcome == 0 else { return }
        invuln = max(0, invuln - delta)
        acc += delta
        if acc > 0.45 {
            acc = 0
            for index in enemies.indices {
                let nextX = enemies[index].x + enemies[index].dir
                if grid[enemies[index].y][nextX] == "#" { enemies[index].dir *= -1 }
                else { enemies[index].x = nextX }
            }
            bumpEnemies()
            placeActors()
        }
    }

    private func bumpEnemies() {
        guard invuln <= 0 else { return }
        if enemies.contains(where: { $0.x == player.x && $0.y == player.y }) {
            hits += 1
            invuln = 0.8
            if hits >= 3 { outcome = 2 }
        }
    }
}

final class TrainScene: QuestArcadeScene {
    var meters = 0
    var tickets = 0
    var hits = 0
    private var distance: CGFloat = 0
    private var lane = 1
    private var jump: CGFloat = 0
    private var spawn = 0.4
    private var invuln: CGFloat = 0
    private var swipeStart: CGPoint?
    private let player = QuestPixel.rocco(shirt: UIColor(red: 0.2, green: 0.45, blue: 0.9, alpha: 1))

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.75, green: 0.88, blue: 0.98, alpha: 1)
        if player.parent == nil { addChild(player) }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        player.position = CGPoint(x: laneX, y: 130 + jump)
    }

    private func laneX(_ index: Int) -> CGFloat {
        let step = size.width / 4
        return step * CGFloat(index + 1)
    }

    private var laneX: CGFloat { laneX(lane) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        swipeStart = touches.first?.location(in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard running, let start = swipeStart, let end = touches.first?.location(in: self) else { return }
        let dx = end.x - start.x
        let dy = end.y - start.y
        if dy > 40 && abs(dy) > abs(dx) { jump = 70 }
        else if dx > 30 { lane = min(2, lane + 1) }
        else if dx < -30 { lane = max(0, lane - 1) }
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = dt(currentTime)
        guard running, delta > 0, outcome == 0 else { return }
        distance += delta * 16
        meters = Int(distance)
        jump = max(0, jump - delta * 140)
        invuln = max(0, invuln - delta)
        player.position = CGPoint(x: laneX, y: 130 + jump)
        player.alpha = invuln > 0 ? 0.4 : 1
        spawn -= Double(delta)
        if spawn <= 0 {
            spawn = 0.7
            let ticket = Int.random(in: 0...2) == 0
            let node = SKShapeNode(rectOf: CGSize(width: ticket ? 22 : 40, height: ticket ? 16 : 36), cornerRadius: 4)
            node.fillColor = ticket ? .systemYellow : UIColor(red: 0.35, green: 0.28, blue: 0.22, alpha: 1)
            node.strokeColor = QuestPixel.ink
            node.lineWidth = 2
            node.position = CGPoint(x: laneX(Int.random(in: 0...2)), y: size.height + 20)
            node.name = ticket ? "ticket" : "luggage"
            addChild(node)
        }
        let body = CGRect(x: player.position.x - 18, y: player.position.y, width: 36, height: 60)
        for node in children where node.name == "ticket" || node.name == "luggage" {
            node.position.y -= delta * 260
            if body.intersects(node.frame), jump < 20, invuln <= 0, node.name == "luggage" {
                hits += 1
                invuln = 0.9
                node.removeFromParent()
                if hits >= 3 { outcome = 2 }
            } else if body.intersects(node.frame), node.name == "ticket" {
                tickets += 1
                node.removeFromParent()
                QuestPixel.blip()
            } else if node.position.y < 40 {
                node.removeFromParent()
            }
        }
        if distance >= 400 && tickets >= 8 { outcome = 1 }
    }
}
