import Foundation
import SwiftUI
import UIKit

@main
@MainActor
struct LyricFloatApp: App {
    var body: some Scene {
        WindowGroup {
            OverlayView()
        }
    }
}

@MainActor
private struct OverlayView: View {
    private enum Panel: String, Identifiable {
        case themes, timing
        var id: String { rawValue }
    }

    @StateObject private var model = OverlayModel()
    @AppStorage("lyricFloat.theme") private var themeID = LyricTheme.defaultID
    @State private var panel: Panel?
    @Environment(\.scenePhase) private var scenePhase

    private var theme: LyricTheme { LyricTheme.find(themeID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                track

                LyricsPreview(player: model.player, theme: theme)
                    .aspectRatio(720.0 / 320, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 20))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.currentLine)

                FloatingControls(model: model, player: model.player, theme: theme)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(theme.foreground)
        .background(theme.backdrop.ignoresSafeArea())
        .tint(theme.highlight)
        .preferredColorScheme(theme.colorScheme)
        .onAppear { model.setSceneActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            model.setSceneActive(phase == .active)
        }
        .onChange(of: themeID, initial: true) { _, id in
            model.applyTheme(LyricTheme.find(id))
        }
        .sheet(item: $panel) { panel in
            switch panel {
            case .themes:
                ThemePickerView(themeID: $themeID)
            case .timing:
                TimingAdjustmentView(model: model, theme: theme)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Lyric Float")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Button("Theme", systemImage: "paintpalette") { panel = .themes }
                if model.hasLyrics {
                    Button("Timing adjustment", systemImage: "clock") { panel = .timing }
                }
                if model.isSpotifyConnected {
                    Button("Disconnect Spotify", systemImage: "link.badge.minus", role: .destructive,
                           action: model.disconnectSpotify)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.foreground)
                    .frame(width: 44, height: 44)
                    .background(theme.surface, in: Circle())
            }
            .accessibilityLabel("Options")
        }
    }

    private var track: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.isSpotifyConnected {
                Label(model.hasLyrics && model.spotifyStatus == nil ? "Spotify synced" : "Following Spotify",
                      systemImage: "waveform")
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
            } else if model.canConnectSpotify {
                Button(model.isConnectingSpotify ? "Connecting…" : "Connect Spotify") {
                    Task { await model.connectSpotify() }
                }
                .buttonStyle(ThemedButtonStyle(theme: theme))
                .disabled(model.isConnectingSpotify)
            }

            if let title = model.title {
                Text(title)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                if let artist = model.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondary)
                }
            }

            if let message = model.spotifyStatus {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
            }
        }
    }
}

@MainActor
private struct FloatingControls: View {
    @ObservedObject var model: OverlayModel
    @ObservedObject var player: FloatingPlayer
    let theme: LyricTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.duration > 0 {
                VStack(spacing: 6) {
                    ProgressView(value: model.position, total: model.duration)
                        .accessibilityLabel("Playback position")
                        .accessibilityValue("\(format(model.position)) of \(format(model.duration))")

                    HStack {
                        Text(format(model.position))
                        Spacer()
                        Text(format(model.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.secondary)
                    .accessibilityHidden(true)
                }
            }

            Button {
                player.toggle()
            } label: {
                Label(player.isActive ? "Close floating window" : "Float lyrics",
                      systemImage: player.isActive ? "pip.exit" : "pip.enter")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ThemedButtonStyle(theme: theme))
            .disabled(player.isStarting || (!player.isActive && (!player.isPossible || !model.hasLyrics)))

            if !player.isSupported {
                Text("Picture in Picture is unavailable on this device.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
            } else if let error = player.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
            }
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ThemedButtonStyle: ButtonStyle {
    let theme: LyricTheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(
                LinearGradient(colors: [theme.highlight, theme.highlight2], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

@MainActor
private struct ThemePickerView: View {
    @Binding var themeID: String
    @Environment(\.dismiss) private var dismiss
    @State private var isChangingIcon = false
    @State private var iconMessage: String?

    private var selected: LyricTheme { LyricTheme.find(themeID) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(LyricTheme.all) { theme in
                        Button {
                            select(theme)
                        } label: {
                            HStack(spacing: 12) {
                                HStack(spacing: 3) {
                                    swatch(theme.surface)
                                    swatch(theme.highlight)
                                    swatch(theme.highlight2)
                                }
                                .accessibilityHidden(true)
                                Text(theme.name)
                                    .foregroundStyle(selected.foreground)
                                Spacer()
                                if selected.id == theme.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(selected.highlight)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.id == theme.id ? .isSelected : [])
                        .listRowBackground(selected.surface)
                        .disabled(isChangingIcon)
                    }
                } header: {
                    Text(iconMessage ?? "Choose a theme to match your Home Screen icon.")
                        .foregroundStyle(selected.secondary)
                        .textCase(nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(selected.backdrop.ignoresSafeArea())
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isChangingIcon)
                }
            }
        }
        .tint(selected.highlight)
        .preferredColorScheme(selected.colorScheme)
        .interactiveDismissDisabled(isChangingIcon)
    }

    private func select(_ theme: LyricTheme) {
        guard !isChangingIcon else { return }
        themeID = theme.id
        iconMessage = nil

        let app = UIApplication.shared
        let iconName = theme.alternateIconName
        guard app.alternateIconName != iconName else { return }
        guard app.supportsAlternateIcons else {
            iconMessage = "Home Screen icon changes are unavailable in this build."
            return
        }

        isChangingIcon = true
        Task {
            defer { isChangingIcon = false }
            do {
                try await app.setAlternateIconName(iconName)
            } catch {
                iconMessage = "Couldn’t change the Home Screen icon. Tap the theme to try again."
            }
        }
    }

    private func swatch(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(selected.foreground.opacity(0.18)))
    }
}

@MainActor
private struct TimingAdjustmentView: View {
    @ObservedObject var model: OverlayModel
    let theme: LyricTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: Binding(get: { model.adjustment }, set: { model.adjust(to: $0) }),
                            in: -10...10, step: 0.25) {
                        Text("\(model.adjustment.formatted(.number.precision(.fractionLength(2)))) seconds")
                            .foregroundStyle(theme.foreground)
                    }
                    .accessibilityLabel("Timing adjustment")
                    .listRowBackground(theme.surface)
                } footer: {
                    Text("A positive value shows lyrics earlier.")
                        .foregroundStyle(theme.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.backdrop.ignoresSafeArea())
            .navigationTitle("Timing adjustment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(theme.highlight)
        .preferredColorScheme(theme.colorScheme)
    }
}
