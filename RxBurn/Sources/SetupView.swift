import SwiftUI

struct SetupView: View {
    @ObservedObject var configManager: ConfigManager
    @State private var selectedPlan: PlanTier = .pro
    @State private var customBudget: String = "5.00"
    @State private var dailyTarget: String = "50"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's your Claude plan?")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(PlanTier.allCases, id: \.self) { tier in
                    Button {
                        selectedPlan = tier
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectedPlan == tier ? "circle.inset.filled" : "circle")
                                .foregroundStyle(selectedPlan == tier ? Color.accentColor : Color.secondary)
                                .font(.system(size: 12))

                            Text(tier.label)
                                .foregroundStyle(.primary)

                            Spacer()

                            if let budget = tier.defaultDailyBudget {
                                Text("$\(String(format: "%.2f", budget))/day")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedPlan == .custom {
                HStack {
                    Text("Daily cost: $")
                        .font(.caption)
                    TextField("5.00", text: $customBudget)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            HStack {
                Text("Daily target: $")
                    .font(.caption)
                TextField("50", text: $dailyTarget)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("(aim to burn this much)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button("Save") {
                let budget = Double(customBudget)
                let target = Double(dailyTarget)
                let config = RxBurnConfig(
                    plan: selectedPlan,
                    customDailyBudget: selectedPlan == .custom ? budget : nil,
                    dailyTarget: target
                )
                configManager.save(config)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .onAppear {
            if let existing = configManager.config {
                selectedPlan = existing.plan
                if let custom = existing.customDailyBudget {
                    customBudget = String(format: "%.2f", custom)
                }
                dailyTarget = String(format: "%.0f", existing.effectiveDailyTarget)
            }
        }
    }
}
