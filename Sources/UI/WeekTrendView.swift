import SwiftUI
import Charts

struct WeekTrendView: View {
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
                        AxisValueLabel().foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel().foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .frame(height: 140)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.02)))
            }

            sectionLabel("HEALTH TREND")

            if summaries.isEmpty {
                emptyChart("No week data")
            } else {
                Chart {
                    ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                        let dayLabel = Self.dayFormatter.string(from: summary.date)
                        LineMark(x: .value("Day", dayLabel), y: .value("Health", summary.avgHealth))
                            .foregroundStyle(Color(hex: "#00d4aa"))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Day", dayLabel), y: .value("Health", summary.avgHealth))
                            .foregroundStyle(healthColor(for: summary.avgHealth))
                            .symbolSize(30)
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
                .chartYScale(domain: 0...100)
                .frame(height: 120)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.02)))
            }

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
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }
}
