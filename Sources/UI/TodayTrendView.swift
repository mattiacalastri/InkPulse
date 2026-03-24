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

    private var anomalyRecords: [HeartbeatRecord] {
        Array(records.filter { $0.anomaly != nil }.suffix(10).reversed())
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
