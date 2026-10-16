//
//  ControllersViewController.swift
//  PongLab
//
//  Created by eliedev on 16/10/2026.
//
//  Shows which joystick controls which paddle, their connection state, and lets
//  the player test each one live before starting a match.


import UIKit

final class ControllersViewController: UIViewController {

    private struct Card {
        let status: UILabel
        let bar: UIProgressView
    }

    private var cards: [Player: Card] = [:]
    private var testers: [Player: JoystickManager] = [:]
    private var changeObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Manettes"
        view.backgroundColor = .black
        addCloseButtonIfPresentedModally()
        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        startTesting()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopTesting()
    }

    // MARK: - UI

    private func buildUI() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        for player in Player.allCases {
            stack.addArrangedSubview(makeCard(for: player))
        }

        stack.addArrangedSubview(makeButton(title: "Échanger joueur 1 / joueur 2",
                                            action: #selector(swapTapped)))
        stack.addArrangedSubview(makeButton(title: "Réinitialiser les associations",
                                            action: #selector(resetTapped)))

        let hint = UILabel()
        hint.text = "Sans joystick, la raquette correspondante reste contrôlable au toucher."
        hint.textColor = .gray
        hint.font = .systemFont(ofSize: 13)
        hint.numberOfLines = 0
        stack.addArrangedSubview(hint)
    }

    private func makeCard(for player: Player) -> UIView {
        let title = UILabel()
        title.text = "\(player.displayName) — \(player.paddleDescription)"
        title.textColor = .white
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let status = UILabel()
        status.textColor = .lightGray
        status.font = .systemFont(ofSize: 14)
        status.numberOfLines = 0

        let bar = UIProgressView(progressViewStyle: .default)
        bar.progressTintColor = .white
        bar.trackTintColor = UIColor(white: 0.25, alpha: 1)

        cards[player] = Card(status: status, bar: bar)

        let stack = UIStackView(arrangedSubviews: [title, status, bar])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func makeButton(title: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.bordered()
        config.title = title
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - Testing

    private func startTesting() {
        guard testers.isEmpty else { return }

        changeObserver = NotificationCenter.default.addObserver(
            forName: .joysticksDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateStatuses()
        }

        for player in Player.allCases {
            let manager = JoystickManager(player: player)
            manager.onPositionChanged = { [weak self] value in
                self?.cards[player]?.bar.setProgress(Float(value), animated: false)
            }
            manager.onConnectionChanged = { [weak self] _ in
                self?.updateStatuses()
            }
            testers[player] = manager
            manager.start()
        }
        updateStatuses()
    }

    private func stopTesting() {
        testers.values.forEach { $0.stop() }
        testers.removeAll()
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
            changeObserver = nil
        }
    }

    private func updateStatuses() {
        for player in Player.allCases {
            let text: String
            switch HomeKitService.shared.status(for: player) {
            case .searching:
                text = "Recherche des accessoires…"
            case .unassigned:
                text = "Aucun joystick associé — contrôle tactile"
            case .missing:
                text = "Accessoire introuvable — contrôle tactile"
            case .unreachable(let name):
                text = "Connexion perdue : \(name) — contrôle tactile"
            case .connected(let name):
                text = "Connecté : \(name). Bougez le joystick pour le tester."
            }
            cards[player]?.status.text = text
        }
    }

    // MARK: - Actions

    @objc private func swapTapped() {
        HomeKitService.shared.swapAssignments()
    }

    @objc private func resetTapped() {
        HomeKitService.shared.resetAssignments()
    }
}
