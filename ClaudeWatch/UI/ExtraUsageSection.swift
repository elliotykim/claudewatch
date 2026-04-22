import SwiftUI

struct ExtraUsageSection: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var preferences: Preferences

    private static let dollarFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    var body: some View {
        if let extra = coordinator.quota.extraUsage {
            VStack(alignment: .leading, spacing: 6) {
                Text("Extra usage").font(.headline)

                HStack {
                    Text("Current month: \(dollars(extra.usedCreditsCents)) of \(dollars(extra.monthlyLimitCents))")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(extra.usedPercentage))% used")
                        .font(.subheadline).monospacedDigit()
                }
                UsageBar(
                    value: extra.usedPercentage,
                    tint: preferences.progressBarColor.resolve(
                        usagePercent: extra.usedPercentage,
                        severity: coordinator.status.severity
                    )
                )
            }
        }
    }

    private func dollars(_ cents: Double) -> String {
        Self.dollarFormatter.string(from: NSNumber(value: cents / 100.0))
            ?? String(format: "$%.2f", cents / 100.0)
    }
}
