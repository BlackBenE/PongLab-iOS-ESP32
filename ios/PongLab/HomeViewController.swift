//
//  HomeViewController.swift
//  PongLab
//
//  Created by eliedev on 15/10/2026.
//


import UIKit
import SpriteKit

class HomeViewController: UIViewController, GameSceneDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationController?.overrideUserInterfaceStyle = .dark
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    // MARK: - UI

    private func setupUI() {
        let titleLabel = UILabel()
        titleLabel.text = "PONG"
        titleLabel.font = .monospacedSystemFont(ofSize: 48, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        let buttons = [
            makeButton(title: "Jouer", filled: true, action: #selector(playTapped)),
            makeButton(title: "Deux balles", filled: true, action: #selector(playTwoBallsTapped)),
            makeButton(title: "Paramètres", filled: false, action: #selector(settingsTapped)),
            makeButton(title: "Manettes", filled: false, action: #selector(controllersTapped))
        ]

        let stack = UIStackView(arrangedSubviews: [titleLabel] + buttons)
        stack.axis = .vertical
        stack.spacing = 20
        stack.setCustomSpacing(40, after: titleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 240)
        ])
    }

    private func makeButton(title: String, filled: Bool, action: Selector) -> UIButton {
        var config = filled ? UIButton.Configuration.filled() : UIButton.Configuration.bordered()
        config.title = title
        config.baseBackgroundColor = filled ? .white : .clear
        config.baseForegroundColor = filled ? .black : .white
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)

        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - Actions

    @objc private func playTapped() {
        startGame(with: GameConfigurationStore.load())
    }

    @objc private func playTwoBallsTapped() {
        startGame(with: GameConfigurationStore.load().applying(.twoBalls))
    }

    @objc private func settingsTapped() {
        open(SettingsViewController())
    }

    @objc private func controllersTapped() {
        open(ControllersViewController())
    }

    // MARK: - Navigation

    /// Works with or without a UINavigationController.
    private func open(_ viewController: UIViewController) {
        if let navigationController = navigationController {
            navigationController.pushViewController(viewController, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: viewController)
            nav.overrideUserInterfaceStyle = .dark
            nav.modalPresentationStyle = .fullScreen
            present(nav, animated: true)
        }
    }

    private func startGame(with configuration: GameConfiguration) {
        let gameScene = GameScene(size: view.bounds.size)
        gameScene.scaleMode = .aspectFill
        gameScene.gameSceneDelegate = self
        gameScene.configuration = configuration

        let skView = SKView(frame: view.bounds)
        skView.ignoresSiblingOrder = true
        skView.presentScene(gameScene)

        let gameViewController = UIViewController()
        gameViewController.view = skView
        gameViewController.modalPresentationStyle = .fullScreen
        present(gameViewController, animated: true)
    }

    // MARK: - GameSceneDelegate

    func didRequestReturnToHome() {
        // Removing the scene triggers willMove(from:), which stops HomeKit observation.
        (presentedViewController?.view as? SKView)?.presentScene(nil)
        dismiss(animated: true)
    }
}

// MARK: - Helper for screens presented modally (no navigation controller)

extension UIViewController {
    /// Adds a "Fermer" button when the screen is the root of a modally presented navigation controller.
    func addCloseButtonIfPresentedModally() {
        guard navigationController?.presentingViewController != nil,
              navigationController?.viewControllers.first === self else { return }
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Fermer", style: .done, target: self, action: #selector(closeModal))
    }

    @objc private func closeModal() {
        dismiss(animated: true)
    }
}
