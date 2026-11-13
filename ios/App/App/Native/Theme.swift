import SwiftUI

/// Gift Keeper's brand colors, taken from the web app's own
/// palette (giftkeepersecret.com's CSS variables — the site's
/// :root plus its own theme override that turns the shared
/// template's "green" names into Gift's burnt orange) so the app
/// and the website wear the same dress: cream page, white cards,
/// burnt orange buttons, dark brown headings, soft tan fills.
enum Theme {
    static let page = Color(red: 0.980, green: 0.965, blue: 0.937)      // #FAF6EF
    static let card = Color.white                                      // #FFFFFF
    static let ink = Color(red: 0.169, green: 0.169, blue: 0.149)       // #2B2B26
    static let muted = Color(red: 0.435, green: 0.416, blue: 0.369)     // #6F6A5E
    static let line = Color(red: 0.890, green: 0.867, blue: 0.816)      // #E3DDD0
    static let orange = Color(red: 0.639, green: 0.302, blue: 0.129)    // #A34D21 (web --green)
    static let brown = Color(red: 0.431, green: 0.231, blue: 0.118)     // #6E3B1E (web --green-dark)
    static let soft = Color(red: 0.973, green: 0.925, blue: 0.824)      // #F8ECD2 (web --green-soft)
    static let amber = Color(red: 0.541, green: 0.427, blue: 0.102)     // #8A6D1A
    static let amberSoft = Color(red: 0.984, green: 0.953, blue: 0.851) // #FBF3D9
    static let warn = Color(red: 0.702, green: 0.149, blue: 0.118)      // #B3261E
    static let warnSoft = Color(red: 0.984, green: 0.918, blue: 0.910)  // #FBEAE8
}

/// The web app's main button, natively: burnt orange, white words,
/// rounded corners.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.orange, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

/// The web app's quiet second button: white with a brown outline.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.brown)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.orange, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

/// The web app's card: white, rounded, a hairline border.
struct GiftCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }
}

extension View {
    func giftCard() -> some View { modifier(GiftCardModifier()) }
}
