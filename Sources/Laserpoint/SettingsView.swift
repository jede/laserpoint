import KeyboardShortcuts
import SwiftUI

/// Settings: rebind the global hotkey, toggle launch-at-login, and manage the
/// prefix shortcuts (e.g. `w …`, `c …`).
struct SettingsView: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @ObservedObject private var store = ShortcutStore.shared

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

            Divider()
                .padding(.vertical, 4)

            shortcutsSection
        }
        .padding(20)
        .frame(width: 460)
        // Re-read in case the login item was changed in System Settings.
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shortcuts")
                .font(.headline)
            Text("Type the key, a space, then your text — e.g. “w swift docs”. Use {query} in a URL where the text should go.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($store.definitions) { $definition in
                ShortcutEditor(definition: $definition) { store.remove(definition) }
                Divider()
            }

            Button {
                store.addDefault()
            } label: {
                Label("Add shortcut", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// One editable shortcut row: trigger key, name, destination type, and (for a
/// URL destination) the URL template.
private struct ShortcutEditor: View {
    @Binding var definition: ShortcutDefinition
    let onDelete: () -> Void

    private enum Kind: Hashable { case webSearch, url }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("key", text: $definition.key)
                    .frame(width: 44)
                    .multilineTextAlignment(.center)

                TextField("Name", text: $definition.name)

                Picker("", selection: kind) {
                    Text("Web search").tag(Kind.webSearch)
                    Text("Open URL").tag(Kind.url)
                }
                .labelsHidden()
                .frame(width: 130)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            if kind.wrappedValue == .url {
                TextField("https://example.com/?q={query}", text: template)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var kind: Binding<Kind> {
        Binding(
            get: {
                if case .webSearch = definition.action { return .webSearch }
                return .url
            },
            set: { newKind in
                switch newKind {
                case .webSearch:
                    definition.action = .webSearch
                case .url:
                    if case .urlTemplate = definition.action { return }
                    definition.action = .urlTemplate("https://example.com/?q={query}")
                }
            }
        )
    }

    private var template: Binding<String> {
        Binding(
            get: {
                if case .urlTemplate(let value) = definition.action { return value }
                return ""
            },
            set: { definition.action = .urlTemplate($0) }
        )
    }
}
