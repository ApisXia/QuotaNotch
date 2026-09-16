// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// A shared control column keeps pickers, shortcuts and toggles visually aligned.
struct SettingsField<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content
    init(_ title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    var body: some View {
        LabeledContent {
            content().labelsHidden().frame(width: 180, alignment: .trailing)
        } label: {
            Text(title).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

struct SettingsHint: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum SettingsAccessState {
    case notRequested, allowed, denied, restricted, limited, unavailable
    var message: LocalizedStringKey {
        switch self {
        case .notRequested: "Access has not been requested. Allow access to choose what appears in the notch."
        case .allowed: "Access allowed."
        case .denied: "Access was denied. You can enable it in System Settings."
        case .restricted: "Access is restricted by your Mac’s policies."
        case .limited: "Read access is required to display events. Your current permission only allows adding events."
        case .unavailable: "Permission status is unavailable. Check System Settings."
        }
    }
    var actionTitle: LocalizedStringKey {
        self == .notRequested || self == .limited ? "Allow Access" : "Open System Settings"
    }
}

struct SettingsPermissionNotice: View {
    let state: SettingsAccessState
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsHint(state.message)
            Button(state.actionTitle, action: action)
        }.padding(.vertical, 4)
    }
}
