import Foundation
import AppKit

// MARK: - ReportGenerator

enum ReportGenerator {

    // MARK: - Generate

    /// Reads a heartbeat JSONL file, computes metrics, and generates an HTML report.
    /// Opens the report in the default browser and returns the file URL.
    static func generate(
        from heartbeatFile: URL,
        outputDir: URL = InkPulseDefaults.reportsDir
    ) -> URL? {
        // 1. Read and decode JSONL
        guard let data = try? Data(contentsOf: heartbeatFile) else {
            print("[InkPulse] Cannot read heartbeat file: \(heartbeatFile.path)")
            return nil
        }

        let lines = String(data: data, encoding: .utf8)?
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? []

        guard !lines.isEmpty else {
            print("[InkPulse] Heartbeat file is empty.")
            return nil
        }

        let decoder = JSONDecoder()
        var records: [HeartbeatRecord] = []
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let record = try? decoder.decode(HeartbeatRecord.self, from: lineData)
            else { continue }
            records.append(record)
        }

        guard !records.isEmpty else {
            print("[InkPulse] No valid records in heartbeat file.")
            return nil
        }

        // 2. Compute aggregates
        let avgHealth = records.map(\.health).reduce(0, +) / records.count
        let totalCost = records.map(\.costEur).max() ?? 0.0 // cumulative → take max
        let model = records.last?.model ?? "unknown"

        // 3. Chart data arrays
        let ecgLabels = records.map { "\"\($0.ts.suffix(8))\"" } // HH:MM:SS
        let ecgData = records.map { String(format: "%.1f", $0.tokenMin) }
        let costData = records.map { String(format: "%.4f", $0.costEur) }
        let toolData = records.map { String(format: "%.1f", $0.toolFreq) }

        // 4. Cache breakdown from last record
        let lastRecord = records.last!
        let cacheHitPct = lastRecord.cacheHit * 100
        let cacheMissPct = max(0, 100 - cacheHitPct - 5.0) // rough estimate
        let cacheCreationPct = max(0, 100 - cacheHitPct - cacheMissPct)

        // 5. Anomaly log rows
        let anomalyRows = records
            .filter { $0.anomaly != nil }
            .map { r in
                "<tr><td>\(r.ts)</td><td>\(r.sessionId.prefix(8))...</td><td>\(r.anomaly ?? "")</td><td>\(r.health)</td></tr>"
            }
            .joined(separator: "\n")

        // 6. Summary
        let summary = generateSummary(
            avgHealth: avgHealth,
            totalCost: totalCost,
            cacheHit: lastRecord.cacheHit
        )

        // 7. Build HTML
        let html = buildHTML(
            avgHealth: avgHealth,
            totalCost: totalCost,
            model: model,
            ecgLabels: ecgLabels,
            ecgData: ecgData,
            costData: costData,
            toolData: toolData,
            cacheHitPct: cacheHitPct,
            cacheMissPct: cacheMissPct,
            cacheCreationPct: cacheCreationPct,
            anomalyRows: anomalyRows,
            summary: summary,
            recordCount: records.count
        )

        // 8. Write file
        let fm = FileManager.default
        try? fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let sessionPrefix = String(records.first?.sessionId.prefix(8) ?? "unknown")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        let fileName = "report-\(sessionPrefix)-\(dateStr).html"
        let outputURL = outputDir.appendingPathComponent(fileName)

        guard let htmlData = html.data(using: .utf8) else { return nil }
        do {
            try htmlData.write(to: outputURL, options: .atomic)
        } catch {
            print("[InkPulse] Failed to write report: \(error)")
            return nil
        }

        // 9. Open in browser
        NSWorkspace.shared.open(outputURL)

        print("[InkPulse] Report generated: \(outputURL.path)")
        return outputURL
    }

    // MARK: - Summary

    private static func generateSummary(avgHealth: Int, totalCost: Double, cacheHit: Double) -> String {
        var insights: [String] = []

        // Health assessment
        if avgHealth >= 80 {
            insights.append("Session health is excellent (\(avgHealth)/100) — Claude is operating within optimal parameters.")
        } else if avgHealth >= 50 {
            insights.append("Session health is moderate (\(avgHealth)/100) — some metrics could be improved.")
        } else {
            insights.append("Session health is critical (\(avgHealth)/100) — review anomalies and consider adjusting prompts or model selection.")
        }

        // Cache efficiency
        let cachePercent = Int(cacheHit * 100)
        if cacheHit >= 0.6 {
            insights.append("Cache hit rate of \(cachePercent)% is strong — context reuse is efficient.")
        } else if cacheHit >= 0.3 {
            insights.append("Cache hit rate of \(cachePercent)% is moderate — consider structuring prompts for better cache utilization.")
        } else {
            insights.append("Cache hit rate of \(cachePercent)% is low — significant token waste from cache misses.")
        }

        // Cost comment
        if totalCost < 0.10 {
            insights.append("Total session cost of \(String(format: "€%.4f", totalCost)) is minimal.")
        } else if totalCost < 1.0 {
            insights.append("Total session cost of \(String(format: "€%.2f", totalCost)) is within normal range.")
        } else {
            insights.append("Total session cost of \(String(format: "€%.2f", totalCost)) is elevated — monitor for cost spikes.")
        }

        return insights.joined(separator: " ")
    }

    // MARK: - HTML Builder

    // swiftlint:disable:next function_parameter_count function_body_length
    private static func buildHTML(
        avgHealth: Int,
        totalCost: Double,
        model: String,
        ecgLabels: [String],
        ecgData: [String],
        costData: [String],
        toolData: [String],
        cacheHitPct: Double,
        cacheMissPct: Double,
        cacheCreationPct: Double,
        anomalyRows: String,
        summary: String,
        recordCount: Int
    ) -> String {
        let healthColor: String
        if avgHealth >= 80 {
            healthColor = "#00d4aa"
        } else if avgHealth >= 50 {
            healthColor = "#FFA500"
        } else {
            healthColor = "#FF4444"
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>InkPulse Report</title>
            <!-- TODO: Bundle Chart.js locally for offline use -->
            <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js"></script>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    background: #0a0f1a;
                    color: #e0e0e0;
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', 'Segoe UI', sans-serif;
                    padding: 2rem;
                    line-height: 1.6;
                }
                .header {
                    text-align: center;
                    margin-bottom: 2rem;
                    padding: 2rem;
                    background: #111827;
                    border-radius: 16px;
                    border: 1px solid #1e293b;
                }
                .header h1 {
                    font-size: 1.5rem;
                    color: #00d4aa;
                    margin-bottom: 1rem;
                    letter-spacing: 0.05em;
                }
                .health-score {
                    font-size: 5rem;
                    font-weight: 800;
                    color: \(healthColor);
                    line-height: 1;
                    margin: 0.5rem 0;
                }
                .health-label {
                    font-size: 0.9rem;
                    color: #9ca3af;
                    text-transform: uppercase;
                    letter-spacing: 0.1em;
                }
                .meta {
                    margin-top: 1rem;
                    color: #9ca3af;
                    font-size: 0.85rem;
                }
                .meta span { margin: 0 1rem; }
                .grid {
                    display: grid;
                    grid-template-columns: 1fr 1fr;
                    gap: 1.5rem;
                    margin-bottom: 1.5rem;
                }
                .card {
                    background: #111827;
                    border-radius: 12px;
                    padding: 1.5rem;
                    border: 1px solid #1e293b;
                }
                .card h2 {
                    font-size: 1rem;
                    color: #00d4aa;
                    margin-bottom: 1rem;
                    font-weight: 600;
                }
                .full-width { grid-column: 1 / -1; }
                canvas { max-height: 300px; }
                table {
                    width: 100%;
                    border-collapse: collapse;
                    font-size: 0.85rem;
                }
                th, td {
                    padding: 0.5rem 0.75rem;
                    text-align: left;
                    border-bottom: 1px solid #1e293b;
                }
                th {
                    color: #00d4aa;
                    font-weight: 600;
                    text-transform: uppercase;
                    font-size: 0.75rem;
                    letter-spacing: 0.05em;
                }
                td { color: #d1d5db; }
                .summary {
                    background: #111827;
                    border-radius: 12px;
                    padding: 1.5rem;
                    border: 1px solid #1e293b;
                    margin-top: 1.5rem;
                    color: #00d4aa;
                    font-size: 0.95rem;
                    line-height: 1.8;
                }
                .summary h2 { margin-bottom: 0.75rem; }
                .no-anomalies {
                    color: #9ca3af;
                    text-align: center;
                    padding: 1rem;
                    font-style: italic;
                }
            </style>
        </head>
        <body>
            <!-- Header -->
            <div class="header">
                <h1>INKPULSE REPORT</h1>
                <div class="health-label">Average Health Score</div>
                <div class="health-score">\(avgHealth)</div>
                <div class="meta">
                    <span>Model: <strong>\(model)</strong></span>
                    <span>Cost: <strong>\(String(format: "€%.4f", totalCost))</strong></span>
                    <span>Samples: <strong>\(recordCount)</strong></span>
                </div>
            </div>

            <!-- ECG Timeline (full width) -->
            <div class="grid">
                <div class="card full-width">
                    <h2>ECG Timeline — Tokens/min</h2>
                    <canvas id="ecgChart"></canvas>
                </div>

                <!-- Cost Burn -->
                <div class="card">
                    <h2>Cost Burn (EUR)</h2>
                    <canvas id="costChart"></canvas>
                </div>

                <!-- Tool Usage -->
                <div class="card">
                    <h2>Tool Usage (calls/min)</h2>
                    <canvas id="toolChart"></canvas>
                </div>

                <!-- Cache Efficiency -->
                <div class="card">
                    <h2>Cache Efficiency</h2>
                    <canvas id="cacheChart"></canvas>
                </div>

                <!-- Anomaly Log -->
                <div class="card">
                    <h2>Anomaly Log</h2>
                    \(anomalyRows.isEmpty
                        ? "<div class=\"no-anomalies\">No anomalies detected.</div>"
                        : """
                        <table>
                            <thead><tr><th>Timestamp</th><th>Session</th><th>Anomaly</th><th>Health</th></tr></thead>
                            <tbody>\(anomalyRows)</tbody>
                        </table>
                        """)
                </div>
            </div>

            <!-- Summary -->
            <div class="summary">
                <h2>Insights</h2>
                <p>\(summary)</p>
            </div>

            <script>
                const chartDefaults = Chart.defaults;
                chartDefaults.color = '#9ca3af';
                chartDefaults.borderColor = '#1e293b';

                const labels = [\(ecgLabels.joined(separator: ","))];

                // ECG Timeline
                new Chart(document.getElementById('ecgChart'), {
                    type: 'line',
                    data: {
                        labels: labels,
                        datasets: [{
                            label: 'Tokens/min',
                            data: [\(ecgData.joined(separator: ","))],
                            borderColor: '#00d4aa',
                            backgroundColor: 'rgba(0, 212, 170, 0.1)',
                            fill: true,
                            tension: 0.3,
                            pointRadius: 0,
                            borderWidth: 2
                        }]
                    },
                    options: {
                        responsive: true,
                        plugins: { legend: { display: false } },
                        scales: {
                            x: { grid: { color: '#1e293b' }, ticks: { maxTicksLimit: 10 } },
                            y: { grid: { color: '#1e293b' }, beginAtZero: true }
                        }
                    }
                });

                // Cost Burn
                new Chart(document.getElementById('costChart'), {
                    type: 'line',
                    data: {
                        labels: labels,
                        datasets: [{
                            label: 'Cost (EUR)',
                            data: [\(costData.joined(separator: ","))],
                            borderColor: '#FFA500',
                            backgroundColor: 'rgba(255, 165, 0, 0.1)',
                            fill: true,
                            tension: 0.3,
                            pointRadius: 0,
                            borderWidth: 2
                        }]
                    },
                    options: {
                        responsive: true,
                        plugins: { legend: { display: false } },
                        scales: {
                            x: { grid: { color: '#1e293b' }, ticks: { maxTicksLimit: 8 } },
                            y: { grid: { color: '#1e293b' }, beginAtZero: true }
                        }
                    }
                });

                // Tool Usage
                new Chart(document.getElementById('toolChart'), {
                    type: 'bar',
                    data: {
                        labels: labels,
                        datasets: [{
                            label: 'Tools/min',
                            data: [\(toolData.joined(separator: ","))],
                            backgroundColor: 'rgba(74, 158, 255, 0.7)',
                            borderColor: '#4A9EFF',
                            borderWidth: 1,
                            borderRadius: 3
                        }]
                    },
                    options: {
                        responsive: true,
                        plugins: { legend: { display: false } },
                        scales: {
                            x: { grid: { display: false }, ticks: { maxTicksLimit: 8 } },
                            y: { grid: { color: '#1e293b' }, beginAtZero: true }
                        }
                    }
                });

                // Cache Efficiency Doughnut
                new Chart(document.getElementById('cacheChart'), {
                    type: 'doughnut',
                    data: {
                        labels: ['Hit', 'Miss', 'Creation'],
                        datasets: [{
                            data: [\(String(format: "%.1f", cacheHitPct)), \(String(format: "%.1f", cacheMissPct)), \(String(format: "%.1f", cacheCreationPct))],
                            backgroundColor: ['#00d4aa', '#FF4444', '#FFA500'],
                            borderColor: '#0a0f1a',
                            borderWidth: 3
                        }]
                    },
                    options: {
                        responsive: true,
                        plugins: {
                            legend: {
                                position: 'bottom',
                                labels: { padding: 16, usePointStyle: true, pointStyle: 'circle' }
                            }
                        },
                        cutout: '65%'
                    }
                });
            </script>
        </body>
        </html>
        """
    }
}
