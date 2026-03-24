// Sources/UI/TrendsTab.swift
import SwiftUI
import Charts

// MARK: - TrendsTab

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
                // Segmented picker
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

// MARK: - TodayTrendView

private struct TodayTrendView: View {
    let records: [HeartbeatRecord]

    private var avgHealth: Int {
        guard !records.isEmpty else { return 0 }
        return records.map(\.health).reduce(0, +) / records.count
    }

    private var totalCost: Double {
        records.map(\.costEur).max() ?? 0
    }

    private var peakTokenMin: Double {
        records.map(\.tokenMin).max() ?? 0
    }

    private var sessionCount: Int {
        Set(records.map(\.sessionId)).count
    }

    private var activeHours: Double {
        Double(records.count) * 5.0 / 3600.0
    }

    private var anomalyRecords: [HeartbeatRecord] {
        Array(records.filter { $0.anomaly != nil }.suffix(10).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Stats strip
            sectionLabel("TODAY OVERVIEW")

            HStack(spacing: 0) {
                trendStat("health", "\(avgHealth)", color: healthColor(for: avgHealth))
                trendDivider()
                trendStat("cost", String(format: "€%.2f", totalCost), color: .white)
                trendDivider()
                trendStat("peak tok/m", String(format: "%.0f", peakTokenMin), color: Color(hex: "#00d4aa"))
                trendDivider()
                trendStat("sessions", "\(sessionCount)", color: Color(hex: "#4A9EFF"))
                trendDivider()
                trendStat("hours", String(format: "%.1f", activeHours), color: .white.opacity(0.7))
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "#00d4aa").opacity(0.1), lineWidth: 1)
                    )
            )

            // ECG chart
            sectionLabel("HEALTH ECG")

            if records.isEmpty {
                emptyChart("No heartbeat data today")
            } else {
                Chart {
                    ForEach(Array(records.enumerated()), id: \.offset) { idx, record in
                        LineMark(
                            x: .value("Index", idx),
                            y: .value("Health", record.health)
                        )
                        .foregroundStyle(Color(hex: "#00d4aa"))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 120)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.02))
                )
            }

            // Anomaly timeline
            if !anomalyRecords.isEmpty {
                sectionLabel("ANOMALIES")

                VStack(spacing: 6) {
                    ForEach(Array(anomalyRecords.enumerated()), id: \.offset) { _, record in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: "#FF4444"))
                                .frame(width: 6, height: 6)

                            Text(formatTimestamp(record.ts))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))

                            Text(record.anomaly ?? "")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: "#FF4444"))

                            Spacer()

                            Text("health \(record.health)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(healthColor(for: record.health))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: "#FF4444").opacity(0.05))
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }
}

// MARK: - WeekTrendView

private struct WeekTrendView: View {
    let summaries: [DaySummary]

    private var allRecords: [HeartbeatRecord] {
        summaries.flatMap(\.records)
    }

    private var weekAvgHealth: Int {
        let active = summaries.filter { $0.totalSessions > 0 }
        guard !active.isEmpty else { return 0 }
        return active.map(\.avgHealth).reduce(0, +) / active.count
    }

    private var weekTotalCost: Double {
        summaries.map(\.totalCost).reduce(0, +)
    }

    private var activeDays: Int {
        summaries.filter { $0.totalSessions > 0 }.count
    }

    private var worstSessions: [(sessionId: String, avgHealth: Int)] {
        let grouped = Dictionary(grouping: allRecords, by: \.sessionId)
        let sessionHealths: [(sessionId: String, avgHealth: Int)] = grouped.map { sid, recs in
            let avg = recs.map(\.health).reduce(0, +) / max(recs.count, 1)
            return (sessionId: sid, avgHealth: avg)
        }
        return Array(sessionHealths.sorted { $0.avgHealth < $1.avgHealth }.prefix(3))
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Stats
            sectionLabel("WEEK OVERVIEW")

            HStack(spacing: 0) {
                trendStat("avg health", "\(weekAvgHealth)", color: healthColor(for: weekAvgHealth))
                trendDivider()
                trendStat("total cost", String(format: "€%.2f", weekTotalCost), color: .white)
                trendDivider()
                trendStat("active days", "\(activeDays)/7", color: Color(hex: "#4A9EFF"))
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "#00d4aa").opacity(0.1), lineWidth: 1)
                    )
            )

            // Cost bar chart
            sectionLabel("DAILY COST")

            if summaries.isEmpty {
                emptyChart("No week data")
            } else {
                Chart {
                    ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                        BarMark(
                            x: .value("Day", Self.dayFormatter.string(from: summary.date)),
                            y: .value("Cost", summary.totalCost)
                        )
                        .foregroundStyle(healthColor(for: summary.avgHealth))
                        .cornerRadius(4)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .frame(height: 140)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.02))
                )
            }

            // Health trend line
            sectionLabel("HEALTH TREND")

            if summaries.isEmpty {
                emptyChart("No week data")
            } else {
                Chart {
                    ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                        let dayLabel = Self.dayFormatter.string(from: summary.date)

                        LineMark(
                            x: .value("Day", dayLabel),
                            y: .value("Health", summary.avgHealth)
                        )
                        .foregroundStyle(Color(hex: "#00d4aa"))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Day", dayLabel),
                            y: .value("Health", summary.avgHealth)
                        )
                        .foregroundStyle(healthColor(for: summary.avgHealth))
                        .symbolSize(30)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 120)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.02))
                )
            }

            // Worst sessions
            if !worstSessions.isEmpty {
                sectionLabel("WORST SESSIONS")

                VStack(spacing: 6) {
                    ForEach(Array(worstSessions.enumerated()), id: \.offset) { _, session in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(healthColor(for: session.avgHealth))
                                .frame(width: 8, height: 8)

                            Text(String(session.sessionId.prefix(12)))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))

                            Spacer()

                            Text("avg \(session.avgHealth)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(healthColor(for: session.avgHealth))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.03))
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }
}

// MARK: - MonthTrendView

private struct MonthTrendView: View {
    let summaries: [DaySummary]

    private var totalCost: Double {
        summaries.map(\.totalCost).reduce(0, +)
    }

    private var totalSessions: Int {
        summaries.map(\.totalSessions).reduce(0, +)
    }

    private var totalAnomalies: Int {
        summaries.map(\.anomalyCount).reduce(0, +)
    }

    private var activeDays: Int {
        summaries.filter { $0.totalSessions > 0 }.count
    }

    private static let dayNumFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private static let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Summary stats
            sectionLabel("MONTH OVERVIEW")

            HStack(spacing: 0) {
                trendStat("total cost", String(format: "€%.2f", totalCost), color: .white)
                trendDivider()
                trendStat("sessions", "\(totalSessions)", color: Color(hex: "#4A9EFF"))
                trendDivider()
                trendStat("anomalies", "\(totalAnomalies)", color: totalAnomalies > 0 ? Color(hex: "#FF4444") : Color(hex: "#00d4aa"))
                trendDivider()
                trendStat("active days", "\(activeDays)/30", color: Color(hex: "#00d4aa"))
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "#00d4aa").opacity(0.1), lineWidth: 1)
                    )
            )

            // Heatmap
            sectionLabel("ACTIVITY HEATMAP")
            heatmapGrid
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.02))
                )

            // Cumulative cost
            sectionLabel("CUMULATIVE COST")
            cumulativeCostChart
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.02))
                )

            // Weekday usage
            sectionLabel("AVG HOURS BY WEEKDAY")
            weekdayUsageChart
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.02))
                )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    // MARK: Heatmap

    private var heatmapGrid: some View {
        let calendar = Calendar.current
        let summaryByDay: [Int: DaySummary] = {
            var map: [Int: DaySummary] = [:]
            for s in summaries {
                let day = calendar.component(.day, from: s.date)
                map[day] = s
            }
            return map
        }()

        let firstDay: Date = summaries.first?.date ?? Date()
        let wd = calendar.component(.weekday, from: firstDay)
        let startPad = wd == 1 ? 6 : wd - 2

        let totalCells = startPad + summaries.count
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return VStack(alignment: .leading, spacing: 4) {
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Self.weekdayLabels[i])
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<totalCells, id: \.self) { idx in
                    if idx < startPad {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.clear)
                            .aspectRatio(1, contentMode: .fit)
                    } else {
                        let dayOffset = idx - startPad
                        let dayNum = dayOffset + calendar.component(.day, from: firstDay)
                        let summary = summaryByDay[dayNum]
                        let health = summary?.avgHealth ?? 0
                        let hasData = (summary?.totalSessions ?? 0) > 0

                        RoundedRectangle(cornerRadius: 3)
                            .fill(hasData ? healthColor(for: health).opacity(opacityForHealth(health)) : Color.white.opacity(0.04))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Text("\(dayNum)")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.white.opacity(hasData ? 0.7 : 0.2))
                            )
                    }
                }
            }
        }
    }

    private func opacityForHealth(_ health: Int) -> Double {
        if health >= 80 { return 0.9 }
        if health >= 60 { return 0.7 }
        if health >= 40 { return 0.5 }
        if health >= 20 { return 0.35 }
        return 0.2
    }

    // MARK: Cumulative Cost

    private var cumulativeCostChart: some View {
        // Precompute running total OUTSIDE Chart
        let runningTotals: [(index: Int, label: String, cumCost: Double)] = {
            var total = 0.0
            var result: [(index: Int, label: String, cumCost: Double)] = []
            for (i, s) in summaries.enumerated() {
                total += s.totalCost
                let label = Self.dayNumFormatter.string(from: s.date)
                result.append((index: i, label: label, cumCost: total))
            }
            return result
        }()

        return Group {
            if runningTotals.isEmpty {
                emptyChart("No month data")
            } else {
                Chart {
                    ForEach(runningTotals, id: \.index) { item in
                        AreaMark(
                            x: .value("Day", item.index),
                            y: .value("Cost", item.cumCost)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "#00d4aa").opacity(0.3), Color(hex: "#00d4aa").opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Day", item.index),
                            y: .value("Cost", item.cumCost)
                        )
                        .foregroundStyle(Color(hex: "#00d4aa"))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .frame(height: 120)
            }
        }
    }

    // MARK: Weekday Usage

    private var weekdayUsageChart: some View {
        let calendar = Calendar.current
        let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        // Group summaries by weekday (Mon=2..Sun=1 in Calendar), compute avg hours
        let weekdayData: [(name: String, avgHours: Double)] = {
            var buckets: [Int: [Double]] = [:]
            for s in summaries {
                let wd = calendar.component(.weekday, from: s.date)
                let isoWd = wd == 1 ? 7 : wd - 1 // Mon=1..Sun=7
                buckets[isoWd, default: []].append(s.activeMinutes / 60.0)
            }
            var result: [(name: String, avgHours: Double)] = []
            for i in 1...7 {
                let vals = buckets[i] ?? []
                let avg = vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
                result.append((name: weekdayNames[i - 1], avgHours: avg))
            }
            return result
        }()

        return Group {
            if summaries.isEmpty {
                emptyChart("No month data")
            } else {
                Chart {
                    ForEach(weekdayData, id: \.name) { item in
                        BarMark(
                            x: .value("Day", item.name),
                            y: .value("Hours", item.avgHours)
                        )
                        .foregroundStyle(Color(hex: "#4A9EFF"))
                        .cornerRadius(4)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .frame(height: 120)
            }
        }
    }
}

// MARK: - Shared Helpers

private func trendStat(_ label: String, _ value: String, color: Color) -> some View {
    VStack(spacing: 4) {
        Text(value)
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.3))
    }
    .frame(maxWidth: .infinity)
}

private func trendDivider() -> some View {
    Rectangle()
        .fill(Color.white.opacity(0.06))
        .frame(width: 1, height: 36)
}

private func sectionLabel(_ text: String) -> some View {
    HStack(spacing: 6) {
        Rectangle()
            .fill(Color(hex: "#00d4aa"))
            .frame(width: 3, height: 12)
            .cornerRadius(1.5)
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
    }
}

private func emptyChart(_ message: String) -> some View {
    RoundedRectangle(cornerRadius: 10)
        .fill(Color.white.opacity(0.02))
        .frame(height: 80)
        .overlay(
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        )
}

private func formatTimestamp(_ ts: String) -> String {
    // Extract HH:MM:SS from ISO8601 timestamp
    if let tIdx = ts.firstIndex(of: "T") {
        let timeStr = ts[ts.index(after: tIdx)...]
        if let dotIdx = timeStr.firstIndex(of: ".") {
            return String(timeStr[..<dotIdx])
        }
        if let zIdx = timeStr.firstIndex(of: "Z") {
            return String(timeStr[..<zIdx])
        }
        return String(timeStr.prefix(8))
    }
    return ts
}
