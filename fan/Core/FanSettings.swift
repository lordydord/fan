//
//  FanSettings.swift
//  fan
//
//  The single source of truth for everything the user chooses.
//
//  Every value is written to UserDefaults the moment it changes, and nothing else in the
//  app writes these keys. Temporary states — Boost, emergency cooling, "switch to Smart
//  while hot", sleep and display sleep — live in FanController and are never saved, so
//  they can't overwrite what was chosen. After a restart or a sleep the app always comes
//  back to exactly these values.
//

import Foundation
import Combine

enum ControlMode: String, CaseIterable, Identifiable {
    case system      // macOS manages the fans
    case automatic   // Smart curve
    case manual      // one fixed speed
    case maximum     // every fan at full speed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "macOS"
        case .automatic: return "Smart"
        case .manual: return "Manual"
        case .maximum: return "Max"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "apple.logo"
        case .automatic: return "sparkles"
        case .manual: return "dial.medium"
        case .maximum: return "wind"
        }
    }
}

enum FanPreset: String, CaseIterable, Identifiable {
    case system = "System"
    case quiet = "Quiet"
    case balanced = "Balanced"
    case performance = "Performance"
    case maximum = "Max"
    case custom = "Custom"

    /// Shown in the menu bar's right-click menu.
    static let selectableCases: [FanPreset] = [.system, .quiet, .balanced, .performance, .maximum]
    /// The Smart profiles.
    static let smartCases: [FanPreset] = [.quiet, .balanced, .performance]

    var id: String { rawValue }

    /// Start temperature, top speed and response for the Smart profiles.
    var curve: (threshold: Double, maxSpeed: Int, response: Double)? {
        switch self {
        case .quiet: return (65, 3600, 0.75)
        case .balanced: return (60, 5000, 1.5)
        case .performance: return (50, FanSettings.maxRPM, 2.25)
        default: return nil
        }
    }

    var symbol: String {
        switch self {
        case .system: return "apple.logo"
        case .quiet: return "leaf.fill"
        case .balanced: return "circle.lefthalf.filled"
        case .performance: return "bolt.fill"
        case .maximum: return "wind"
        case .custom: return "slider.horizontal.3"
        }
    }
}

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case temperature
    case fanSpeedPercentage
    case power
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .temperature: return "Temp"
        case .fanSpeedPercentage: return "Fan %"
        case .power: return "Power"
        case .none: return "Icon"
        }
    }
}

final class FanSettings: ObservableObject {
    static let shared = FanSettings()

    static let minRPM = 1000
    static let maxRPM = 6500
    static let intervals: [Double] = [2, 5, 10, 30]

    private enum Key {
        static let mode = "fanControlMode"
        static let profile = "activePreset"
        static let manualSpeed = "manualFanSpeed"
        static let threshold = "autoThreshold"
        static let maxSpeed = "autoMaxSpeed"
        static let response = "autoAggressiveness"
        static let emergencyEnabled = "emergencyProtectionEnabled"
        static let emergencyTemperature = "emergencyTemperature"
        static let highTempAlert = "highTempAlert"
        static let notify = "enableNotifications"
        static let autoSwitch = "autoSwitchMode"
        static let menuBar = "statusBarDisplayMode"
        static let interval = "monitoringInterval"
        static let launchAtLogin = "launchAtLogin"
        static let schema = "settingsSchema"
    }

    private let d = UserDefaults.standard

    @Published var mode: ControlMode { didSet { d.set(mode.rawValue, forKey: Key.mode) } }
    /// Which Smart profile is in use: quiet, balanced, performance or custom.
    @Published var smartProfile: FanPreset { didSet { d.set(smartProfile.rawValue, forKey: Key.profile) } }
    @Published var manualSpeed: Int { didSet { d.set(manualSpeed, forKey: Key.manualSpeed) } }
    @Published var autoThreshold: Double { didSet { d.set(autoThreshold, forKey: Key.threshold) } }
    @Published var autoMaxSpeed: Int { didSet { d.set(autoMaxSpeed, forKey: Key.maxSpeed) } }
    @Published var autoAggressiveness: Double { didSet { d.set(autoAggressiveness, forKey: Key.response) } }
    @Published var emergencyEnabled: Bool { didSet { d.set(emergencyEnabled, forKey: Key.emergencyEnabled) } }
    @Published var emergencyTemperature: Double { didSet { d.set(emergencyTemperature, forKey: Key.emergencyTemperature) } }
    @Published var highTempAlert: Double { didSet { d.set(highTempAlert, forKey: Key.highTempAlert) } }
    @Published var notifyHighTemp: Bool { didSet { d.set(notifyHighTemp, forKey: Key.notify) } }
    /// While hot in macOS or Manual mode, run the Smart curve until it cools. Never changes `mode`.
    @Published var autoSwitchWhenHot: Bool { didSet { d.set(autoSwitchWhenHot, forKey: Key.autoSwitch) } }
    @Published var menuBarDisplay: MenuBarDisplay { didSet { d.set(menuBarDisplay.rawValue, forKey: Key.menuBar) } }
    @Published var monitoringInterval: Double { didSet { d.set(monitoringInterval, forKey: Key.interval) } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: Key.launchAtLogin) } }

    private init() {
        d.register(defaults: [
            Key.mode: ControlMode.automatic.rawValue,
            Key.profile: FanPreset.balanced.rawValue,
            Key.manualSpeed: 3000,
            Key.threshold: 60.0,
            Key.maxSpeed: 5000,
            Key.response: 1.5,
            Key.emergencyEnabled: true,
            Key.emergencyTemperature: 90.0,
            Key.highTempAlert: 85.0,
            Key.notify: true,
            Key.autoSwitch: false,
            Key.menuBar: MenuBarDisplay.temperature.rawValue,
            Key.interval: 5.0,
            Key.launchAtLogin: false,
        ])

        let storedProfile = d.string(forKey: Key.profile) ?? ""
        var mode = ControlMode(rawValue: d.string(forKey: Key.mode) ?? "") ?? .automatic
        var manual = d.integer(forKey: Key.manualSpeed)

        // Before 1.2, macOS and Max were stored as profiles rather than modes, and Max and
        // Boost overwrote the manual speed with 6,500 RPM. Move them over once.
        if d.integer(forKey: Key.schema) < 2 {
            if storedProfile == FanPreset.system.rawValue { mode = .system }
            if storedProfile == FanPreset.maximum.rawValue { mode = .maximum }
            if manual >= Self.maxRPM { manual = 3000 }
            d.set(2, forKey: Key.schema)
        }

        let threshold = d.double(forKey: Key.threshold)
        let maxSpeed = d.integer(forKey: Key.maxSpeed)
        let response = d.double(forKey: Key.response)
        let emergency = d.double(forKey: Key.emergencyTemperature)
        let alert = d.double(forKey: Key.highTempAlert)
        let interval = d.double(forKey: Key.interval)

        self.mode = mode
        self.manualSpeed = (Self.minRPM...Self.maxRPM).contains(manual) ? manual : 3000
        self.autoThreshold = (40...90).contains(threshold) ? threshold : 60
        self.autoMaxSpeed = (Self.minRPM...Self.maxRPM).contains(maxSpeed) ? maxSpeed : 5000
        self.autoAggressiveness = (0...3).contains(response) ? response : 1.5
        self.emergencyEnabled = d.bool(forKey: Key.emergencyEnabled)
        self.emergencyTemperature = (75...105).contains(emergency) ? emergency : 90
        self.highTempAlert = (60...100).contains(alert) ? alert : 85
        self.notifyHighTemp = d.bool(forKey: Key.notify)
        self.autoSwitchWhenHot = d.bool(forKey: Key.autoSwitch)
        self.menuBarDisplay = MenuBarDisplay(rawValue: d.string(forKey: Key.menuBar) ?? "") ?? .temperature
        self.monitoringInterval = Self.intervals.min(by: { abs($0 - interval) < abs($1 - interval) }) ?? 5
        self.launchAtLogin = d.bool(forKey: Key.launchAtLogin)

        let profile = FanPreset(rawValue: storedProfile)
        if let profile, profile == .custom || FanPreset.smartCases.contains(profile) {
            self.smartProfile = profile
        } else {
            self.smartProfile = .custom
            self.smartProfile = inferredProfile()
        }

        // Write back anything that was migrated or clamped so the stored file matches.
        d.set(self.mode.rawValue, forKey: Key.mode)
        d.set(self.smartProfile.rawValue, forKey: Key.profile)
        d.set(self.manualSpeed, forKey: Key.manualSpeed)
        d.set(self.monitoringInterval, forKey: Key.interval)
    }

    private func inferredProfile() -> FanPreset {
        FanPreset.smartCases.first { p in
            guard let c = p.curve else { return false }
            return c.threshold == autoThreshold && c.maxSpeed == autoMaxSpeed && abs(c.response - autoAggressiveness) < 0.01
        } ?? .custom
    }

    // MARK: - Choosing

    /// The profile chip that should look selected, if any.
    var selectedPreset: FanPreset? {
        switch mode {
        case .system: return .system
        case .maximum: return .maximum
        case .automatic: return smartProfile
        case .manual: return nil
        }
    }

    func choose(_ preset: FanPreset) {
        switch preset {
        case .system:
            mode = .system
        case .maximum:
            mode = .maximum
        case .custom:
            smartProfile = .custom
            mode = .automatic
        case .quiet, .balanced, .performance:
            if let c = preset.curve {
                autoThreshold = c.threshold
                autoMaxSpeed = c.maxSpeed
                autoAggressiveness = c.response
            }
            smartProfile = preset
            mode = .automatic
        }
    }

    func setThreshold(_ value: Double) {
        let v = max(40, min(90, value.rounded()))
        guard v != autoThreshold else { return }
        autoThreshold = v
        smartProfile = inferredProfile()
    }

    func setResponse(_ value: Double) {
        let v = (max(0, min(3, value)) * 10).rounded() / 10
        guard abs(v - autoAggressiveness) > 0.001 else { return }
        autoAggressiveness = v
        smartProfile = inferredProfile()
    }

    func setTopSpeed(_ value: Int) {
        let v = max(Self.minRPM, min(Self.maxRPM, (value / 100) * 100))
        guard v != autoMaxSpeed else { return }
        autoMaxSpeed = v
        smartProfile = inferredProfile()
    }

    func setManualSpeed(_ value: Int) {
        let v = max(Self.minRPM, min(Self.maxRPM, (value / 100) * 100))
        if v != manualSpeed { manualSpeed = v }
    }
}
