// Sources/Persistence/HistoryStore.swift
import Foundation
import Combine

struct DaySummary {
    let date: Date
    let avgHealth: Int
    let totalCost: Double
    let peakTokenMin: Double
    let totalSessions: Int
    let activeMinutes: Double
    let anomalyCount: Int
    let avgCacheHit: Double
    let avgErrorRate: Double
    let records: [HeartbeatRecord]
}

final class HistoryStore: ObservableObject {

    @Published var todayRecords: [HeartbeatRecord] = []
    @Published var weekSummaries: [DaySummary] = []
    @Published var monthSummaries: [DaySummary] = []

    private let heartbeatDir: URL
    private var todayTimer: Timer?
    private var historyTimer: Timer?

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    init(heartbeatDir: URL = InkPulseDefaults.heartbeatDir) {
        self.heartbeatDir = heartbeatDir
    }

    func start() {
        refreshToday()
        refreshHistory()

        todayTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.refreshToday()
        }
        historyTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refreshHistory()
        }
    }

    func refreshToday() {
        let dateStr = Self.fileDateFormatter.string(from: Date())
        let fileURL = heartbeatDir.appendingPathComponent("heartbeat-\(dateStr).jsonl")
        todayRecords = loadRecords(from: fileURL)
    }

    func refreshHistory() {
        let today = Date()
        let calendar = Calendar.current

        var weekDays: [DaySummary] = []
        for offset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateStr = Self.fileDateFormatter.string(from: date)
            let fileURL = heartbeatDir.appendingPathComponent("heartbeat-\(dateStr).jsonl")
            let records = loadRecords(from: fileURL)
            weekDays.append(aggregate(records: records, date: date))
        }
        weekSummaries = weekDays

        var monthDays: [DaySummary] = []
        for offset in (0..<30).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateStr = Self.fileDateFormatter.string(from: date)
            let fileURL = heartbeatDir.appendingPathComponent("heartbeat-\(dateStr).jsonl")
            let records = loadRecords(from: fileURL)
            monthDays.append(aggregate(records: records, date: date))
        }
        monthSummaries = monthDays
    }

    private func loadRecords(from fileURL: URL) -> [HeartbeatRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }

        let decoder = JSONDecoder()
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(HeartbeatRecord.self, from: lineData)
            }
    }

    private func aggregate(records: [HeartbeatRecord], date: Date) -> DaySummary {
        guard !records.isEmpty else {
            return DaySummary(
                date: date, avgHealth: 0, totalCost: 0, peakTokenMin: 0,
                totalSessions: 0, activeMinutes: 0, anomalyCount: 0,
                avgCacheHit: 0, avgErrorRate: 0, records: []
            )
        }

        let avgHealth = records.map(\.health).reduce(0, +) / records.count
        let totalCost = records.map(\.costEur).max() ?? 0
        let peakTokenMin = records.map(\.tokenMin).max() ?? 0
        let uniqueSessions = Set(records.map(\.sessionId)).count
        let anomalyCount = records.filter { $0.anomaly != nil }.count
        let avgCacheHit = records.map(\.cacheHit).reduce(0, +) / Double(records.count)
        let avgErrorRate = records.map(\.errorRate).reduce(0, +) / Double(records.count)
        let activeMinutes = Double(records.count) * 5.0 / 60.0

        return DaySummary(
            date: date, avgHealth: avgHealth, totalCost: totalCost,
            peakTokenMin: peakTokenMin, totalSessions: uniqueSessions,
            activeMinutes: activeMinutes, anomalyCount: anomalyCount,
            avgCacheHit: avgCacheHit, avgErrorRate: avgErrorRate,
            records: records
        )
    }
}
