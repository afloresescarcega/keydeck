import SwiftUI
import KeyDeckKit
import UIKit

@main
struct KeyDeckApp: App {
    @State private var sessionManager = VoiceSessionManager()
    @State private var selectedTab: AppTab = .voice

    var body: some Scene {
        WindowGroup {
            ContentView(
                sessionManager: sessionManager,
                selectedTab: $selectedTab
            )
            .tint(sessionManager.settings.accentColor.swiftUIColor)
            .onAppear {
                applyWindowTint(sessionManager.settings.accentColor)
            }
            .onChange(of: sessionManager.settings.accentColor) { _, newValue in
                applyWindowTint(newValue)
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    private func applyWindowTint(_ accent: KeyDeckAccentColor) {
        let color = accent.uiKitColor
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.tintColor = color
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == KeyDeckConstants.urlScheme else { return }

        if url.host == "settings" {
            selectedTab = .settings
            return
        }

        if url.host == "voice" {
            selectedTab = .voice
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let modeRaw = components?.queryItems?.first(where: { $0.name == "mode" })?.value
            let mode = modeRaw.flatMap(VoiceMode.init(rawValue:)) ?? .rambler
            let reqID = components?.queryItems?
                .first(where: { $0.name == "requestId" })?.value
                .flatMap(UUID.init(uuidString:))

            Task {
                if url.path == "/arm" { // NOSONAR: fixed deep-link route
                    await sessionManager.armSession()
                } else if url.path == "/disarm" { // NOSONAR: fixed deep-link route
                    await sessionManager.disarmSession()
                } else {
                    await sessionManager.handleExternalStart(mode: mode, requestID: reqID)
                }
            }
        }
    }
}

enum AppTab: Hashable {
    case voice
    case history
    case workflows
    case settings
}

extension KeyDeckAccentColor {
    var swiftUIColor: Color {
        switch self {
        case .blue: .blue
        case .graphite: Color(.label)
        case .teal: .teal
        case .orange: .orange
        case .green: .green
        case .indigo: .indigo
        case .pink: .pink
        }
    }

    var uiKitColor: UIColor {
        switch self {
        case .blue: .systemBlue
        case .graphite: .label
        case .teal: .systemTeal
        case .orange: .systemOrange
        case .green: .systemGreen
        case .indigo: .systemIndigo
        case .pink: .systemPink
        }
    }
}
