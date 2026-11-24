import SwiftUI
import KeyDeckKit

struct ContentView: View {
    @Bindable var sessionManager: VoiceSessionManager
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            VoiceHomeView(sessionManager: sessionManager, selectedTab: $selectedTab)
                .tabItem {
                    Label("Voice", systemImage: "waveform.and.mic")
                }
                .tag(AppTab.voice)

            TranscriptLogView(sessionManager: sessionManager)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(AppTab.history)

            WorkflowsPlaceholderView()
                .tabItem {
                    Label("Palette", systemImage: "command")
                }
                .tag(AppTab.workflows)

            SettingsView(sessionManager: sessionManager)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .sheet(isPresented: $sessionManager.consentPromptRequested) {
            AIConsentView { allowed in
                sessionManager.settings.aiDataSharingConsent = allowed
            }
        }
    }
}
