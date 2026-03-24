import SwiftUI

struct TrendsTab: View {
    @ObservedObject var appState: AppState

    enum Period: String, CaseIterable {
        case today = "Today"
        case week = "Week"
        case month = "Month"
    }

    @State private var selectedPeriod: Period = .today

    var body: some View {
        ZStack {
            Color(hex: "#0a0f1a").ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(Period.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider().overlay(Color(hex: "#00d4aa").opacity(0.2))

                ScrollView {
                    switch selectedPeriod {
                    case .today:
                        TodayTrendView(records: appState.historyStore.todayRecords)
                    case .week:
                        WeekTrendView(summaries: appState.historyStore.weekSummaries)
                    case .month:
                        MonthTrendView(summaries: appState.historyStore.monthSummaries)
                    }
                }
            }
        }
        .frame(minWidth: 580, minHeight: 520)
    }
}
