import Foundation

/// Per-token pricing for a single model.
struct ModelPricing {
    let inputPerMillion: Double   // USD per 1M input tokens
    let outputPerMillion: Double  // USD per 1M output tokens
}

/// Model pricing table and cost helpers.
enum Pricing {

    // MARK: - Model Table (USD per 1M tokens)

    static let models: [String: ModelPricing] = [
        // Claude 4.x
        "claude-opus-4":          ModelPricing(inputPerMillion: 15.0,  outputPerMillion: 75.0),
        "claude-opus-4-6":        ModelPricing(inputPerMillion: 15.0,  outputPerMillion: 75.0),
        "claude-sonnet-4":        ModelPricing(inputPerMillion: 3.0,   outputPerMillion: 15.0),
        "claude-sonnet-4-6":      ModelPricing(inputPerMillion: 3.0,   outputPerMillion: 15.0),
        "claude-haiku-4-5":       ModelPricing(inputPerMillion: 0.80,  outputPerMillion: 4.0),
        // Claude 3.5
        "claude-3-5-sonnet":      ModelPricing(inputPerMillion: 3.0,   outputPerMillion: 15.0),
        "claude-3-5-haiku":       ModelPricing(inputPerMillion: 0.80,  outputPerMillion: 4.0),
        // Legacy
        "claude-haiku-3.5":       ModelPricing(inputPerMillion: 0.25,  outputPerMillion: 1.25),
    ]

    // MARK: - EUR/USD

    /// 1 USD = 0.91 EUR
    static let eurUsdRate: Double = 0.91

    // MARK: - Cache Discounts

    /// Cache read tokens cost 90% less than regular input tokens.
    static let cacheReadDiscount: Double = 0.90
    /// Cache creation tokens cost 25% more than regular input tokens.
    static let cacheCreationSurcharge: Double = 0.25

    // MARK: - Model Lookup

    /// Find pricing for a model, handling date-suffixed variants like "claude-opus-4-6-20251001".
    static func findPricing(for model: String) -> ModelPricing? {
        if let p = models[model] { return p }
        // Strip date suffix (e.g., "-20251001")
        let stripped = model.replacingOccurrences(of: #"-\d{8,}$"#, with: "", options: .regularExpression)
        if let p = models[stripped] { return p }
        // Try prefix match
        return models.first(where: { model.hasPrefix($0.key) })?.value
    }

    // MARK: - Cost Calculation

    /// Compute total cost in EUR for a given usage.
    ///
    /// - Parameters:
    ///   - model: Model identifier (e.g. "claude-opus-4").
    ///   - inputTokens: Regular (non-cached) input tokens.
    ///   - outputTokens: Output tokens.
    ///   - cacheReadTokens: Tokens served from cache.
    ///   - cacheCreationTokens: Tokens written to cache.
    /// - Returns: Total cost in EUR, or `nil` if model is unknown.
    static func costEUR(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0
    ) -> Double? {
        guard let pricing = findPricing(for: model) else { return nil }

        let inputCostUSD = Double(inputTokens) / 1_000_000.0 * pricing.inputPerMillion
        let outputCostUSD = Double(outputTokens) / 1_000_000.0 * pricing.outputPerMillion

        let cacheReadCostUSD = Double(cacheReadTokens) / 1_000_000.0
            * pricing.inputPerMillion * (1.0 - cacheReadDiscount)
        let cacheCreationCostUSD = Double(cacheCreationTokens) / 1_000_000.0
            * pricing.inputPerMillion * (1.0 + cacheCreationSurcharge)

        let totalUSD = inputCostUSD + outputCostUSD + cacheReadCostUSD + cacheCreationCostUSD
        return totalUSD * eurUsdRate
    }
}
