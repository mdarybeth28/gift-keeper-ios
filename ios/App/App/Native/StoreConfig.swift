import Foundation

/// Everything about Gift Keeper's two payment doors, in one place.
///
/// The price is SETTLED and does not change here: $15.99 a year on
/// every door (web Stripe, Apple IAP). Mary's call, 2026-11-09 — it
/// replaced the old one-time price before any paying customer ever
/// arrived, and the live web app sells exactly this today.
///
/// APPLE IAP DOOR: the product ID below is a named constant, not an
/// App Store Connect fact yet. At submission time (after Mary's
/// Apple Developer enrollment activates) ONE auto-renewable
/// subscription product must be created in App Store Connect with
/// EXACTLY this ID, at $15.99/year:
///   - com.marybethsfinds.giftkeeper.yearly   (PROPOSED bundle id —
///     the bundle id itself locks only at first submission)
/// Until that product exists, Product.products(for:) returns
/// nothing and the paywall says so honestly (see PaywallView).
///
/// WEB STRIPE DOOR (link-out): the same payment link the web app's
/// gate uses ($15.99/yr — buy.stripe.com/14A9AT2O26mPfSd8030ZW04).
/// US storefront rules currently allow this link-out alongside IAP
/// with no entitlement; it sits behind ONE switchable flag so a
/// future rule change is a one-line switch, not a rebuild. The flag
/// is a plain constant today on purpose: flipping it ships in the
/// next build, and no server can silently change what a reviewed
/// build does.
enum StoreConfig {
    // MARK: Apple IAP product ID (create in App Store Connect, submission time)

    static let yearlyProductID = "com.marybethsfinds.giftkeeper.yearly"
    static let allProductIDs = [yearlyProductID]

    // MARK: US link-out door (switchable)

    /// Set to false to remove the "Pay on our website" door from
    /// the paywall entirely. US storefront only while true.
    static let linkOutEnabledUS = true

    static let webYearlyURL = URL(string: "https://buy.stripe.com/14A9AT2O26mPfSd8030ZW04")!

    // MARK: Owner account (mirrors the web app's OWNER_EMAIL)

    /// The web app carries ONE owner constant (OWNER_EMAIL in the
    /// live Gift Keeper web app): that email is the owner and is
    /// always in. Gift's isOwner() is a local email comparison,
    /// separate from the approved_emails gate — the native gate
    /// mirrors both halves: owner short-circuit here, RPC question
    /// for everyone else. (Pet Keeper's web app lists two owner
    /// emails; Gift's lists this one only — mirrored as found.)
    static let ownerEmails = [
        "marybeth.davis28@gmail.com",
    ]

    static func isOwner(email: String?) -> Bool {
        guard let email else { return false }
        return ownerEmails.contains(email.trimmingCharacters(in: .whitespaces).lowercased())
    }
}
