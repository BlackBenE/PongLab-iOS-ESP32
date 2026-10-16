//
//  GameMode.swift
//  pong_
//

import Foundation

enum GameMode {
    case standard
    case twoBalls

    var ballCount: Int {
        switch self {
        case .standard: return 1
        case .twoBalls: return 2
        }
    }
}
