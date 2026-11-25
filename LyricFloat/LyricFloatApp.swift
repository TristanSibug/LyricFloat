import Foundation
import SwiftUI

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
        case themes, appIcon, font, timing
        var id: String { rawValue }
    }

    @StateObject private var model = OverlayModel()
    @AppStorage("lyricFloat.theme") private var themeID = LyricTheme.defaultID
    @AppStorage("lyricFloat.font") private var lyricFont = LyricFont.system
    @State private var panel: Panel?
    @Environment(\.scenePhase) private var scenePhase

    private var theme: LyricTheme { LyricTheme.find(themeID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let title = model.title {
                    track(title: title)
                        .padding(.top, 6)
                }

                LyricsPreview(player: model.player, theme: theme)
                    .aspectRatio(720.0 / 320, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 20))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.currentLine)

                FloatingControls(model: model, player: model.player, liveActivity: model.liveActivity,
                                 lockedLyrics: model.lockedLyrics, theme: theme)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 18)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(theme.foreground)
        .background(theme.backdrop.ignoresSafeArea())
        .tint(theme.highlight)
        .preferredColorScheme(theme.colorScheme)
        .onOpenURL { model.handleSpotifyCallback($0) }
        .onAppear { model.setSceneActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            model.setSceneActive(phase == .active)
        }
        .onChange(of: themeID, initial: true) { _, id in
            model.applyTheme(LyricTheme.find(id))
        }
        .onChange(of: lyricFont, initial: true) { _, font in
            model.applyFont(font)
        }
        .sheet(item: $panel) { panel in
            switch panel {
            case .themes:
                ThemePickerView(themeID: $themeID)
            case .appIcon:
                AppIconPickerView(theme: theme)
            case .font:
                LyricFontPickerView(selection: $lyricFont, theme: theme)
            case .timing:
                TimingAdjustmentView(model: model, theme: theme)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBar

            if !model.isSpotifyConnected, model.canConnectSpotify {
                Button(model.isConnectingSpotify ? "Connecting…" : "Connect Spotify") {
                    Task { await model.connectSpotify() }
                }
                .buttonStyle(ThemedButtonStyle(theme: theme))
                .disabled(model.isConnectingSpotify)
            }

            if let message = model.spotifyStatus {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
            }
        }
    }

    private var titleBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lyric Float")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                if model.isSpotifyConnected {
                    Label(model.spotifyStatus == nil ? "Spotify connected" : "Spotify connection interrupted",
                          systemImage: model.spotifyStatus == nil ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(theme.secondary)
                }
            }

            Spacer()
            Menu {
                Button("Theme", systemImage: "paintpalette") { panel = .themes }
                Button("App Icon", systemImage: "app") { panel = .appIcon }
                Button("Font", systemImage: "textformat") { panel = .font }
                if model.hasLyrics {
                    Button("Timing adjustment", systemImage: "clock") { panel = .timing }
                }
                if model.canDisconnectSpotify {
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

    private func track(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)

            if let artist = model.artist, !artist.isEmpty {
                Text(artist)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondary)
            }
        }
    }
}

@MainActor
private struct FloatingControls: View {
    @ObservedObject var model: OverlayModel
    @ObservedObject var player: FloatingPlayer
    @ObservedObject var liveActivity: LyricLiveActivity
    @ObservedObject var lockedLyrics: LockedLyricsSession
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

            Button(action: model.toggleLockScreenLyrics) {
                Label(liveActivity.isActive ? "Remove from Lock Screen" : "Show on Lock Screen",
                      systemImage: liveActivity.isActive ? "iphone.slash" : "lock.iphone")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(!liveActivity.isActive && !model.canShowLockScreenLyrics)
            .opacity(liveActivity.isActive || model.canShowLockScreenLyrics ? 1 : 0.45)

            if let message = liveActivity.message ?? lockedLyrics.message {
                Text(message)
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
