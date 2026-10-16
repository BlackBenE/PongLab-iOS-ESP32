//
//  GameConfiguration.swift
//  PongLab
//
//  Created by eliedev on 16/10/2026.
//
//  All the tunable rules of a match.
//

import CoreGraphics
import Foundation

struct GameConfiguration: Codable, Equatable {
    var winningScore = 10
    var initialBallSpeed: CGFloat = 500          // points / second
    var maxBallSpeed: CGFloat = 1000
    var speedIncreasePerHit: CGFloat = 1.04      // multiplier applied on each paddle hit
    var paddleWidth: CGFloat = 100
    var paddleHeight: CGFloat = 10
    var ballRadius: CGFloat = 10
    var ballCount = 1

    // MARK: - Allowed values

    static let winningScoreOptions = [5, 10, 15, 20]
    static let initialSpeedRange: ClosedRange<CGFloat> = 300...900
    static let maxSpeedRange: ClosedRange<CGFloat> = 600...1600
    static let speedIncreaseRange: ClosedRange<CGFloat> = 1.0...1.15
    static let paddleWidthRange: ClosedRange<CGFloat> = 60...200
    static let paddleHeightRange: ClosedRange<CGFloat> = 6...20
    static let ballRadiusRange: ClosedRange<CGFloat> = 6...20
    static let ballCountRange: ClosedRange<Int> = 1...4

    /// Returns a copy with every value forced into its allowed range.
    func validated() -> GameConfiguration {
        var c = self
        c.winningScore = Self.winningScoreOptions.contains(winningScore) ? winningScore : 10
        c.initialBallSpeed = Self.clamp(initialBallSpeed, Self.initialSpeedRange)
        c.maxBallSpeed = Self.clamp(maxBallSpeed, Self.maxSpeedRange)
        c.maxBallSpeed = max(c.maxBallSpeed, c.initialBallSpeed)
        c.speedIncreasePerHit = Self.clamp(speedIncreasePerHit, Self.speedIncreaseRange)
        c.paddleWidth = Self.clamp(paddleWidth, Self.paddleWidthRange)
        c.paddleHeight = Self.clamp(paddleHeight, Self.paddleHeightRange)
        c.ballRadius = Self.clamp(ballRadius, Self.ballRadiusRange)
        c.ballCount = Self.clamp(ballCount, Self.ballCountRange)
        return c
    }

    /// Applies the ball count of a game mode preset.
    func applying(_ mode: GameMode) -> GameConfiguration {
        var c = self
        c.ballCount = mode.ballCount
        return c.validated()
    }

    private static func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Persistence

enum GameConfigurationStore {
    private static let key = "gameConfiguration"

    static func load() -> GameConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let config = try? JSONDecoder().decode(GameConfiguration.self, from: data) else {
            return GameConfiguration()
        }
        return config.validated()
    }

    static func save(_ configuration: GameConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration.validated()) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
