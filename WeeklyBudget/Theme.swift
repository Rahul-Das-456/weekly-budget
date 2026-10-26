import SwiftUI
import UIKit

/// The look of the app, picked in Settings and remembered on the phone.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark, pink, hacker

    static let storageKey = "theme"

    /// The theme saved in Settings, for code that runs outside a view.
    static var saved: AppTheme {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppTheme.init) ?? .system
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "Match phone"
        case .light: "Light"
        case .dark: "Dark"
        case .pink: "Pink"
        case .hacker: "Hacker"
        }
    }

    var icon: String {
        switch self {
        case .system: "iphone"
        case .light: "sun.max"
        case .dark: "moon"
        case .pink: "heart"
        case .hacker: "terminal"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light, .pink: .light
        case .dark, .hacker: .dark
        }
    }

    /// Buttons, progress bars and highlights.
    var accent: Color {
        switch self {
        case .system, .light, .dark: .accentColor
        case .pink: Color(red: 1.0, green: 0.42, blue: 0.68)
        case .hacker: Color(red: 0.0, green: 1.0, blue: 0.25)
        }
    }

    /// Text on filled accent-colored buttons.
    var onAccent: Color {
        switch self {
        case .hacker: .black
        default: .white
        }
    }

    /// Page background behind the cards, or nil for the system color.
    var background: LinearGradient? {
        switch self {
        case .system, .light, .dark: nil
        case .pink: LinearGradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.93),
                                            Color(red: 0.95, green: 0.89, blue: 1.0)],
                                   startPoint: .top, endPoint: .bottom)
        case .hacker: LinearGradient(colors: [.black], startPoint: .top, endPoint: .bottom)
        }
    }

    /// Card background, or nil for the system color.
    var card: Color? {
        switch self {
        case .system, .light, .dark: nil
        case .pink: Color(red: 1.0, green: 0.97, blue: 0.98)
        case .hacker: Color(red: 0.03, green: 0.09, blue: 0.04)
        }
    }

    /// Main text color, or nil for the system color.
    var text: Color? {
        switch self {
        case .system, .light, .dark: nil
        case .pink: Color(red: 0.62, green: 0.2, blue: 0.45)
        case .hacker: Color(red: 0.0, green: 1.0, blue: 0.25)
        }
    }

    /// Category icon color, or nil to match the text.
    var iconColor: Color? {
        self == .pink ? accent : nil
    }

    /// Font for all text, or nil to leave each view's own font alone.
    var fontDesign: Font.Design? {
        switch self {
        case .system, .light, .dark: nil
        case .pink: .rounded
        case .hacker: .monospaced
        }
    }

    /// Font for the big money totals.
    var displayDesign: Font.Design {
        switch self {
        case .system, .light, .dark: .serif
        case .pink: .rounded
        case .hacker: .monospaced
        }
    }

    /// Separator in the "THIS WEEK" header.
    var separator: String { self == .pink ? "♡" : "·" }

    /// Icon on the Add expense button.
    var addIcon: String { self == .pink ? "heart.fill" : "plus" }

    /// Screen titles are drawn by UIKit, so their color and font are set here rather than in SwiftUI.
    /// They only affect title bars created afterwards, so the main screen rebuilds its bar after a change.
    @MainActor func applyToNavigationBars() {
        let bar = UINavigationBar.appearance()
        guard let text else {
            bar.largeTitleTextAttributes = nil
            bar.titleTextAttributes = nil
            return
        }
        let design: UIFontDescriptor.SystemDesign = self == .hacker ? .monospaced : .rounded
        bar.largeTitleTextAttributes = [.foregroundColor: UIColor(text), .font: Self.font(.largeTitle, design: design)]
        bar.titleTextAttributes = [.foregroundColor: UIColor(text), .font: Self.font(.headline, design: design)]
    }

    private static func font(_ style: UIFont.TextStyle, design: UIFontDescriptor.SystemDesign) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style).fontDescriptor
        let descriptor = (base.withSymbolicTraits(.traitBold) ?? base).withDesign(design) ?? base
        return UIFont(descriptor: descriptor, size: 0)
    }
}

/// Applies the chosen theme to a screen. Use it on the root of every screen and sheet,
/// since sheets don't pick up the color scheme from the screen that presents them.
private struct ThemedModifier: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    func body(content: Content) -> some View {
        content
            .tint(theme.accent)
            .foregroundStyle(theme.text.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
            .fontDesign(theme.fontDesign)
            .preferredColorScheme(theme.colorScheme)
    }
}

/// Gives a List or Form the theme's page background.
private struct ThemedListModifier: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    func body(content: Content) -> some View {
        if let background = theme.background {
            content.scrollContentBackground(.hidden).background(background)
        } else {
            content
        }
    }
}

/// Gives a row the theme's card background.
private struct ThemedRowModifier: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    func body(content: Content) -> some View {
        if let card = theme.card {
            content.listRowBackground(card)
        } else {
            content
        }
    }
}

/// A Label whose icon takes the theme's icon color.
struct ThemedLabel: View {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let color = theme.iconColor {
                Image(systemName: systemImage).foregroundStyle(color)
            } else {
                Image(systemName: systemImage)
            }
        }
    }
}

extension View {
    func themed() -> some View { modifier(ThemedModifier()) }
    func themedList() -> some View { modifier(ThemedListModifier()) }
    func themedRow() -> some View { modifier(ThemedRowModifier()) }
}
