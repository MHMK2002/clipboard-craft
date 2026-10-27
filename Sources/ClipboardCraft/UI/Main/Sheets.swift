import Combine
import SwiftUI

// MARK: - Collection editor

struct CollectionEditorView: View {
    let state: CollectionEditorState
    let store: ClipStore
    let library: LibraryModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var symbol = "folder.fill"
    @State private var color: CollectionColor = .blue

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(color.color.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: color.color.opacity(0.4), radius: 8, y: 3)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.existing == nil ? "New Collection" : "Edit Collection").font(.title3.weight(.semibold))
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(CollectionColor.allCases) { c in
                        Circle()
                            .fill(c.color.gradient)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(.white, lineWidth: color == c ? 2.5 : 0))
                            .overlay(Circle().strokeBorder(c.color, lineWidth: color == c ? 1 : 0).padding(-3))
                            .onTapGesture { withAnimation(.spring(response: 0.25)) { color = c } }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 8), spacing: 8) {
                    ForEach(ClipCollection.symbolChoices, id: \.self) { s in
                        Image(systemName: s)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(symbol == s ? .white : .primary)
                            .frame(width: 34, height: 34)
                            .background(symbol == s ? AnyShapeStyle(color.color.gradient) : AnyShapeStyle(.primary.opacity(0.06)),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .onTapGesture { withAnimation(.spring(response: 0.25)) { symbol = s } }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(state.existing == nil ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            if let c = state.existing { name = c.name; symbol = c.symbol; color = c.color }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if var c = state.existing {
            c.name = trimmed; c.symbol = symbol; c.color = color
            store.updateCollection(c)
        } else {
            let c = store.createCollection(name: trimmed, symbol: symbol, color: color)
            if !state.addingItems.isEmpty {
                store.setCollection(c.id, member: true, for: state.addingItems)
                store.showToast("Added to \(c.name)", symbol: c.symbol)
            }
        }
        dismiss()
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    var onDone: () -> Void
    @State private var hasAccess = AppServices.shared.paste.hasAccessibilityAccess
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            AppIconBadge(size: 84)
            VStack(spacing: 6) {
                Text("Welcome to Clipboard Craft").font(.system(size: 24, weight: .bold))
                Text("Your smarter clipboard companion").font(.system(size: 14)).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                feature("clock.arrow.circlepath", .blue, "Everything you copy, remembered",
                        "Text, links, code, colors, images and real files — searchable instantly.")
                feature("keyboard", .purple, "Always one shortcut away",
                        "Press \(AppSettings.shared.quickPanelShortcuts.first?.displayString ?? "your shortcut") anywhere, type to search, hit ↩ to paste.")
                feature("pin.fill", .orange, "Pin, star and organise",
                        "Keep important clips forever and group them into collections.")
            }
            .padding(18)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 12) {
                Image(systemName: hasAccess ? "checkmark.seal.fill" : "hand.raised.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(hasAccess ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasAccess ? "Direct paste is enabled" : "Allow direct paste").font(.system(size: 13, weight: .semibold))
                    Text(hasAccess ? "Clips are pasted straight into the app you’re using."
                                   : "Grant Accessibility access so ↩ pastes into the active app.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                if !hasAccess {
                    VStack(alignment: .trailing, spacing: 4) {
                        Button("Grant Access…") {
                            AppServices.shared.paste.requestAccessibilityAccess()
                            AppServices.shared.paste.openAccessibilitySettings()
                        }
                        .buttonStyle(.glass)
                        Button("Enabled it? Restart") { AppServices.shared.paste.relaunch() }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                }
            }
            .padding(14)
            .background((hasAccess ? Color.green : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                AppSettings.shared.hasCompletedOnboarding = true
                onDone()
            } label: {
                Text("Get Started").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 500)
        .onReceive(timer) { _ in hasAccess = AppServices.shared.paste.hasAccessibilityAccess }
    }

    private func feature(_ symbol: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The app icon rendered from the bundle, with a fallback.
struct AppIconBadge: View {
    var size: CGFloat = 64
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
            .resizable()
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }
}
