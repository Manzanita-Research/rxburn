import Foundation
import SwiftUI

struct ModelBreakdown: Codable {
    let modelName: String
    let cost: Double

    var model: String {
        modelName
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20251001", with: "")
    }
}

// MARK: - ccusage JSON shapes

private struct DailyEntry: Codable {
    let date: String
    let totalCost: Double
    let modelBreakdowns: [ModelBreakdown]?
}

private struct WeeklyEntry: Codable {
    let weekStart: String
    let totalCost: Double
}

private struct MonthlyEntry: Codable {
    let month: String
    let totalCost: Double
}

private struct DailyResponse: Codable {
    let daily: [DailyEntry]
    let totals: Totals
    struct Totals: Codable { let totalCost: Double }
}

private struct WeeklyResponse: Codable {
    let weekly: [WeeklyEntry]
    let totals: Totals
    struct Totals: Codable { let totalCost: Double }
}

private struct MonthlyResponse: Codable {
    let monthly: [MonthlyEntry]
    let totals: Totals
    struct Totals: Codable { let totalCost: Double }
}

// MARK: - Chart data

struct ChartEntry: Identifiable {
    let id = UUID()
    let label: String
    let cost: Double
    let date: Date?
}

enum UsageError: Equatable {
    case npxNotFound
    case fetchFailed(String)

    var description: String {
        switch self {
        case .npxNotFound: return "Node.js not found"
        case .fetchFailed(let msg): return msg
        }
    }
}

enum UsageState: Equatable {
    case loading
    case loaded(Double)
    case error(UsageError)
}

// MARK: - UsageMonitor

@MainActor
class UsageMonitor: ObservableObject {
    @Published var state: UsageState = .loading
    @Published var modelBreakdowns: [ModelBreakdown] = []
    @Published var lastUpdate: Date?

    @Published var dailyEntries: [ChartEntry] = []
    @Published var weeklyEntries: [ChartEntry] = []
    @Published var monthlyEntries: [ChartEntry] = []

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 300

    init() {
        Task {
            await fetchAll()
        }
        startTimer()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchAll()
            }
        }
    }

    func fetchAll() async {
        await fetch()
        await fetchHistory()
    }

    // MARK: - Today's cost (existing)

    func fetch() async {
        let today = Self.todayString()
        guard let result = await Self.runCCUsage(["daily", "--since", today, "--json", "--offline"]) else {
            state = .error(.npxNotFound)
            return
        }

        guard let (status, data) = result else {
            state = .error(.npxNotFound)
            return
        }

        guard status == 0 else {
            state = .error(.fetchFailed("ccusage exit \(status)"))
            return
        }

        do {
            let response = try JSONDecoder().decode(DailyResponse.self, from: data)
            state = .loaded(response.totals.totalCost)
            modelBreakdowns = response.daily.first?.modelBreakdowns ?? []
            lastUpdate = Date()
        } catch {
            state = .error(.fetchFailed(error.localizedDescription))
        }
    }

    // MARK: - Historical data

    private func fetchHistory() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchDaily() }
            group.addTask { await self.fetchWeekly() }
            group.addTask { await self.fetchMonthly() }
        }
    }

    private func fetchDaily() async {
        let since = Self.dateString(daysAgo: 30)
        guard let result = await Self.runCCUsage(["daily", "--since", since, "--json", "--offline"]),
              let (status, data) = result, status == 0 else { return }

        if let response = try? JSONDecoder().decode(DailyResponse.self, from: data) {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"

            let entries = response.daily.map { entry in
                let parsed = df.date(from: entry.date)
                let shortLabel: String
                if let date = parsed {
                    let display = DateFormatter()
                    display.dateFormat = "EEE"
                    shortLabel = display.string(from: date)
                } else {
                    shortLabel = entry.date
                }
                return ChartEntry(label: shortLabel, cost: entry.totalCost, date: parsed)
            }
            dailyEntries = entries
        }
    }

    private func fetchWeekly() async {
        let since = Self.dateString(daysAgo: 364)
        guard let result = await Self.runCCUsage(["weekly", "--since", since, "--json", "--offline"]),
              let (status, data) = result, status == 0 else { return }

        if let response = try? JSONDecoder().decode(WeeklyResponse.self, from: data) {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"

            let entries = response.weekly.enumerated().map { index, entry in
                let parsed = df.date(from: entry.weekStart)
                let shortLabel: String
                if let date = parsed {
                    let cal = Calendar.current
                    let month = cal.component(.month, from: date)
                    let prevMonth: Int? = index > 0 ? {
                        if let prev = df.date(from: response.weekly[index - 1].weekStart) {
                            return cal.component(.month, from: prev)
                        }
                        return nil
                    }() : nil
                    if prevMonth == nil || month != prevMonth {
                        let display = DateFormatter()
                        display.dateFormat = "MMM"
                        shortLabel = display.string(from: date)
                    } else {
                        shortLabel = ""
                    }
                } else {
                    shortLabel = entry.weekStart
                }
                return ChartEntry(label: shortLabel, cost: entry.totalCost, date: parsed)
            }
            weeklyEntries = entries
        }
    }

    private func fetchMonthly() async {
        guard let result = await Self.runCCUsage(["monthly", "--json", "--offline"]),
              let (status, data) = result, status == 0 else { return }

        if let response = try? JSONDecoder().decode(MonthlyResponse.self, from: data) {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM"

            let entries = response.monthly.map { entry in
                let parsed = df.date(from: entry.month)
                let shortLabel: String
                if let date = parsed {
                    let display = DateFormatter()
                    display.dateFormat = "MMM"
                    shortLabel = display.string(from: date)
                } else {
                    shortLabel = entry.month
                }
                return ChartEntry(label: shortLabel, cost: entry.totalCost, date: parsed)
            }
            monthlyEntries = entries
        }
    }

    // MARK: - Process helper

    private nonisolated static func runCCUsage(_ args: [String]) async -> Optional<(Int32, Data)?> {
        guard let npxPath = findNpx() else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: npxPath)
        process.arguments = ["ccusage@latest"] + args

        var env = ProcessInfo.processInfo.environment
        let npxDir = npxPath.split(separator: "/").dropLast().map(String.init).joined(separator: "/")
        let extraPaths = [
            "/\(npxDir)",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(NSHomeDirectory())/.bun/bin",
            "/usr/bin"
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return (1, Data())
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (process.terminationStatus, data))
            }
        }
    }

    // MARK: - Utilities

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }

    private static func dateString(daysAgo: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return f.string(from: date)
    }

    private nonisolated static func findNpx() -> String? {
        let home = NSHomeDirectory()
        let fm = FileManager.default

        let fnmBase = "\(home)/Library/Application Support/fnm/node-versions"
        if let versions = try? fm.contentsOfDirectory(atPath: fnmBase) {
            let sorted = versions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            for version in sorted {
                let candidate = "\(fnmBase)/\(version)/installation/bin/npx"
                if fm.isExecutableFile(atPath: candidate) { return candidate }
            }
        }

        let candidates = [
            "/opt/homebrew/bin/npx",
            "/usr/local/bin/npx",
            "\(home)/.bun/bin/npx",
            "/usr/bin/npx"
        ]

        let nvmBase = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmBase) {
            let sorted = versions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            for version in sorted {
                let candidate = "\(nvmBase)/\(version)/bin/npx"
                if fm.isExecutableFile(atPath: candidate) { return candidate }
            }
        }

        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }
}
