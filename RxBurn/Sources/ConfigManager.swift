import Foundation
import SwiftUI

enum PlanTier: String, Codable, CaseIterable {
    case pro
    case max5x
    case max20x
    case custom

    var label: String {
        switch self {
        case .pro: return "Pro"
        case .max5x: return "Max 5x"
        case .max20x: return "Max 20x"
        case .custom: return "Custom"
        }
    }

    var monthlyPrice: Double? {
        switch self {
        case .pro: return 20
        case .max5x: return 100
        case .max20x: return 200
        case .custom: return nil
        }
    }

    var defaultDailyBudget: Double? {
        guard let price = monthlyPrice else { return nil }
        return (price / 30.0 * 100).rounded() / 100
    }
}

struct RxBurnConfig: Codable, Equatable {
    var plan: PlanTier
    var customDailyBudget: Double?
    var dailyTarget: Double?

    var effectiveDailyBudget: Double {
        if plan == .custom {
            return customDailyBudget ?? 5.0
        }
        return plan.defaultDailyBudget ?? 5.0
    }

    var effectiveDailyTarget: Double {
        dailyTarget ?? 50.0
    }

    var monthlyBudget: Double {
        effectiveDailyBudget * 30
    }
}

@MainActor
class ConfigManager: ObservableObject {
    @Published var config: RxBurnConfig?
    @Published var needsSetup: Bool = true

    private static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/rxburn")
    private static let configFile = configDir.appendingPathComponent("config.json")

    init() {
        load()
    }

    func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.configFile.path) else {
            needsSetup = true
            return
        }

        do {
            let data = try Data(contentsOf: Self.configFile)
            let decoded = try JSONDecoder().decode(RxBurnConfig.self, from: data)
            config = decoded
            needsSetup = false
        } catch {
            needsSetup = true
        }
    }

    func save(_ newConfig: RxBurnConfig) {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: Self.configDir.path) {
                try fm.createDirectory(at: Self.configDir, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(newConfig)
            try data.write(to: Self.configFile)
            config = newConfig
            needsSetup = false
        } catch {
            // config write failed — stay in setup state
        }
    }

    func showSetup() {
        needsSetup = true
    }
}
