import SwiftUI
import UIKit

extension View {
    /// Keeps swipe-to-go-back working on a page that hides the system back button and draws its own.
    func keepsSwipeBack() -> some View { background(SwipeBackEnabler().frame(width: 0, height: 0)) }
}

/// Puts the navigation controller's edge swipe back in charge (it switches off when the back button is hidden).
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let nav = navigationController, let swipe = nav.interactivePopGestureRecognizer else { return }
            swipe.delegate = SwipeBackDelegate.shared
            swipe.isEnabled = true
        }
    }
}

/// Allows the swipe whenever there's a page to go back to.
@MainActor
private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackDelegate()
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = findNav(gestureRecognizer.view) else { return false }
        return nav.viewControllers.count > 1
    }

    private func findNav(_ view: UIView?) -> UINavigationController? {
        var r: UIResponder? = view
        while let next = r { if let nav = next as? UINavigationController { return nav }; r = next.next }
        return nil
    }
}
