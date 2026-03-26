import Foundation

/// Per-token pricing for a single model (USD per 1M tokens).
struct ModelPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheReadPerMillion: Double
    let cacheCreatePerMillion: Double
}

/// Model pricing table and cost helpers.
/// Prices from CodexBar's CostUsagePricing.swift (verified Mar 2026).
enum Pricing {

    // MARK: - Standard Pricing (USD per 1M tokens)

    static let models: [String: ModelPricing] = [
        // Claude 4.x — standard tier (<=200K context)
        "claude-opus-4":          ModelPricing(inputPerMillion: 5.0,   outputPerMillion: 25.0,  cacheReadPerMillion: 0.50,  cacheCreatePerMillion: 6.25),
        "claude-opus-4-6":        ModelPricing(inputPerMillion: 5.0,   outputPerMillion: 25.0,  cacheReadPerMillion: 0.50,  cacheCreatePerMillion: 6.25),
        "claude-sonnet-4":        ModelPricing(inputPerMillion: 3.0,   outputPerMillion: 15.0,  cacheReadPerMillion: 0.30,  cacheCreatePerMillion: 3.75),
        "claude-sonnet-4-6":      ModelPricing(inputPerMillion: 3.0,   outputPerMillion: 15.0,  cacheReadPerMillion: 0.30,  cacheCreatePerMillion: 3.75),
        "claude-haiku-4-5":       ModelPricing(inputPerMillion: 1.0,   outputPerMillion: 5.0,   cacheReadPerMillion: 0.10,  cacheCreatePerMillion: 1.25),
        // Claude 3.5
        "claude-3-5-sonnet":      ModelPricing(inputPerMillion: 3.0,   outputPerMillion: 15.0,  cacheReadPerMillion: 0.30,  cacheCreatePerMillion: 3.75),
        "claude-3-5-haiku":       ModelPricing(inputPerMillion: 1.0,   outputPerMillion: 5.0,   cacheReadPerMillion: 0.10,  cacheCreatePerMillion: 1.25),
        // Legacy
        "claude-haiku-3.5":       ModelPricing(inputPerMillion: 0.25,  outputPerMillion: 1.25,  cacheReadPerMillion: 0.025, cacheCreatePerMillion: 0.3125),
    ]

    // MARK: - Tiered Pricing (Sonnet >200K context)

    /// Sonnet models double their price above 200K context tokens.
    static let tieredModels: [String: ModelPricing] = [
        "claude-sonnet-4":        ModelPricing(inputPerMillion: 6.0,   outputPerMillion: 22.5,  cacheReadPerMillion: 0.60,  cacheCreatePerMillion: 7.50),
        "claude-sonnet-4-6":      ModelPricing(inputPerMillion: 6.0,   outputPerMillion: 22.5,  cacheReadPerMillion: 0.60,  cacheCreatePerMillion: 7.50),
        "claude-3-5-sonnet":      ModelPricing(inputPerMillion: 6.0,   outputPerMillion: 22.5,  cacheReadPerMillion: 0.60,  cacheCreatePerMillion: 7.50),
    ]

    /// Context token threshold for tiered pricing.
    static let tierThreshold: Int = 200_000

    // MARK: - EUR/USD

    static let eurUsdRate: Double = 0.91

    // MARK: - Model Lookup

    /// Find pricing for a model, with optional tiered pricing for >200K context.
    static func findPricing(for model: String, contextTokens: Int = 0) -> ModelPricing? {
        // Check tiered pricing first
        if contextTokens > tierThreshold {
            if let tiered = findInTable(model, table: tieredModels) {
                return tiered
            }
        }
        return findInTable(model, table: models)
    }

    private static func findInTable(_ model: String, table: [String: ModelPricing]) -> ModelPricing? {
        if let p = table[model] { return p }
        // Strip date suffix (e.g., "-20251001")
        let stripped = model.replacingOccurrences(of: #"-\d{8,}$"#, with: "", options: .regularExpression)
        if let p = table[stripped] { return p }
        // Try prefix match
        return table.first(where: { model.hasPrefix($0.key) })?.value
    }

    // MARK: - Cost Calculation

    /// Compute total cost in EUR for a given usage.
    static func costEUR(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        contextTokens: Int = 0
    ) -> Double? {
        guard let pricing = findPricing(for: model, contextTokens: contextTokens) else { return nil }

        let inputCostUSD = Double(inputTokens) / 1_000_000.0 * pricing.inputPerMillion
        let outputCostUSD = Double(outputTokens) / 1_000_000.0 * pricing.outputPerMillion
        let cacheReadCostUSD = Double(cacheReadTokens) / 1_000_000.0 * pricing.cacheReadPerMillion
        let cacheCreationCostUSD = Double(cacheCreationTokens) / 1_000_000.0 * pricing.cacheCreatePerMillion

        let totalUSD = inputCostUSD + outputCostUSD + cacheReadCostUSD + cacheCreationCostUSD
        return totalUSD * eurUsdRate
    }
}
