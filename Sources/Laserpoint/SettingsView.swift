import KeyboardShortcuts
import SwiftUI

/// Minimal settings: rebind the global hotkey and toggle launch-at-login. The
/// recorder persists and re-registers the shortcut automatically.
struct SettingsView: View {
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Toggle Laserpoint:", name: .toggleLauncher)

            Toggle("Start at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    LoginItem.setEnabled(enabled)
                }

            Text("Press the shortcut anywhere to open the launcher.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380)
        // Re-read in case the login item was changed in System Settings.
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }
}
