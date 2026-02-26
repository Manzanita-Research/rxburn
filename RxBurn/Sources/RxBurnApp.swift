import AppKit
import Charts
import SwiftUI

@main
struct RxBurnApp: App {
    @StateObject private var usage = UsageMonitor()
    @StateObject private var configManager = ConfigManager()

    var body: some Scene {
        MenuBarExtra {
            PopoverContent(usage: usage, configManager: configManager)
                .frame(width: 360)
        } label: {
            MenuBarLabel(usage: usage, dailyBudget: configManager.config?.effectiveDailyBudget, dailyTarget: configManager.config?.effectiveDailyTarget ?? 50)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu bar label

struct MenuBarLabel: View {
    @ObservedObject var usage: UsageMonitor
    var dailyBudget: Double?
    var dailyTarget: Double

    var body: some View {
        switch usage.state {
        case .loading:
            Text("…")
        case .error:
            Text("⚠")
        case .loaded(let cost):
            let tier = dailyBudget.map { burnTier(cost: cost, dailyCost: $0, target: dailyTarget) } ?? .cold
            Image(nsImage: textImage(costString(cost), tier: tier))
        }
    }

    private func costString(_ cost: Double) -> String {
        "$\(String(format: "%.2f", cost))"
    }

    private func textImage(_ text: String, tier: BurnTier) -> NSImage {
        let color: NSColor = tier == .cold ? .labelColor : tier.nsColor
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let image = NSImage(size: size)
        image.lockFocus()
        str.draw(at: .zero)
        image.unlockFocus()
        image.isTemplate = tier == .cold
        return image
    }
}

// MARK: - Burn tiers

enum BurnTier {
    case cold    // under daily subscription cost — not getting your money's worth
    case warm    // between subscription cost and $50 — decent
    case hot     // over $50 — burning bright

    var color: Color {
        switch self {
        case .cold: return .red
        case .warm: return .orange
        case .hot: return .green
        }
    }

    var nsColor: NSColor {
        switch self {
        case .cold: return .systemRed
        case .warm: return .systemOrange
        case .hot: return .systemGreen
        }
    }
}

func burnTier(cost: Double, dailyCost: Double, target: Double) -> BurnTier {
    if cost < dailyCost { return .cold }
    if cost < target { return .warm }
    return .hot
}

// MARK: - Dependency error

struct DependencyErrorView: View {
    @ObservedObject var usage: UsageMonitor
    private let installCommand = "brew install node"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Node.js not found")
                .font(.headline)

            Text("RxBurn needs Node.js to fetch usage data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Text(installCommand)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .cornerRadius(4)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(installCommand, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            Button("Retry") {
                Task { await usage.fetchAll() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
}

// MARK: - Popover content

struct PopoverContent: View {
    @ObservedObject var usage: UsageMonitor
    @ObservedObject var configManager: ConfigManager

    private var hasDependencyError: Bool {
        if case .error(.npxNotFound) = usage.state { return true }
        return false
    }

    var body: some View {
        if hasDependencyError {
            DependencyErrorView(usage: usage)
        } else if configManager.needsSetup {
            SetupView(configManager: configManager)
        } else {
            normalContent
        }
    }

    private var normalContent: some View {
        let budget = configManager.config?.effectiveDailyBudget ?? 5.0
        let target = configManager.config?.effectiveDailyTarget ?? 50.0

        return VStack(spacing: 0) {
            UsageChartView(usage: usage, dailyBudget: budget, dailyTarget: target)
                .id(target)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            TodaySummary(usage: usage, dailyBudget: budget, dailyTarget: target)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            HStack {
                Button("Refresh") {
                    Task { await usage.fetchAll() }
                }
                .keyboardShortcut("r")

                Spacer()

                Button("Settings") {
                    configManager.showSetup()
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Today summary

struct TodaySummary: View {
    @ObservedObject var usage: UsageMonitor
    var dailyBudget: Double
    var dailyTarget: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .loaded(let cost) = usage.state {
                let tier = burnTier(cost: cost, dailyCost: dailyBudget, target: dailyTarget)
                let ratio = cost / max(dailyBudget, 0.01)

                HStack {
                    Text("Today")
                        .font(.headline)
                    Spacer()
                    Text("$\(String(format: "%.2f", cost))")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(tier.color)
                }

                Text(burnMessage(tier: tier, ratio: ratio, cost: cost))
                    .foregroundStyle(tier.color)
                    .font(.caption)

                if !usage.modelBreakdowns.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(usage.modelBreakdowns, id: \.model) { breakdown in
                            HStack {
                                Text(breakdown.model)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("$\(String(format: "%.2f", breakdown.cost))")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if case .error(let err) = usage.state {
                Text("Error: \(err.description)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if let lastUpdate = usage.lastUpdate {
                Text("Updated \(lastUpdate.formatted(.relative(presentation: .named)))")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
            }
        }
    }

    private func burnMessage(tier: BurnTier, ratio: Double, cost: Double) -> String {
        switch tier {
        case .cold:
            return "Only \(String(format: "%.1f", ratio))x your subscription — burn more"
        case .warm:
            return "\(String(format: "%.0f", ratio))x your subscription today"
        case .hot:
            return "\(String(format: "%.0f", ratio))x your subscription — cooking"
        }
    }
}

// MARK: - Chart

enum ChartPeriod: String, CaseIterable {
    case week = "Week"
    case month = "Month"
}

struct UsageChartView: View {
    @ObservedObject var usage: UsageMonitor
    var dailyBudget: Double
    var dailyTarget: Double
    @State private var period: ChartPeriod = .week

    var body: some View {
        VStack(spacing: 12) {
            Picker("Period", selection: $period) {
                ForEach(ChartPeriod.allCases, id: \.self) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let entries = chartEntries
            if entries.isEmpty {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .frame(height: 160)
            } else {
                let maxCost = entries.map(\.cost).max() ?? 0
                let yMax = max(300, maxCost * 1.2)
                let yTicks = Array(stride(from: 0.0, through: yMax, by: 50.0))

                Chart {
                    ForEach(entries) { entry in
                        if let date = entry.date {
                            BarMark(
                                x: .value("Date", date, unit: .day),
                                y: .value("Cost", entry.cost)
                            )
                            .foregroundStyle(burnTier(cost: entry.cost, dailyCost: dailyBudget, target: dailyTarget).color)
                            .cornerRadius(2)
                        }
                    }

                    RuleMark(y: .value("Subscription Cost", dailyBudget))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.red.opacity(0.5))

                    RuleMark(y: .value("Daily Target", dailyTarget))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 3]))
                        .foregroundStyle(.orange.opacity(0.7))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: xAxisStride, count: xAxisCount)) { value in
                        AxisValueLabel(format: xAxisFormat)
                            .font(.system(size: 9))
                    }
                }
                .chartYScale(domain: 0...yMax)
                .chartYAxis {
                    AxisMarks(position: .leading, values: yTicks) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("$\(Int(v))")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
    }

    private var xAxisStride: Calendar.Component {
        .day
    }

    private var xAxisCount: Int {
        period == .week ? 1 : 7
    }

    private var xAxisFormat: Date.FormatStyle {
        period == .week
            ? .dateTime.weekday(.abbreviated)
            : .dateTime.month(.defaultDigits).day()
    }

    private var chartEntries: [ChartEntry] {
        switch period {
        case .week:
            return filledDaily(usage.dailyEntries, days: 7)
        case .month:
            return filledDaily(usage.dailyEntries, days: 30)
        }
    }

    private func filledDaily(_ entries: [ChartEntry], days: Int) -> [ChartEntry] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var lookup: [String: Double] = [:]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for entry in entries {
            if let date = entry.date {
                lookup[df.string(from: date)] = entry.cost
            }
        }

        return (0..<days).reversed().map { daysAgo in
            let date = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            let key = df.string(from: date)
            let cost = lookup[key] ?? 0
            return ChartEntry(label: "", cost: cost, date: date)
        }
    }
}
