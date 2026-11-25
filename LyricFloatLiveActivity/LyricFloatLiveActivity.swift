import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LyricFloatLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricActivityAttributes.self) { context in
            let theme = LyricTheme.find(context.state.themeID)
            let font = LyricFont(rawValue: context.state.fontID) ?? .system

            Group {
                if context.isStale {
                    Text("Tap to refresh")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondary)
                } else {
                    Text(context.state.line)
                        .font(Font(font.uiFont(size: 20, weight: .semibold)))
                        .foregroundStyle(theme.foreground)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .activityBackgroundTint(theme.surface)
            .activitySystemActionForegroundColor(theme.foreground)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Label(context.state.title, systemImage: "music.note")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "music.note").accessibilityLabel("Lyric Float")
            } compactTrailing: {
                Image(systemName: context.isStale ? "arrow.clockwise" : "waveform")
                    .accessibilityLabel(context.isStale ? "Lyrics need refresh" : "Lyric Float active")
            } minimal: {
                Image(systemName: "music.note").accessibilityLabel("Lyric Float")
            }
        }
    }
}
