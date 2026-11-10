import SwiftUI
import Capacitor

/// The one scoped home for web screens (Option A in the build plan):
/// the Capacitor bridge view controller, embedded in a tab. The web
/// content it shows is the app's BUNDLED local assets — Capacitor is
/// configured without any `server.url`, so this can never become a
/// remote window onto the live website.
///
/// PHASE 1 SEAM — the first thing the first real CI build verifies:
/// that this plain `CAPBridgeViewController()` embedding compiles and
/// boots alongside the native tabs. If Capacitor's embedding API has
/// moved, this file (and only this file) is where the fix lands.
struct WebTabView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CAPBridgeViewController {
        CAPBridgeViewController()
    }

    func updateUIViewController(_ uiViewController: CAPBridgeViewController, context: Context) {
        // The bridge manages its own lifecycle; nothing to update.
    }
}
