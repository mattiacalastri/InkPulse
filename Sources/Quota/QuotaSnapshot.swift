import Foundation

/// Represents a single quota tier (5-hour, 7-day, etc.).
struct QuotaTier {
    /// Utilization percentage (0-100) from Anthropic API.
    let utilization: Double
    let resetsAt: Date?

    /// Remaining as fraction (0.0-1.0). 29% utilization = 71% remaining.
    var remainingPercent: Double { max(0, (100.0 - utilization) / 100.0) }
    /// Utilization as fraction (0.0-1.0).
    var usedPercent: Double { min(1.0, utilization / 100.0) }
}

/// Extra usage (pay-as-you-go beyond plan).
struct ExtraUsageInfo {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
}

/// Detected Claude plan type based on quota limits.
enum ClaudePlan: String {
    case pro = "Pro"
    case max5x = "Max 5x"
    case max20x = "Max 20x"
    case api = "API"
    case unknown = "Unknown"
}

/// Aggregated quota snapshot from Anthropic OAuth usage endpoint.
struct QuotaSnapshot {
    let fiveHour: QuotaTier?
    let sevenDay: QuotaTier?
    let sevenDayOpus: QuotaTier?
    let sevenDaySonnet: QuotaTier?
    let plan: ClaudePlan
    let fetchedAt: Date

    /// Extra usage (pay-as-you-go beyond plan limits).
    let extraUsage: ExtraUsageInfo?

    /// Primary display: five-hour remaining percentage (most actionable).
    var primaryRemainingPercent: Double? { fiveHour?.remainingPercent }

    /// Primary display: five-hour utilization percentage.
    var primaryUsedPercent: Double? { fiveHour?.usedPercent }

    /// True if any tier is above 80% utilization.
    var isCritical: Bool {
        [fiveHour, sevenDay, sevenDayOpus, sevenDaySonnet]
            .compactMap { $0?.usedPercent }
            .contains(where: { $0 > 0.80 })
    }

    /// Detect plan from extra_usage field.
    /// If extra_usage is enabled, it's Max plan. Otherwise Pro.
    static func detectPlan(extraUsage: ExtraUsageInfo?) -> ClaudePlan {
        guard let eu = extraUsage else { return .pro }
        if eu.isEnabled { return .max5x }  // Max plans have extra_usage enabled
        return .pro
    }
}
