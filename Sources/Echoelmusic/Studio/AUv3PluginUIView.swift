#if canImport(UIKit) && canImport(AVFoundation)
import SwiftUI
import AVFoundation
import AudioToolbox
import CoreAudioKit
import UIKit

// AUv3PluginUIView.swift
// Echoel — embeds a hosted AUv3 plugin's OWN interface inside an Echoel-framed
// sheet. We ask the AU for its view controller (`requestViewController`) and add it
// as a child VC. If the plugin ships no custom UI, we say so honestly (iOS has no
// built-in generic parameter view like macOS's AUGenericView). See Audio/AUv3Host.swift.

/// Bridges an `AUAudioUnit`'s plugin view controller into SwiftUI.
struct AUv3PluginUIView: UIViewControllerRepresentable {
    let audioUnit: AUAudioUnit

    func makeUIViewController(context: Context) -> AUv3PluginContainerVC {
        let vc = AUv3PluginContainerVC()
        vc.embed(audioUnit)
        return vc
    }

    func updateUIViewController(_ vc: AUv3PluginContainerVC, context: Context) {}
}

/// Hosts the plugin's child view controller (or a "no custom UI" message).
final class AUv3PluginContainerVC: UIViewController {

    private let message = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        message.numberOfLines = 0
        message.textColor = .secondaryLabel
        message.font = .systemFont(ofSize: 13)
        message.textAlignment = .center
        message.translatesAutoresizingMaskIntoConstraints = false
        message.isHidden = true
        view.addSubview(message)
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            message.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            message.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    func embed(_ au: AUAudioUnit) {
        // `requestViewController` calls its completion on the main thread for view
        // requests — bridge to the MainActor synchronously (no value crosses an actor
        // boundary, so it's Swift-6 clean) and do the view-hierarchy work there.
        au.requestViewController { [weak self] childVC in
            MainActor.assumeIsolated { self?.attach(childVC) }
        }
    }

    private func attach(_ childVC: UIViewController?) {
        guard let childVC else {
            message.text = "This plugin has no custom interface on iOS."
            message.isHidden = false
            return
        }
        addChild(childVC)
        childVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(childVC.view)
        NSLayoutConstraint.activate([
            childVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            childVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            childVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            childVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        childVC.didMove(toParent: self)
    }
}
#endif
