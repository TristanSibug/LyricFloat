import SwiftUI
import UIKit

@MainActor
private struct AppearancePickerSheet<Content: View>: View {
    let title: String
    let theme: LyricTheme
    var isBusy = false
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                content.padding(20)
            }
            .background(theme.backdrop)
            .foregroundStyle(theme.foreground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isBusy)
                }
            }
            .toolbarBackground(theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(theme.highlight)
        .preferredColorScheme(theme.colorScheme)
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.backdrop)
        .interactiveDismissDisabled(isBusy)
    }
}

@MainActor
struct ThemePickerView: View {
    @Binding var themeID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var selected: LyricTheme { LyricTheme.find(themeID) }

    var body: some View {
        AppearancePickerSheet(title: "Theme", theme: selected) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                      count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                ForEach(LyricTheme.all) { theme in
                    let isSelected = selected.id == theme.id
                    let shape = RoundedRectangle(cornerRadius: 16)
                    Button {
                        themeID = theme.id
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(theme.id == "signal-blue" ? theme.surface : theme.highlight)
                                    .frame(width: 16, height: 16)
                                Circle().fill(theme.highlight2).frame(width: 16, height: 16)
                                Spacer(minLength: 0)
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(theme.highlight)
                                }
                            }
                            .accessibilityHidden(true)
                            Text(theme.name)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(theme.foreground)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.backdrop, in: shape)
                        .overlay(shape.strokeBorder(isSelected ? theme.highlight : theme.foreground.opacity(0.1)))
                        .contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

@MainActor
struct AppIconPickerView: View {
    let theme: LyricTheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedIconName = UIApplication.shared.alternateIconName
    @State private var isChanging = false
    @State private var message: String?

    var body: some View {
        AppearancePickerSheet(title: "App Icon", theme: theme, isBusy: isChanging) {
            VStack(alignment: .leading, spacing: 16) {
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(theme.secondary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                          count: typeSize.isAccessibilitySize ? 2 : 3), spacing: 12) {
                    ForEach(LyricTheme.all) { option in
                        let isSelected = option.alternateIconName == selectedIconName
                        let shape = RoundedRectangle(cornerRadius: 16)
                        Button {
                            select(option.alternateIconName)
                        } label: {
                            VStack(spacing: 8) {
                                thumbnail(for: option)
                                    .overlay(alignment: .topTrailing) {
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(theme.onAccent, theme.highlight)
                                                .offset(x: 6, y: -5)
                                        }
                                    }
                                    .accessibilityHidden(true)
                                Text(option.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(2, reservesSpace: true)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(theme.surface, in: shape)
                            .overlay(shape.strokeBorder(isSelected ? theme.highlight : theme.foreground.opacity(0.1)))
                            .contentShape(shape)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .disabled(isChanging)
            }
        }
    }

    private func thumbnail(for option: LyricTheme) -> some View {
        let name = option.alternateIconName ?? "AppIcon"
        let image = Bundle.main.path(forResource: name, ofType: "png", inDirectory: "IconPreviews")
            .flatMap { UIImage(contentsOfFile: $0) }
        return Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "app.fill").font(.largeTitle).foregroundStyle(option.highlight)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func select(_ iconName: String?) {
        guard !isChanging, selectedIconName != iconName else { return }
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else {
            message = "Home Screen icon changes are unavailable in this build."
            return
        }

        message = nil
        isChanging = true
        Task {
            defer { isChanging = false }
            do {
                try await app.setAlternateIconName(iconName)
                selectedIconName = app.alternateIconName
            } catch {
                message = "Couldn’t change the Home Screen icon. Tap an icon to try again."
            }
        }
    }
}

@MainActor
struct LyricFontPickerView: View {
    @Binding var selection: LyricFont
    let theme: LyricTheme
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title2) private var sampleSize: CGFloat = 22

    var body: some View {
        AppearancePickerSheet(title: "Lyrics Font", theme: theme) {
            VStack(spacing: 12) {
                ForEach(LyricFont.allCases) { font in
                    let isSelected = selection == font
                    let shape = RoundedRectangle(cornerRadius: 16)
                    Button {
                        selection = font
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Every word in time")
                                    .font(Font(font.uiFont(size: sampleSize, weight: .semibold)))
                                    .accessibilityHidden(true)
                                Text(font.name).font(.footnote).foregroundStyle(theme.secondary)
                            }
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(theme.highlight)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(16)
                        .background(theme.surface, in: shape)
                        .overlay(shape.strokeBorder(isSelected ? theme.highlight : theme.foreground.opacity(0.1)))
                        .contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}
