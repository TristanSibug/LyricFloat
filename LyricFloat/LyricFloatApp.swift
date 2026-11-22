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
        case search, timing
        var id: String { rawValue }
    }

    @StateObject private var model = OverlayModel()
    @State private var panel: Panel?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                track
                LyricsPreview(player: model.player)
                    .aspectRatio(720.0 / 320, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 20))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.currentLine)

                FloatingControls(model: model, player: model.player)

                Button {
                    panel = .search
                } label: {
                    Label("Find lyrics", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(
            (colorScheme == .dark
             ? Color(red: 0.09, green: 0.07, blue: 0.11)
             : Color(red: 0.98, green: 0.97, blue: 0.99))
                .ignoresSafeArea()
        )
        .tint(colorScheme == .dark
              ? Color(red: 0.40, green: 0.23, blue: 0.48)
              : Color(red: 0.30, green: 0.15, blue: 0.35))
        .onAppear { model.setSceneActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            model.setSceneActive(phase == .active)
        }
        .sheet(item: $panel) { panel in
            switch panel {
            case .search:
                LyricsSearchView(catalog: model.catalog, onSelect: model.selectSong)
            case .timing:
                TimingAdjustmentView(model: model)
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
            if model.isSpotifyConnected || model.hasLyrics {
                Menu {
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
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(.quaternary, in: Circle())
                }
                .accessibilityLabel("Options")
            }
        }
    }

    private var track: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.followsSpotify {
                Label(model.hasLyrics && model.spotifyStatus == nil ? "Spotify synced" : "Following Spotify",
                      systemImage: "waveform")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if model.canConnectSpotify {
                if model.isSpotifyConnected {
                    Button("Follow Spotify", systemImage: "waveform", action: model.followSpotify)
                        .buttonStyle(.bordered)
                } else {
                    Button(model.isConnectingSpotify ? "Connecting…" : "Connect Spotify") {
                        Task { await model.connectSpotify() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isConnectingSpotify)
                }
            }

            if let title = model.title {
                Text(title)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                if let artist = model.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = model.spotifyStatus {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private struct FloatingControls: View {
    @ObservedObject var model: OverlayModel
    @ObservedObject var player: FloatingPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.duration > 0 {
                VStack(spacing: 6) {
                    if model.followsSpotify {
                        ProgressView(value: model.position, total: model.duration)
                            .accessibilityLabel("Playback position")
                            .accessibilityValue("\(format(model.position)) of \(format(model.duration))")
                    } else {
                        Slider(value: Binding(get: { model.position }, set: { model.seek(to: $0) }),
                               in: 0...model.duration)
                            .accessibilityLabel("Lyrics position")
                            .accessibilityValue(format(model.position))
                    }

                    HStack {
                        Text(format(model.position))
                        Spacer()
                        Text(format(model.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                }
            }

            if model.hasLyrics, !model.followsSpotify {
                Button(action: model.isPlaying ? model.pause : model.play) {
                    Label(model.isPlaying ? "Pause lyrics" : "Start lyrics",
                          systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
            }

            Button {
                player.toggle()
            } label: {
                Label(player.isActive ? "Close floating window" : "Float lyrics",
                      systemImage: player.isActive ? "pip.exit" : "pip.enter")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .controlSize(.large)
            .disabled(player.isStarting || (!player.isActive && (!player.isPossible || !model.hasLyrics)))

            if !player.isSupported {
                Text("Picture in Picture is unavailable on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let error = player.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

@MainActor
private struct TimingAdjustmentView: View {
    @ObservedObject var model: OverlayModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: Binding(get: { model.adjustment }, set: { model.adjust(to: $0) }),
                            in: -10...10, step: 0.25) {
                        Text("\(model.adjustment.formatted(.number.precision(.fractionLength(2)))) seconds")
                    }
                    .accessibilityLabel("Timing adjustment")
                } footer: {
                    Text("A positive value shows lyrics earlier.")
                }
            }
            .navigationTitle("Timing adjustment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

@MainActor
private struct LyricsSearchView: View {
    private enum Field: Hashable { case title, artist }

    let catalog: LyricsCatalog
    let onSelect: (LyricsCatalog.Song) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var title = ""
    @State private var artist = ""
    @State private var results: [LyricsCatalog.Song] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Song title", text: $title)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.search)
                    TextField("Artist (optional)", text: $artist)
                        .focused($focusedField, equals: .artist)
                        .submitLabel(.search)
                    Button("Search", action: search)
                        .disabled(searchTask != nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if searchTask != nil {
                    ProgressView("Searching…")
                } else if let message {
                    Text(message)
                        .foregroundStyle(.secondary)
                }

                ForEach(results) { song in
                    Button {
                        onSelect(song)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(song.title)
                                .foregroundStyle(.primary)
                            let totalSeconds = Int(song.duration)
                            let duration = String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
                            let details = [song.artist, song.album ?? "", duration].filter { !$0.isEmpty }
                            Text(details.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Find lyrics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onSubmit(search)
            .onAppear { focusedField = .title }
            .onDisappear {
                searchTask?.cancel()
                searchTask = nil
            }
        }
    }

    private func search() {
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, searchTask == nil else { return }
        focusedField = nil
        results = []
        message = nil
        let artist = self.artist
        searchTask = Task {
            do {
                let songs = try await catalog.search(title: query, artist: artist)
                try Task.checkCancellation()
                results = songs
                if songs.isEmpty { message = "No timed lyrics found. Try another title or artist." }
            } catch {
                guard !Task.isCancelled else { return }
                message = error.localizedDescription
            }
            searchTask = nil
        }
    }
}
