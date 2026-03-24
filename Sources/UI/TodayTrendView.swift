import SwiftUI
import Charts

struct TodayTrendView: View {
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

    // Downsample dense data for clean ECG line — take every Nth point
    private var ecgData: [(index: Int, health: Int)] {
        guard records.count > 2 else {
            return records.enumerated().map { ($0.offset, $0.element.health) }
        }
        let step = max(1, records.count / 200) // max ~200 points for smooth line
        var result: [(index: Int, health: Int)] = []
        for i in stride(from: 0, to: records.count, by: step) {
            result.append((index: i, health: records[i].health))
        }
        // Always include last point
        if result.last?.index != records.count - 1 {
            result.append((index: records.count - 1, health: records.last!.health))
        }
        return result
    }

    // Group anomalies by type — deduplicate repetitive entries
    private var groupedAnomalies: [(type: String, count: Int, avgHealth: Int, firstTs: String, lastTs: String)] {
        let anomalyRecords = records.filter { $0.anomaly != nil }
        let grouped = Dictionary(grouping: anomalyRecords, by: { $0.anomaly ?? "" })
        return grouped.map { type, recs in
            let avg = recs.map(\.health).reduce(0, +) / recs.count
            let sorted = recs.sorted { $0.ts < $1.ts }
            return (
                type: type,
                count: recs.count,
                avgHealth: avg,
                firstTs: sorted.first?.ts ?? "",
                lastTs: sorted.last?.ts ?? ""
            )
        }
        .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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

            sectionLabel("HEALTH ECG")

            if records.isEmpty {
                emptyChart("No heartbeat data today")
            } else {
                Chart(ecgData, id: \.index) { point in
                    LineMark(
                        x: .value("Index", point.index),
                        y: .value("Health", point.health)
                    )
                    .foregroundStyle(Color(hex: "#00d4aa"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                    AreaMark(
                        x: .value("Index", point.index),
                        y: .value("Health", point.health)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Color(hex: "#00d4aa").opacity(0.15), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 140)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.02))
                )
            }

            // Grouped anomalies — no spam
            if !groupedAnomalies.isEmpty {
                sectionLabel("ANOMALIES — \(records.filter { $0.anomaly != nil }.count) total")

                VStack(spacing: 6) {
                    ForEach(Array(groupedAnomalies.enumerated()), id: \.offset) { _, group in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: "#FF4444"))
                                .frame(width: 6, height: 6)

                            Text(group.type)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(hex: "#FF4444"))

                            Text("×\(group.count)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(hex: "#FF4444").opacity(0.7))

                            Spacer()

                            Text(formatTimestamp(group.firstTs) + (group.count > 1 ? " → " + formatTimestamp(group.lastTs) : ""))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))

                            Text("avg \(group.avgHealth)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(healthColor(for: group.avgHealth))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
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
