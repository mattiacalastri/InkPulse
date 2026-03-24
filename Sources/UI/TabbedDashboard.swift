// Sources/UI/TabbedDashboard.swift
import SwiftUI

struct TabbedDashboard: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            LiveTab(appState: appState)
                .tabItem {
                    Label("Live", systemImage: "waveform.path.ecg")
                }

            TrendsTab(appState: appState)
                .tabItem {
                    Label("Trends", systemImage: "chart.xyaxis.line")
                }

            Text("Reports — coming soon")
                .tabItem {
                    Label("Reports", systemImage: "doc.text.chart.fill")
                }
        }
        .preferredColorScheme(.dark)
    }
}
