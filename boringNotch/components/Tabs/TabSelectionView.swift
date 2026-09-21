//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI
import Defaults

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "主页", icon: "house.fill", view: .home),
    TabModel(label: "AI 用量", icon: "chart.bar.fill", view: .aiUsage),
    TabModel(label: "任务监控", icon: "square.stack.3d.up", view: .activity),
    TabModel(label: "收纳", icon: "tray.full", view: .bubbleShelf)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func select(_ view: NotchViews) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            coordinator.currentView = view
            AgentActivityStore.shared.notchReadEnabled = view == .activity
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                    TabButton(label: QuotaText.localized(tab.label), icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        select(tab.view)
                    }
                    .frame(height: 26)
                    .help(QuotaText.localized(tab.label))
                    .accessibilityLabel(QuotaText.localized(tab.label))
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
