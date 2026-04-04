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

            TeamsTab(appState: appState)
                .tabItem {
                    Label("Teams", systemImage: "person.3.fill")
                }

            TrendsTab(appState: appState)
                .tabItem {
                    Label("Trends", systemImage: "chart.xyaxis.line")
                }

            ReportsTab(appState: appState)
                .tabItem {
                    Label("Reports", systemImage: "doc.text.chart.fill")
                }
        }
        .preferredColorScheme(.dark)
    }
}
