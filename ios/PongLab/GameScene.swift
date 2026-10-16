//
//  GameScene.swift
//  PongLab
//  Created by eliedev on 15/10/2026.
//


import SpriteKit

protocol GameSceneDelegate: AnyObject {
    func didRequestReturnToHome()
}

enum PhysicsCategory {
    static let ball: UInt32   = 1 << 0
    static let wall: UInt32   = 1 << 1
    static let paddle: UInt32 = 1 << 2
}

enum GameState {
    case playing, paused, gameOver
}

class GameScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Constants

    private enum Constants {
        static let paddleEdgeOffset: CGFloat = 60
        static let wallWidth: CGFloat = 10
        static let minVerticalRatio: CGFloat = 0.35   // avoids near-horizontal trajectories
        static let scoreLabelOffset: CGFloat = 30
        static let overlayZ: CGFloat = 100
    }

    private enum ButtonName: String {
        case pause = "pauseButton"
        case resume = "resumeButton"
        case restart = "restartButton"
        case replay = "replayButton"
        case home = "homeButton"
    }

    // MARK: - Properties

    weak var gameSceneDelegate: GameSceneDelegate?

    /// Set before presenting the scene. Kept across restarts.
    var configuration = GameConfiguration() {
        didSet { configuration = configuration.validated() }
    }

    private(set) var state: GameState = .playing

    private var balls: [SKShapeNode] = []
    private var paddles: [Player: SKShapeNode] = [:]
    private var scores: [Player: Int] = [:]
    private var scoreLabels: [Player: SKLabelNode] = [:]
    private var menuNode: SKNode?

    private var currentBallSpeed: CGFloat = 0

    private let bounceSound = SKAction.playSoundFileNamed("bouncing.mp3", waitForCompletion: false)

    private var joysticks: [Player: JoystickManager] = [:]
    private var joystickConnected: [Player: Bool] = [:]
    private var lastJoystickPosition: [Player: CGFloat] = [:]
    private var lifecycleObserver: NSObjectProtocol?

    private var paddleSize: CGSize {
        CGSize(width: configuration.paddleWidth, height: configuration.paddleHeight)
    }

    // MARK: - Scene lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .black
        startGame()
        setupJoysticks()
        observeAppLifecycle()
    }

    override func willMove(from view: SKView) {
        // Stops everything that could outlive the scene: HomeKit observation,
        // notification observers, running actions and physics callbacks.
        joysticks.values.forEach { $0.stop() }
        joysticks.removeAll()
        joystickConnected.removeAll()
        if let observer = lifecycleObserver {
            NotificationCenter.default.removeObserver(observer)
            lifecycleObserver = nil
        }
        removeAllActions()
        physicsWorld.contactDelegate = nil
    }

    private func observeAppLifecycle() {
        // Automatically pause when the app goes to the background.
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.pauseGame()
        }
    }

    // MARK: - Joysticks

    private func setupJoysticks() {
        for player in Player.allCases {
            let manager = JoystickManager(player: player)
            manager.onConnectionChanged = { [weak self] connected in
                self?.joystickConnected[player] = connected
                if connected { self?.applyJoystickPositions() }
            }
            manager.onPositionChanged = { [weak self] normalized in
                self?.joystickMoved(normalized, for: player)
            }
            joysticks[player] = manager
            manager.start()
        }
    }

    private func joystickMoved(_ normalized: CGFloat, for player: Player) {
        lastJoystickPosition[player] = normalized
        // Ignored while paused or finished; the position is re-applied on resume.
        guard state == .playing else { return }
        paddles[player]?.position.x = clampedX(normalized * size.width)
    }

    private func applyJoystickPositions() {
        guard state == .playing else { return }
        for (player, normalized) in lastJoystickPosition where joystickConnected[player] == true {
            paddles[player]?.position.x = clampedX(normalized * size.width)
        }
    }

    // MARK: - Game setup

    private func startGame() {
        removeAllChildren()
        removeAllActions()
        balls.removeAll()
        paddles.removeAll()
        menuNode = nil

        state = .playing
        physicsWorld.speed = 1
        currentBallSpeed = configuration.initialBallSpeed

        setUpPhysicsWorld()
        createWalls()
        createPaddles()
        createScore()
        createPauseButton()
        createBalls()
        applyJoystickPositions()
    }

    private func setUpPhysicsWorld() {
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
    }

    private func createBalls() {
        for _ in 0..<configuration.ballCount {
            let ball = createBall()
            balls.append(ball)
            resetBall(ball)
        }
    }

    private func createBall() -> SKShapeNode {
        let ball = SKShapeNode(circleOfRadius: configuration.ballRadius)
        ball.strokeColor = .white
        ball.fillColor = .white

        let body = SKPhysicsBody(circleOfRadius: configuration.ballRadius)
        body.restitution = 1.0
        body.friction = 0
        body.linearDamping = 0
        body.angularDamping = 0
        body.allowsRotation = false
        body.categoryBitMask = PhysicsCategory.ball
        body.collisionBitMask = PhysicsCategory.wall | PhysicsCategory.paddle | PhysicsCategory.ball
        body.contactTestBitMask = PhysicsCategory.wall | PhysicsCategory.paddle | PhysicsCategory.ball
        ball.physicsBody = body

        addChild(ball)
        return ball
    }

    private func createWalls() {
        createVerticalWall(x: Constants.wallWidth / 2)
        createVerticalWall(x: size.width - Constants.wallWidth / 2)
    }

    private func createVerticalWall(x: CGFloat) {
        let wallSize = CGSize(width: Constants.wallWidth, height: size.height)
        let wall = SKShapeNode(rectOf: wallSize)
        wall.position = CGPoint(x: x, y: size.height / 2)
        wall.strokeColor = .clear
        wall.fillColor = .clear

        let body = SKPhysicsBody(rectangleOf: wallSize)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.wall
        wall.physicsBody = body

        addChild(wall)
    }

    private func createPaddles() {
        paddles[.one] = createPaddle(y: Constants.paddleEdgeOffset)
        paddles[.two] = createPaddle(y: size.height - Constants.paddleEdgeOffset)
    }

    private func createPaddle(y: CGFloat) -> SKShapeNode {
        let paddle = SKShapeNode(rectOf: paddleSize)
        paddle.position = CGPoint(x: size.width / 2, y: y)
        paddle.strokeColor = .white
        paddle.fillColor = .white

        let body = SKPhysicsBody(rectangleOf: paddleSize)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.paddle
        paddle.physicsBody = body

        addChild(paddle)
        return paddle
    }

    private func createScore() {
        scores = [.one: 0, .two: 0]
        scoreLabels[.one] = createScoreLabel(y: size.height / 2 - Constants.scoreLabelOffset)
        scoreLabels[.two] = createScoreLabel(y: size.height / 2 + Constants.scoreLabelOffset)
    }

    private func createScoreLabel(y: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(text: "0")
        label.fontName = "Menlo-Bold"
        label.fontSize = 24
        label.fontColor = .white
        label.position = CGPoint(x: size.width / 2, y: y)
        addChild(label)
        return label
    }

    private func createPauseButton() {
        // Invisible, larger hit area behind the visible label.
        let hitArea = SKSpriteNode(color: .clear, size: CGSize(width: 56, height: 56))
        hitArea.name = ButtonName.pause.rawValue
        hitArea.position = CGPoint(x: size.width - 40, y: size.height / 2)
        hitArea.zPosition = 10

        let label = SKLabelNode(text: "II")
        label.fontName = "Menlo-Bold"
        label.fontSize = 22
        label.fontColor = SKColor(white: 1, alpha: 0.7)
        label.verticalAlignmentMode = .center
        hitArea.addChild(label)

        addChild(hitArea)
    }

    // MARK: - Ball handling

    /// Puts one ball back at the center and launches it in a random diagonal direction.
    private func resetBall(_ ball: SKShapeNode) {
        ball.position = CGPoint(x: size.width / 2, y: size.height / 2)

        let angle = CGFloat.random(in: (.pi / 6)...(.pi / 3))   // 30° to 60°
        let dx = cos(angle) * (Bool.random() ? 1 : -1)
        let dy = sin(angle) * (Bool.random() ? 1 : -1)
        ball.physicsBody?.velocity = CGVector(dx: dx * currentBallSpeed, dy: dy * currentBallSpeed)
    }

    /// Keeps every ball at the shared current speed and prevents near-horizontal trajectories.
    private func normalizeVelocity(of ball: SKShapeNode) {
        guard let body = ball.physicsBody else { return }
        let v = body.velocity
        let length = hypot(v.dx, v.dy)
        guard length > 0 else { return }

        var dx = v.dx / length
        var dy = v.dy / length

        if abs(dy) < Constants.minVerticalRatio {
            dy = copysign(Constants.minVerticalRatio, dy)
            let newLength = hypot(dx, dy)
            dx /= newLength
            dy /= newLength
        }

        body.velocity = CGVector(dx: dx * currentBallSpeed, dy: dy * currentBallSpeed)
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard state == .playing else { return }

        for ball in balls {
            if ball.position.y < 0 {
                scorePoint(for: .two)
            } else if ball.position.y > size.height {
                scorePoint(for: .one)
            } else {
                continue
            }

            // Only the ball that left the field is relaunched; the others keep going.
            if state == .gameOver { return }
            resetBall(ball)
        }
    }

    override func didSimulatePhysics() {
        guard state == .playing else { return }
        balls.forEach(normalizeVelocity(of:))
    }

    private func scorePoint(for player: Player) {
        // A point resets the shared speed (applies to every ball).
        currentBallSpeed = configuration.initialBallSpeed

        let newScore = (scores[player] ?? 0) + 1
        scores[player] = newScore
        scoreLabels[player]?.text = "\(newScore)"

        if newScore >= configuration.winningScore {
            endGame(winner: player)
        }
    }

    // MARK: - State transitions

    func pauseGame() {
        guard state == .playing else { return }
        state = .paused
        physicsWorld.speed = 0     // freezes balls without losing velocity or positions
        showMenu(title: "Pause",
                 buttons: [("Reprendre", .resume), ("Recommencer", .restart), ("Accueil", .home)])
    }

    private func resumeGame() {
        guard state == .paused else { return }
        hideMenu()
        state = .playing
        physicsWorld.speed = 1
        applyJoystickPositions()
    }

    private func restartGame() {
        // Scores, balls, speed, paddles and menus are all rebuilt; configuration is kept.
        startGame()
    }

    private func endGame(winner: Player) {
        state = .gameOver
        physicsWorld.speed = 0
        showMenu(title: "\(winner.displayName) gagne !", titleColor: .yellow,
                 buttons: [("Rejouer", .replay), ("Accueil", .home)])
    }

    private func goToHomePage() {
        gameSceneDelegate?.didRequestReturnToHome()
    }

    // MARK: - Menu overlay

    private func showMenu(title: String,
                          titleColor: SKColor = .white,
                          buttons: [(title: String, name: ButtonName)]) {
        hideMenu()

        let menu = SKNode()
        menu.zPosition = Constants.overlayZ

        let dim = SKSpriteNode(color: .black, size: size)
        dim.alpha = 0.7
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        menu.addChild(dim)

        let titleLabel = SKLabelNode(text: title)
        titleLabel.fontName = "Menlo-Bold"
        titleLabel.fontSize = 32
        titleLabel.fontColor = titleColor
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 70)
        menu.addChild(titleLabel)

        for (index, button) in buttons.enumerated() {
            let label = SKLabelNode(text: button.title)
            label.name = button.name.rawValue
            label.fontName = "Menlo"
            label.fontSize = 24
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: size.width / 2,
                                     y: size.height / 2 - CGFloat(index) * 48)
            menu.addChild(label)
        }

        addChild(menu)
        menuNode = menu
    }

    private func hideMenu() {
        menuNode?.removeFromParent()
        menuNode = nil
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        let tappedButton = nodes(at: location)
            .compactMap { $0.name }
            .compactMap(ButtonName.init(rawValue:))
            .first

        if let button = tappedButton {
            handleTap(on: button)
        } else if state == .playing {
            movePaddle(to: location)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state == .playing else { return }
        // Multi-touch: each finger controls the paddle of its own half of the screen.
        for touch in touches {
            movePaddle(to: touch.location(in: self))
        }
    }

    private func handleTap(on button: ButtonName) {
        switch button {
        case .pause:
            pauseGame()
        case .resume:
            resumeGame()
        case .restart:
            if state == .paused { restartGame() }
        case .replay:
            if state == .gameOver { restartGame() }
        case .home:
            if state != .playing { goToHomePage() }
        }
    }

    private func movePaddle(to location: CGPoint) {
        let player: Player = location.y < size.height / 2 ? .one : .two
        // A connected joystick has priority over touch for ITS paddle only.
        guard joystickConnected[player] != true else { return }
        paddles[player]?.position.x = clampedX(location.x)
    }

    /// Keeps the paddle between the two walls.
    private func clampedX(_ x: CGFloat) -> CGFloat {
        let half = paddleSize.width / 2 + Constants.wallWidth
        return min(max(x, half), size.width - half)
    }

    // MARK: - SKPhysicsContactDelegate

    func didBegin(_ contact: SKPhysicsContact) {
        run(bounceSound)

        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if categories & PhysicsCategory.paddle != 0 {
            currentBallSpeed = min(currentBallSpeed * configuration.speedIncreasePerHit,
                                   configuration.maxBallSpeed)
        }
    }
}
