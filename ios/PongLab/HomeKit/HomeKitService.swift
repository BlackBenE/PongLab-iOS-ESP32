//
//  HomeKitService.swift
//  PongLab
//
//  Created by eliedev on 16/10/2026.
//
//
//  Single owner of HMHomeManager. HomeKit allows only ONE delegate per accessory,
//  so this service is that delegate and routes every update to the right
//  JoystickManager (by characteristic identifier).
//

import Foundation
import HomeKit

extension Notification.Name {
    static let joysticksDidChange = Notification.Name("joysticksDidChange")
}

enum JoystickStatus {
    case searching
    case unassigned
    case missing
    case unreachable(String)
    case connected(String)
}

final class HomeKitService: NSObject {

    static let shared = HomeKitService()

    struct Joystick {
        let accessory: HMAccessory
        let characteristic: HMCharacteristic

        var id: UUID { characteristic.uniqueIdentifier }
        var isReachable: Bool { accessory.isReachable }
        var displayName: String { "\(accessory.name) · \(characteristic.localizedDescription)" }
    }

    /// Text looked for in the characteristic description.
    static let characteristicKeyword = "Joystick X"

    private let assignmentsKey = "joystickAssignments"

    private var homeManager: HMHomeManager?
    private var users = 0
    private var managers: [JoystickManager] = []
    private var assignments: [Player: UUID] = [:]

    private(set) var joysticks: [Joystick] = []
    private(set) var isLoaded = false

    private override init() {
        super.init()
        assignments = loadAssignments()
    }

    // MARK: - Managers

    func register(_ manager: JoystickManager) {
        managers.append(manager)
        users += 1
        if homeManager == nil { startHomeKit() }
    }

    func unregister(_ manager: JoystickManager) {
        guard let index = managers.firstIndex(where: { $0 === manager }) else { return }
        managers.remove(at: index)
        users = max(0, users - 1)
        if users == 0 { stopHomeKit() }
        log("Manager unregistered. Active managers: \(managers.count)")
    }

    // MARK: - Queries

    func joystick(for player: Player) -> Joystick? {
        guard let id = assignments[player] else { return nil }
        return joysticks.first { $0.id == id }
    }

    func status(for player: Player) -> JoystickStatus {
        guard isLoaded else { return .searching }
        guard let id = assignments[player] else { return .unassigned }
        guard let joystick = joysticks.first(where: { $0.id == id }) else { return .missing }
        return joystick.isReachable ? .connected(joystick.displayName)
                                    : .unreachable(joystick.displayName)
    }

    // MARK: - Assignment edition

    func swapAssignments() {
        let first = assignments[.one]
        let second = assignments[.two]
        assignments[.one] = second
        assignments[.two] = first
        saveAssignments()
        notifyChanged()
    }

    func resetAssignments() {
        assignments = [:]
        saveAssignments()
        rescan()
    }

    // MARK: - HomeKit lifecycle

    private func startHomeKit() {
        log("Starting HomeKit")
        isLoaded = false
        let manager = HMHomeManager()
        manager.delegate = self
        homeManager = manager
    }

    private func stopHomeKit() {
        log("Stopping HomeKit")
        homeManager?.homes.forEach { $0.delegate = nil }
        joysticks.forEach { $0.accessory.delegate = nil }
        homeManager?.delegate = nil
        homeManager = nil
        joysticks = []
        isLoaded = false
    }

    private func rescan() {
        guard let manager = homeManager else { return }

        var found: [Joystick] = []
        for home in manager.homes {
            home.delegate = self
            for accessory in home.accessories {
                for hkService in accessory.services {
                    for characteristic in hkService.characteristics
                    where characteristic.localizedDescription
                        .localizedCaseInsensitiveContains(Self.characteristicKeyword) {
                        accessory.delegate = self
                        found.append(Joystick(accessory: accessory, characteristic: characteristic))
                    }
                }
            }
        }

        // Deterministic order, independent from HomeKit's discovery order.
        found.sort {
            ($0.accessory.name, $0.characteristic.localizedDescription, $0.id.uuidString)
            < ($1.accessory.name, $1.characteristic.localizedDescription, $1.id.uuidString)
        }

        joysticks = found
        isLoaded = true
        assignFreeJoysticks()
        found.forEach { log("Found \($0.displayName) [\($0.id)] reachable=\($0.isReachable)") }
        notifyChanged()
    }

    /// Gives still-unassigned players a joystick nobody uses yet. Existing assignments never change.
    private func assignFreeJoysticks() {
        let used = Set(assignments.values)
        var free = joysticks.filter { !used.contains($0.id) }
        for player in Player.allCases where assignments[player] == nil {
            guard !free.isEmpty else { break }
            assignments[player] = free.removeFirst().id
        }
        saveAssignments()
    }

    private func notifyChanged() {
        managers.forEach { $0.refresh() }
        NotificationCenter.default.post(name: .joysticksDidChange, object: self)
    }

    // MARK: - Persistence

    private func loadAssignments() -> [Player: UUID] {
        let raw = UserDefaults.standard.dictionary(forKey: assignmentsKey) as? [String: String] ?? [:]
        var result: [Player: UUID] = [:]
        for (key, value) in raw {
            if let player = Player(rawValue: key), let id = UUID(uuidString: value) {
                result[player] = id
            }
        }
        return result
    }

    private func saveAssignments() {
        var raw: [String: String] = [:]
        for (player, id) in assignments { raw[player.rawValue] = id.uuidString }
        UserDefaults.standard.set(raw, forKey: assignmentsKey)
    }

    private func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[HomeKitService] \(message())")
        #endif
    }
}

// MARK: - HMHomeManagerDelegate

extension HomeKitService: HMHomeManagerDelegate {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) { rescan() }
    func homeManager(_ manager: HMHomeManager, didAdd home: HMHome) { rescan() }
    func homeManager(_ manager: HMHomeManager, didRemove home: HMHome) { rescan() }
}

// MARK: - HMHomeDelegate

extension HomeKitService: HMHomeDelegate {
    func home(_ home: HMHome, didAdd accessory: HMAccessory) { rescan() }
    func home(_ home: HMHome, didRemove accessory: HMAccessory) { rescan() }
}

// MARK: - HMAccessoryDelegate

extension HomeKitService: HMAccessoryDelegate {
    func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        log("Reachability changed: \(accessory.name) -> \(accessory.isReachable)")
        notifyChanged()
    }

    func accessory(_ accessory: HMAccessory,
                   service: HMService,
                   didUpdateValueFor characteristic: HMCharacteristic) {
        let id = characteristic.uniqueIdentifier
        for manager in managers where manager.attachedID == id {
            manager.handle(value: characteristic.value)
        }
    }
}
