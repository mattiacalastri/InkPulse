// Sources/UI/ReportsTab.swift
import SwiftUI
import Charts

// MARK: - ReportsTab

struct ReportsTab: View {
    @ObservedObject var appState: AppState

    enum Period: String, CaseIterable {
        case today = "Today"
        case week  = "This Week"
        case month = "This Month"
    }

    @State private var selectedPeriod: Period = .today

    private var records: [HeartbeatRecord] {
        switch selectedPeriod {
        case .today: return appState.historyStore.todayRecords
        case .week:  return appState.historyStore.weekSummaries.flatMap(\.records)
        case .month: return appState.historyStore.monthSummaries.flatMap(\.records)
        }
    }

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
                    ReportsContentView(records: records, appState: appState)
                }
            }
        }
        .frame(minWidth: 580, minHeight: 520)
    }
}

// MARK: - ReportsContentView

private struct ReportsContentView: View {
    let records: [HeartbeatRecord]
    let appState: AppState

    // MARK: Computed

    private var avgHealth: Int {
        guard !records.isEmpty else { return 0 }
        return records.map(\.health).reduce(0, +) / records.count
    }

    /// Multi-session aware cost aggregation: take max costEur per session, then sum
    private var totalCost: Double {
        let grouped = Dictionary(grouping: records, by: \.sessionId)
        return grouped.values.map { sessionRecords in
            sessionRecords.map(\.costEur).max() ?? 0
        }.reduce(0, +)
    }

    private var dominantModel: String {
        let counts = Dictionary(grouping: records, by: \.model).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key ?? "—"
    }

    private var avgCacheHit: Double {
        guard !records.isEmpty else { return 0 }
        return records.map(\.cacheHit).reduce(0, +) / Double(records.count)
    }

    private var anomalyRecords: [HeartbeatRecord] {
        Array(records.filter { $0.anomaly != nil }.suffix(20))
    }

    private var toolFreqData: [(index: Int, value: Double)] {
        Array(records.enumerated()).map { (index: $0.offset, value: $0.element.toolFreq) }
    }

    private var costBurnData: [(index: Int, value: Double)] {
        Array(records.enumerated()).map { (index: $0.offset, value: $0.element.costEur) }
    }

    // MARK: Insights

    private var healthAssessment: String {
        switch avgHealth {
        case 80...100: return "System operating at peak performance."
        case 60..<80:  return "Performance is good — minor inefficiencies detected."
        case 40..<60:  return "Moderate degradation — review active sessions."
        case 20..<40:  return "Health is poor — anomalies likely impacting cost."
        default:       return "Critical state — immediate investigation required."
        }
    }

    private var cacheInsight: String {
        let pct = Int(avgCacheHit * 100)
        if pct >= 60 { return "Cache efficiency is excellent (\(pct)%) — cost well-optimized." }
        if pct >= 30 { return "Cache hit rate moderate (\(pct)%) — consider prompt reuse." }
        return "Cache misses high (\(pct)%) — repeated context is burning budget."
    }

    private var costComment: String {
        if totalCost < 0.50  { return "Spend is minimal — well within budget." }
        if totalCost < 2.00  { return "Costs are within normal range." }
        if totalCost < 5.00  { return "Spend is elevated — monitor session count." }
        return String(format: "High spend (€%.2f) — investigate hemorrhage anomalies.", totalCost)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // 1 — Header card
            headerCard

            // 2 — ECG Timeline
            sectionLabel("ECG TIMELINE")
            ecgChart

            // 3 — Cost Burn
            sectionLabel("COST BURN")
            costBurnChart

            // 4 — Tool Usage + Cache side by side
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("TOOL FREQ")
                    toolFreqChart
                }
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("CACHE HIT")
                    cacheDoughnut
                }
            }

            // 5 — Anomaly log
            if !anomalyRecords.isEmpty {
                sectionLabel("ANOMALY LOG")
                anomalyLog
            }

            // 6 — Insights
            sectionLabel("INSIGHTS")
            insightsCard

            // 7 — Export button (bottom-right)
            HStack {
                Spacer()
                Button {
                    appState.generateReport()
                } label: {
                    Label("Export HTML", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 0) {
            // Avg health — large, colored
            VStack(spacing: 4) {
                Text("\(avgHealth)")
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                    .foregroundStyle(healthColor(for: avgHealth))
                Text("avg health")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)

            headerDivider()

            VStack(spacing: 4) {
                Text(String(format: "€%.2f", totalCost))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("total cost")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)

            headerDivider()

            VStack(spacing: 4) {
                Text(dominantModel.replacingOccurrences(of: "claude-", with: ""))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#4A9EFF"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("model")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)

            headerDivider()

            VStack(spacing: 4) {
                Text("\(records.count)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#00d4aa"))
                Text("samples")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "#00d4aa").opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func headerDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1, height: 44)
    }

    // MARK: - ECG Timeline

    private var ecgChart: some View {
        Group {
            if records.isEmpty {
                emptyChart("No data for selected period")
            } else {
                Chart {
                    ForEach(Array(records.enumerated()), id: \.offset) { idx, record in
                        AreaMark(
                            x: .value("Index", idx),
                            y: .value("Health", record.health)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#00d4aa").opacity(0.25),
                                    Color(hex: "#00d4aa").opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Index", idx),
                            y: .value("Health", record.health)
                        )
                        .foregroundStyle(Color(hex: "#00d4aa"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 110)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.03))
                )
            }
        }
    }

    // MARK: - Cost Burn

    private var costBurnChart: some View {
        Group {
            if records.isEmpty {
                emptyChart("No data for selected period")
            } else {
                Chart {
                    ForEach(costBurnData, id: \.index) { item in
                        AreaMark(
                            x: .value("Index", item.index),
                            y: .value("Cost", item.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#FFA500").opacity(0.3),
                                    Color(hex: "#FFA500").opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Index", item.index),
                            y: .value("Cost", item.value)
                        )
                        .foregroundStyle(Color(hex: "#FFA500"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .frame(height: 100)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.03))
                )
            }
        }
    }

    // MARK: - Tool Freq Bar

    private var toolFreqChart: some View {
        Group {
            if records.isEmpty {
                emptyChart("No data")
            } else {
                // Bucket into 10 bins
                let bucketed = toolFreqBuckets()
                Chart {
                    ForEach(bucketed, id: \.label) { item in
                        BarMark(
                            x: .value("Freq", item.label),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(Color(hex: "#4A9EFF"))
                        .cornerRadius(3)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .frame(height: 140)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.03))
                )
            }
        }
    }

    private func toolFreqBuckets() -> [(label: String, count: Int)] {
        let maxFreq = records.map(\.toolFreq).max() ?? 20
        let binSize = max(maxFreq / 8, 1)
        var bins: [Int: Int] = [:]
        for r in records {
            let bin = Int(r.toolFreq / binSize)
            bins[bin, default: 0] += 1
        }
        return bins.keys.sorted().map { bin in
            let label = String(format: "%.0f", Double(bin) * binSize)
            return (label: label, count: bins[bin] ?? 0)
        }
    }

    // MARK: - Cache Doughnut

    private var cacheDoughnut: some View {
        let hitCount  = records.filter { $0.cacheHit >= 0.5 }.count
        let missCount = records.count - hitCount

        return Group {
            if records.isEmpty {
                emptyChart("No data")
            } else {
                VStack(spacing: 8) {
                    Chart {
                        SectorMark(
                            angle: .value("Count", hitCount),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(Color(hex: "#00d4aa"))
                        .cornerRadius(3)

                        SectorMark(
                            angle: .value("Count", max(missCount, 0)),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(Color(hex: "#FF4444"))
                        .cornerRadius(3)
                    }
                    .frame(height: 110)

                    HStack(spacing: 12) {
                        legendDot(color: Color(hex: "#00d4aa"), label: "hit")
                        legendDot(color: Color(hex: "#FF4444"), label: "miss")
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.03))
                )
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Anomaly Log

    private var anomalyLog: some View {
        VStack(spacing: 5) {
            ForEach(Array(anomalyRecords.reversed().enumerated()), id: \.offset) { _, record in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: "#FF4444"))
                        .frame(width: 6, height: 6)

                    Text(formatTimestamp(record.ts))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))

                    Text(record.anomaly ?? "")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#FF4444"))

                    Spacer()

                    Text("h:\(record.health)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(healthColor(for: record.health))

                    Text(String(format: "€%.3f", record.costEur))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "#FF4444").opacity(0.05))
                )
            }
        }
    }

    // MARK: - Insights Card

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            insightRow(icon: "heart.fill", color: healthColor(for: avgHealth), text: healthAssessment)
            insightRow(icon: "memorychip", color: Color(hex: "#4A9EFF"), text: cacheInsight)
            insightRow(icon: "eurosign.circle.fill", color: Color(hex: "#FFA500"), text: costComment)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "#00d4aa").opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func insightRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Shared helpers (sectionLabel, emptyChart, formatTimestamp)
// are in SharedComponents.swift
