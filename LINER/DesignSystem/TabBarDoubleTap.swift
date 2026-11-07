import SwiftUI
import UIKit

extension View {
    /// Calls `action` when the tab bar is double-tapped while the first tab (Home) is selected. Single taps still
    /// go through to the tab bar as usual.
    func onHomeTabDoubleTap(_ action: @escaping @MainActor () -> Void) -> some View {
        background(TabBarDoubleTap(action: action).frame(width: 0, height: 0))
    }
}

/// Hooks a double-tap recogniser onto the real tab bar (SwiftUI doesn't report a second tap on the tab that's
/// already selected).
private struct TabBarDoubleTap: UIViewControllerRepresentable {
    let action: @MainActor () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(action: action) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.action = action }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var action: @MainActor () -> Void
        private weak var installedOn: UITabBar?

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let bar = tabBarController?.tabBar, installedOn !== bar else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
            tap.numberOfTapsRequired = 2
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            bar.addGestureRecognizer(tap)
            installedOn = bar
        }

        @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
            // The first tap of the pair selects the tab, so Home is selected by now if that's where it landed.
            guard tabBarController?.selectedIndex == 0 else { return }
            action()
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
