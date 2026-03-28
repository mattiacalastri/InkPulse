import SwiftUI
import Charts

struct TodayTrendView: View {
    let records: [HeartbeatRecord]

    // MARK: - Overview Stats

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

    // MARK: - ECG Data

    private var ecgData: [(index: Int, health: Int)] {
        guard records.count > 2 else {
            return records.enumerated().map { ($0.offset, $0.element.health) }
        }
        let step = max(1, records.count / 200)
        var result: [(index: Int, health: Int)] = []
        for i in stride(from: 0, to: records.count, by: step) {
            result.append((index: i, health: records[i].health))
        }
        if result.last?.index != records.count - 1 {
            result.append((index: records.count - 1, health: records.last!.health))
        }
        return result
    }

    // MARK: - Anomaly Heatmap Data

    private struct HourAnomaly: Identifiable {
        let id = UUID()
        let hour: Int
        let type: String
        let count: Int
    }

    private var anomalyHeatmap: [HourAnomaly] {
        let anomalyRecords = records.filter { $0.anomaly != nil }
        var result: [HourAnomaly] = []

        // Group by hour + type
        var buckets: [String: Int] = [:]  // "HH:type" → count
        for rec in anomalyRecords {
            if let hour = extractHour(from: rec.ts), let anomaly = rec.anomaly {
                let key = "\(hour):\(anomaly)"
                buckets[key, default: 0] += 1
            }
        }

        for (key, count) in buckets {
            let parts = key.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let hour = Int(parts[0]) {
                result.append(HourAnomaly(hour: hour, type: String(parts[1]), count: count))
            }
        }

        return result.sorted { $0.hour < $1.hour }
    }

    // MARK: - Stall Root Cause Analysis

    private struct StallCause {
        let name: String
        let count: Int
        let percent: Double
        let color: Color
        let icon: String
    }

    private var stallCauses: [StallCause] {
        let stallRecords = records.filter { $0.anomaly == "stall" }
        guard !stallRecords.isEmpty else { return [] }

        var mcpTimeout = 0
        var permissionWait = 0
        var contextFull = 0
        var unknown = 0

        for rec in stallRecords {
            let tool = rec.lastToolName?.lowercased() ?? ""
            let ctx = rec.contextPercent ?? 0

            if tool.hasPrefix("mcp_") || tool.hasPrefix("mcp__") {
                mcpTimeout += 1
            } else if ctx > 0.90 {
                contextFull += 1
            } else if tool == "bash" || tool == "edit" || tool == "write" || tool.isEmpty {
                permissionWait += 1
            } else {
                unknown += 1
            }
        }

        let total = Double(stallRecords.count)
        var causes: [StallCause] = []
        if mcpTimeout > 0 {
            causes.append(StallCause(name: "MCP timeout", count: mcpTimeout, percent: Double(mcpTimeout) / total * 100, color: Color(hex: "#FF4444"), icon: "network.slash"))
        }
        if permissionWait > 0 {
            causes.append(StallCause(name: "Permission wait", count: permissionWait, percent: Double(permissionWait) / total * 100, color: Color(hex: "#FFA500"), icon: "hand.raised.fill"))
        }
        if contextFull > 0 {
            causes.append(StallCause(name: "Context full", count: contextFull, percent: Double(contextFull) / total * 100, color: Color(hex: "#9B59B6"), icon: "brain"))
        }
        if unknown > 0 {
            causes.append(StallCause(name: "Other", count: unknown, percent: Double(unknown) / total * 100, color: Color(hex: "#4A9EFF"), icon: "questionmark.circle"))
        }
        return causes.sorted { $0.count > $1.count }
    }

    // MARK: - Cost Efficiency Analysis

    private var costBreakdown: (forging: Double, stalled: Double, forgingPct: Double) {
        guard !records.isEmpty, totalCost > 0 else { return (0, 0, 1.0) }

        let stallRecords = records.filter { $0.anomaly == "stall" || $0.anomaly == "loop" }
        let stallFraction = Double(stallRecords.count) / Double(records.count)
        let stalledCost = totalCost * stallFraction
        let forgingCost = totalCost - stalledCost

        return (forging: forgingCost, stalled: stalledCost, forgingPct: 1.0 - stallFraction)
    }

    // MARK: - Actionable Insight

    private var actionableInsight: (title: String, body: String, icon: String, color: Color)? {
        let causes = stallCauses
        guard let topCause = causes.first, topCause.count > 10 else { return nil }

        let breakdown = costBreakdown
        let wastedStr = String(format: "€%.2f", breakdown.stalled)

        switch topCause.name {
        case "MCP timeout":
            return (
                title: "MCP timeout is your #1 bottleneck",
                body: "\(topCause.count) stalls (\(Int(topCause.percent))%). Add 30s timeout fallback to MCP tools. Est. saving: \(wastedStr)/day.",
                icon: "network.slash",
                color: Color(hex: "#FF4444")
            )
        case "Permission wait":
            return (
                title: "Permission prompts are slowing you down",
                body: "\(topCause.count) stalls (\(Int(topCause.percent))%). Allow frequent tools (Bash, Edit) in settings. Est. saving: \(wastedStr)/day.",
                icon: "hand.raised.fill",
                color: Color(hex: "#FFA500")
            )
        case "Context full":
            return (
                title: "Context pressure causing stalls",
                body: "\(topCause.count) stalls (\(Int(topCause.percent))%). Split long sessions or use subagents for heavy tasks. Est. saving: \(wastedStr)/day.",
                icon: "brain",
                color: Color(hex: "#9B59B6")
            )
        default:
            return nil
        }
    }

    // MARK: - Grouped Anomalies (legacy, kept for summary)

    private var groupedAnomalies: [(type: String, count: Int, avgHealth: Int)] {
        let anomalyRecords = records.filter { $0.anomaly != nil }
        let grouped = Dictionary(grouping: anomalyRecords, by: { $0.anomaly ?? "" })
        return grouped.map { type, recs in
            let avg = recs.map(\.health).reduce(0, +) / recs.count
            return (type: type, count: recs.count, avgHealth: avg)
        }
        .sorted { $0.count > $1.count }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── ACTIONABLE INSIGHT ──
            if let insight = actionableInsight {
                insightBanner(insight)
            }

            // ── OVERVIEW ──
            sectionLabel("TODAY OVERVIEW")
            overviewGrid

            // ── COST EFFICIENCY ──
            if costBreakdown.stalled > 0.01 {
                sectionLabel("COST EFFICIENCY")
                costEfficiencyBar
            }

            // ── ECG ──
            sectionLabel("HEALTH ECG")
            ecgChart

            // ── ANOMALY HEATMAP ──
            if !anomalyHeatmap.isEmpty {
                sectionLabel("ANOMALY HEATMAP — \(records.filter { $0.anomaly != nil }.count) total")
                heatmapView
            }

            // ── STALL ROOT CAUSE ──
            if !stallCauses.isEmpty {
                sectionLabel("STALL ROOT CAUSE — \(stallCauses.map(\.count).reduce(0, +)) stalls")
                rootCauseView
            }

            // ── PILLAR BREAKDOWN ──
            if pillarBreakdown.count > 1 {
                sectionLabel("PILLAR COST SPLIT")
                pillarCostView
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    // MARK: - Actionable Insight Banner

    private func insightBanner(_ insight: (title: String, body: String, icon: String, color: Color)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: insight.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(insight.color)
                Text("ACTION REQUIRED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(insight.color)
                Spacer()
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "#FFD700"))
            }
            Text(insight.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(insight.body)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(3)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(insight.color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(insight.color.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Overview Grid

    private var overviewGrid: some View {
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
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "#00d4aa").opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Cost Efficiency Bar

    private var costEfficiencyBar: some View {
        let b = costBreakdown
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: "#00d4aa")).frame(width: 6, height: 6)
                    Text("Forging")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(String(format: "€%.2f (%d%%)", b.forging, Int(b.forgingPct * 100)))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#00d4aa"))
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: "#FF4444")).frame(width: 6, height: 6)
                    Text("Wasted")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(String(format: "€%.2f (%d%%)", b.stalled, Int((1.0 - b.forgingPct) * 100)))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#FF4444"))
                }
            }

            GeometryReader { geo in
                HStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#00d4aa"))
                        .frame(width: geo.size.width * CGFloat(b.forgingPct))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#FF4444").opacity(0.7))
                }
            }
            .frame(height: 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    // MARK: - ECG Chart

    private var ecgChart: some View {
        Group {
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
                        .fill(.white.opacity(0.04))
                )
            }
        }
    }

    // MARK: - Anomaly Heatmap

    private var heatmapView: some View {
        let types = Array(Set(anomalyHeatmap.map(\.type))).sorted()
        let hours = Array(Set(anomalyHeatmap.map(\.hour))).sorted()
        let maxCount = anomalyHeatmap.map(\.count).max() ?? 1

        return VStack(alignment: .leading, spacing: 4) {
            // Hour labels
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 70, alignment: .leading)
                ForEach(hours, id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                }
            }

            // Rows per anomaly type
            ForEach(types, id: \.self) { type in
                HStack(spacing: 0) {
                    Text(type)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(anomalyColor(type))
                        .frame(width: 70, alignment: .leading)
                        .lineLimit(1)

                    ForEach(hours, id: \.self) { hour in
                        let count = anomalyHeatmap.first { $0.hour == hour && $0.type == type }?.count ?? 0
                        let intensity = maxCount > 0 ? Double(count) / Double(maxCount) : 0

                        RoundedRectangle(cornerRadius: 2)
                            .fill(count > 0 ? anomalyColor(type).opacity(0.2 + intensity * 0.8) : Color.white.opacity(0.03))
                            .frame(height: 16)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                count > 0 ?
                                Text("\(count)")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.8))
                                : nil
                            )
                            .padding(.horizontal, 1)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.04))
        )
    }

    // MARK: - Root Cause View

    private var rootCauseView: some View {
        VStack(spacing: 6) {
            ForEach(Array(stallCauses.enumerated()), id: \.offset) { _, cause in
                HStack(spacing: 10) {
                    Image(systemName: cause.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(cause.color)
                        .frame(width: 16)

                    Text(cause.name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(cause.color)

                    Text("\(cause.count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    // Proportion bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(cause.color.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(cause.percent / 100.0))
                    }
                    .frame(width: 80, height: 6)

                    Text(String(format: "%.0f%%", cause.percent))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(cause.color)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(cause.color.opacity(0.05))
                )
            }
        }
    }

    // MARK: - Pillar Cost Breakdown

    private var pillarBreakdown: [(name: String, cost: Double, color: Color)] {
        var costs: [String: Double] = [:]
        for rec in records {
            let pillar = rec.pillar ?? "Unknown"
            costs[pillar, default: 0] = max(costs[pillar, default: 0], rec.costEur)
        }
        return costs.map { name, cost in
            let color = pillarColor(name)
            return (name: name, cost: cost, color: color)
        }
        .sorted { $0.cost > $1.cost }
    }

    private var pillarCostView: some View {
        let total = pillarBreakdown.map(\.cost).reduce(0, +)
        return VStack(spacing: 4) {
            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(pillarBreakdown.enumerated()), id: \.offset) { _, p in
                        let fraction = total > 0 ? CGFloat(p.cost / total) : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(p.color)
                            .frame(width: max(geo.size.width * fraction, 2))
                    }
                }
            }
            .frame(height: 10)

            // Legend
            HStack(spacing: 12) {
                ForEach(Array(pillarBreakdown.enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 4) {
                        Circle().fill(p.color).frame(width: 6, height: 6)
                        Text(p.name)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(String(format: "€%.2f", p.cost))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(p.color)
                    }
                }
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private func extractHour(from ts: String) -> Int? {
        // ISO8601: "2026-03-24T23:22:12.000Z" → extract hour
        guard let tIdx = ts.firstIndex(of: "T") else { return nil }
        let timeStr = ts[ts.index(after: tIdx)...]
        let hourStr = timeStr.prefix(2)
        return Int(hourStr)
    }

    private func anomalyColor(_ type: String) -> Color {
        switch type {
        case "stall": return Color(hex: "#FFA500")
        case "explosion": return Color(hex: "#FF4444")
        case "loop": return Color(hex: "#9B59B6")
        case "hemorrhage": return Color(hex: "#FF4444")
        case "deep_thinking": return Color(hex: "#4A9EFF")
        default: return Color(hex: "#FFA500")
        }
    }

    /// Map pillar name to color — reads from teams.json, falls back to config overrides, then hash-based color.
    private func pillarColor(_ name: String) -> Color {
        // Check team configs first
        for team in TeamsLoader.load() {
            if team.name == name { return team.resolvedColor }
        }
        // Check pillar overrides from config
        let config = ConfigLoader.load()
        for (_, override) in config.pillarOverrides {
            if override.name == name { return Color(hex: override.color) }
        }
        // Deterministic color from name hash
        let hash = abs(name.hashValue)
        let palette = ["#00d4aa", "#FFD700", "#4A9EFF", "#A855F7", "#FF6B35", "#FF4444", "#2ECC71", "#E74C3C"]
        return Color(hex: palette[hash % palette.count])
    }
}
