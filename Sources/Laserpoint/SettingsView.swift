import KeyboardShortcuts
import SwiftUI

/// Minimal settings: rebind the global hotkey. The recorder persists and
/// re-registers the shortcut automatically.
struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Toggle Laserpoint:", name: .toggleLauncher)
            Text("Press the shortcut anywhere to open the launcher.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380)
    }
}
