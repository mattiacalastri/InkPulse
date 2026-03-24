import SwiftUI
import Charts

struct MonthTrendView: View {
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

            sectionLabel("ACTIVITY HEATMAP")
            heatmapGrid
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.02)))

            sectionLabel("CUMULATIVE COST")
            cumulativeCostChart
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.02)))

            sectionLabel("AVG HOURS BY WEEKDAY")
            weekdayUsageChart
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.02)))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    // MARK: - Heatmap

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

    // MARK: - Cumulative Cost

    private var cumulativeCostChart: some View {
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
                        AreaMark(x: .value("Day", item.index), y: .value("Cost", item.cumCost))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#00d4aa").opacity(0.3), Color(hex: "#00d4aa").opacity(0.05)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        LineMark(x: .value("Day", item.index), y: .value("Cost", item.cumCost))
                            .foregroundStyle(Color(hex: "#00d4aa"))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel().foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .frame(height: 120)
            }
        }
    }

    // MARK: - Weekday Usage

    private var weekdayUsageChart: some View {
        let calendar = Calendar.current
        let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        let weekdayData: [(name: String, avgHours: Double)] = {
            var buckets: [Int: [Double]] = [:]
            for s in summaries {
                let wd = calendar.component(.weekday, from: s.date)
                let isoWd = wd == 1 ? 7 : wd - 1
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
                        BarMark(x: .value("Day", item.name), y: .value("Hours", item.avgHours))
                            .foregroundStyle(Color(hex: "#4A9EFF"))
                            .cornerRadius(4)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel().foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .frame(height: 120)
            }
        }
    }
}
