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
            QuestAudio.shared.playJump()
        } else if !doubleUsed, time - lastTap < 0.34 {
            vy = 860
            doubleUsed = true
            QuestAudio.shared.playJump()
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

final class BoyfriendScene: QuestArcadeScene {
    var hearts = 0
    var hits = 0
    var hint = "Collect 10 hearts"
    var inputX: CGFloat = 0
    var jumpQueued = false
    private var px: CGFloat = 80
    private var py: CGFloat = 160
    private var vy: CGFloat = 0
    private var grounded = false
    private var invuln: CGFloat = 0
    private let world = SKNode()
    private let player = QuestPixel.rocco(shirt: UIColor(red: 0.95, green: 0.4, blue: 0.62, alpha: 1))
    private let platforms: [CGRect] = [
        CGRect(x: 0, y: 120, width: 300, height: 22),
        CGRect(x: 380, y: 190, width: 170, height: 22),
        CGRect(x: 620, y: 120, width: 160, height: 22),
        CGRect(x: 860, y: 240, width: 190, height: 22),
        CGRect(x: 1140, y: 150, width: 170, height: 22),
        CGRect(x: 1400, y: 250, width: 210, height: 22),
        CGRect(x: 1700, y: 160, width: 180, height: 22),
        CGRect(x: 1960, y: 120, width: 420, height: 22),
    ]
    private var heartSpots = [
        CGPoint(x: 160, y: 180), CGPoint(x: 430, y: 250), CGPoint(x: 680, y: 180),
        CGPoint(x: 930, y: 300), CGPoint(x: 1200, y: 210), CGPoint(x: 1480, y: 310),
        CGPoint(x: 1760, y: 220), CGPoint(x: 2050, y: 190), CGPoint(x: 220, y: 190),
        CGPoint(x: 1000, y: 310), CGPoint(x: 1600, y: 310), CGPoint(x: 2140, y: 200),
    ]
    private var enemies: [(x: CGFloat, y: CGFloat, minX: CGFloat, maxX: CGFloat, dir: CGFloat, node: SKShapeNode)] = []

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.98, green: 0.78, blue: 0.88, alpha: 1)
        guard world.parent == nil else { return }
        addChild(world)
        for rect in platforms {
            let pad = SKSpriteNode(color: UIColor(red: 0.95, green: 0.45, blue: 0.7, alpha: 1), size: rect.size)
            pad.anchorPoint = .zero
            pad.position = CGPoint(x: rect.minX, y: rect.minY)
            world.addChild(pad)
        }
        for spot in heartSpots {
            let heart = SKShapeNode(circleOfRadius: 12)
            heart.fillColor = .systemPink
            heart.strokeColor = QuestPixel.ink
            heart.lineWidth = 2
            heart.position = spot
            heart.name = "heart"
            world.addChild(heart)
        }
        let door = SKSpriteNode(color: UIColor(red: 0.55, green: 0.28, blue: 0.55, alpha: 1), size: CGSize(width: 46, height: 70))
        door.anchorPoint = CGPoint(x: 0.5, y: 0)
        door.position = CGPoint(x: 2260, y: 142)
        world.addChild(door)
        let patrols: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(400, 230, 390, 520), (1420, 290, 1410, 1580)]
        for patrol in patrols {
            let enemy = SKShapeNode(circleOfRadius: 14)
            enemy.fillColor = UIColor(red: 0.35, green: 0.25, blue: 0.55, alpha: 1)
            enemy.strokeColor = .clear
            enemy.position = CGPoint(x: patrol.0, y: patrol.1)
            world.addChild(enemy)
            enemies.append((patrol.0, patrol.1, patrol.2, patrol.3, 1, enemy))
        }
        world.addChild(player)
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = dt(currentTime)
        guard running, delta > 0, outcome == 0 else { return }
        let previous = py
        px += inputX * 250 * delta
        px = min(max(px, 30), 2320)
        if jumpQueued && grounded {
            vy = 720
            grounded = false
        }
        jumpQueued = false
        vy -= 1650 * delta
        py += vy * delta
        grounded = false
        if vy <= 0 {
            for rect in platforms where px > rect.minX + 10 && px < rect.maxX - 10 && previous >= rect.maxY - 2 && py <= rect.maxY {
                py = rect.maxY
                vy = 0
                grounded = true
                break
            }
        }
        if py < -20 {
            hits += 1
            px = 80
            py = 160
            vy = 0
            if hits >= 3 { outcome = 2; return }
        }
        invuln = max(0, invuln - delta)
        for index in enemies.indices {
            enemies[index].x += enemies[index].dir * 80 * delta
            if enemies[index].x < enemies[index].minX || enemies[index].x > enemies[index].maxX {
                enemies[index].dir *= -1
            }
            enemies[index].node.position = CGPoint(x: enemies[index].x, y: enemies[index].y)
            if invuln <= 0, hypot(px - enemies[index].x, py - enemies[index].y) < 32 {
                hits += 1
                invuln = 1
                if hits >= 3 { outcome = 2; return }
            }
        }
        player.position = CGPoint(x: px, y: py)
        player.alpha = invuln > 0 ? 0.45 : 1
        world.position.x = min(0, 160 - px)
        for node in world.children where node.name == "heart" {
            if hypot(px - node.position.x, (py + 30) - node.position.y) < 36 {
                hearts += 1
                puff(at: convert(node.position, from: world), color: .systemPink)
                node.removeFromParent()
                QuestPixel.blip()
            }
        }
        hint = hearts >= 10 ? "Reach the door" : "Collect 10 hearts"
        if px > 2200 && hearts >= 10 { outcome = 1 }
    }
}
