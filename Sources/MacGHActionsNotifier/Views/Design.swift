import SwiftUI

enum Design {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.08)
    static let green = Color(red: 0.06, green: 0.62, blue: 0.38)
    static let blue = Color(red: 0.10, green: 0.42, blue: 0.90)
    static let red = Color(red: 0.88, green: 0.18, blue: 0.20)
    static let orange = Color(red: 0.93, green: 0.50, blue: 0.12)
}

struct AppLogoView: View {
    var size: CGFloat

    var body: some View {
        Group {
            if let image = NSImage(named: "AppIcon") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Design.green)
                    .padding(size * 0.18)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityLabel("GitHub Actions Notifier logo")
    }
}

extension AppStatus {
    var accent: Color {
        switch self {
        case .idle: .secondary
        case .success: Design.green
        case .running: Design.blue
        case .failed: Design.red
        case .problem: Design.orange
        }
    }
}
