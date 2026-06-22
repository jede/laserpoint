import SwiftUI

/// The Spotlight-style UI: a big search field on top, a scrolling list of
/// ranked results below. Keyboard navigation (arrows / enter / esc) is driven
/// by the hosting panel via the `SearchModel`, so this view stays declarative.
struct SearchView: View {
    @ObservedObject var model: SearchModel
    /// Called when the user commits (enter or click) — closes the panel.
    var onLaunch: () -> Void
    /// Called when the user dismisses (esc).
    var onDismiss: () -> Void

    @FocusState private var fieldFocused: Bool

    private let rowHeight: CGFloat = 48
    private let listPadding: CGFloat = 6
    private let maxVisibleRows = 8

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if !model.results.isEmpty {
                Divider()
                resultsList
            }
        }
        .frame(width: 640)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.18), value: model.launchingApp)
        .onAppear { fieldFocused = true }
        .onChange(of: model.focusRequest) { _, _ in
            // Re-focus after the window becomes key and the field is back in the
            // hierarchy. A tick of delay makes the focus assignment reliable.
            DispatchQueue.main.async { fieldFocused = true }
        }
    }

    private var searchField: some View {
        // Both states are laid out at a constant 64pt and crossfade by opacity,
        // so the container never changes size — this keeps the rounded-material
        // clip in sync with the window frame (no corner flicker on transition).
        ZStack(alignment: .leading) {
            // Search state — kept mounted (faded) while launching so focus and
            // layout stay stable.
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search apps…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .light))
                    .focused($fieldFocused)
                    .onSubmit { onLaunch() }
            }
            .opacity(model.launchingApp == nil ? 1 : 0)

            // Launching state overlay.
            if let app = model.launchingApp {
                HStack(spacing: 12) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text("Opening \(app.name)…")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
    }

    private var resultsList: some View {
        // Identify selection by the app itself, never by positional index — the
        // LazyVStack reuses rows by `id`, so an index-based highlight desyncs
        // from row content when the result set changes.
        let selectedID = model.selectedApp?.id

        // Deterministic height: a ScrollView reports a flexible size, which
        // breaks the panel's `fittingSize`. Size it to the visible rows so the
        // window can lay out correctly, and only scroll past `maxVisibleRows`.
        let visibleRows = min(model.results.count, maxVisibleRows)
        let listHeight = CGFloat(visibleRows) * rowHeight + listPadding * 2

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.results) { app in
                        ResultRow(app: app, isSelected: app.id == selectedID)
                            .id(app.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.select(app)
                                onLaunch()
                            }
                    }
                }
                .padding(listPadding)
            }
            .frame(height: listHeight)
            .onChange(of: model.selectedApp?.id) { _, newID in
                guard let newID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }
}

private struct ResultRow: View {
    let app: AppEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 32, height: 32)

            Text(app.name)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? .white : .primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor : .clear)
        )
    }
}
