import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global hotkey that toggles the launcher. Defaults to ⌥Space; the user can
    /// rebind it in Settings. The chosen shortcut is persisted automatically.
    static let toggleLauncher = Self("toggleLauncher", default: .init(.space, modifiers: [.option]))
}
