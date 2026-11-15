//
//  FanControlViewModel.swift
//  fan
//
//  Live sensor readings for the UI. Settings live in FanSettings; control in FanController.
//

import Foundation
import Combine
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UserNotifications

struct ThermalSample: Identifiable {
    let id = UUID()
    let date: Date
    let temperature: Double
    let fanSpeed: Int
}

@MainActor
final class FanControlViewModel: ObservableObject {
    @Published var cpuTemperature: Double?
    @Published var gpuTemperature: Double?
    @Published var fanSpeeds: [Int] = []
    @Published var fanMinSpeeds: [Int] = []
    @Published var fanMaxSpeeds: [Int] = []
    @Published var numberOfFans: Int = 0
    @Published var currentFanSpeed: Int = 0
    @Published var isMonitoring = false
    @Published var hasAccess = false
    @Published var lastError: String?
    @Published var thermalHistory: [ThermalSample] = []
    @Published var lastReading: Date?

    let settings: FanSettings
    let fanController: FanController
    private let systemMonitor = SystemMonitor()
    private var bag = Set<AnyCancellable>()
    private var lastHighTemperatureNotification: Date = .distantPast

    init(settings: FanSettings) {
        self.settings = settings
        self.fanController = FanController(systemMonitor: systemMonitor, settings: settings)

        bind()
        observeSleepAndWake()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func bind() {
        systemMonitor.$cpuTemperature.receive(on: DispatchQueue.main).assign(to: &$cpuTemperature)
        systemMonitor.$gpuTemperature.receive(on: DispatchQueue.main).assign(to: &$gpuTemperature)
        systemMonitor.$fanSpeeds.receive(on: DispatchQueue.main).assign(to: &$fanSpeeds)
        systemMonitor.$fanMinSpeeds.receive(on: DispatchQueue.main).assign(to: &$fanMinSpeeds)
        systemMonitor.$fanMaxSpeeds.receive(on: DispatchQueue.main).assign(to: &$fanMaxSpeeds)
        systemMonitor.$numberOfFans.receive(on: DispatchQueue.main).assign(to: &$numberOfFans)
        systemMonitor.$isMonitoring.receive(on: DispatchQueue.main).assign(to: &$isMonitoring)
        systemMonitor.$hasAccess.receive(on: DispatchQueue.main).assign(to: &$hasAccess)
        systemMonitor.$lastError.receive(on: DispatchQueue.main).assign(to: &$lastError)
        $fanSpeeds.map { $0.first ?? 0 }.assign(to: &$currentFanSpeed)

        $cpuTemperature
            .compactMap { $0 }
            .sink { [weak self] temp in self?.record(temp) }
            .store(in: &bag)

        settings.$monitoringInterval
            .removeDuplicates()
            .sink { [weak self] in self?.systemMonitor.setMonitoringInterval($0) }
            .store(in: &bag)
    }

    private func record(_ temp: Double) {
        lastReading = Date()
        thermalHistory.append(ThermalSample(date: Date(), temperature: temp, fanSpeed: currentFanSpeed))
        if thermalHistory.count > 60 { thermalHistory.removeFirst(thermalHistory.count - 60) }

        let hottest = getMaxTemperature()
        if settings.notifyHighTemp, hottest >= settings.highTempAlert {
            showHighTempNotification(hottest)
        }
    }

    private func showHighTempNotification(_ temperature: Double) {
        guard Date().timeIntervalSince(lastHighTemperatureNotification) >= 600 else { return }
        lastHighTemperatureNotification = Date()
        let content = UNMutableNotificationContent()
        content.title = "Your Mac is running hot"
        content.body = String(format: "%.0f°C — above your %.0f°C alert.", temperature, settings.highTempAlert)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "fan.high-temperature", content: content, trigger: nil))
    }

    // MARK: - Sleep and wake

    private func observeSleepAndWake() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willPowerOffNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(didWake), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func willSleep() { fanController.systemWillSleep() }
    @objc private func didWake() { fanController.systemDidWake() }

    // MARK: - Actions

    func startMonitoring() { systemMonitor.startMonitoring() }
    func stopMonitoring() { systemMonitor.stopMonitoring() }
    func applyPreset(_ preset: FanPreset) { fanController.choose(preset) }
    func resetToSystemControl() { fanController.releaseControl() }

    func checkAccess() -> Bool { systemMonitor.checkAccess() }

    // MARK: - Derived values

    func getMaxTemperature() -> Double {
        max(cpuTemperature ?? 0, gpuTemperature ?? 0)
    }

    /// 0…1 of the fan's range.
    var fanFraction: Double {
        let lo = Double(fanMinSpeeds.first ?? FanSettings.minRPM)
        let hi = Double(max(fanMaxSpeeds.first ?? FanSettings.maxRPM, FanSettings.maxRPM))
        guard hi > lo, currentFanSpeed > 0 else { return 0 }
        return min(1, max(0, (Double(currentFanSpeed) - lo) / (hi - lo)))
    }

    var fanPercent: Int { Int((Double(currentFanSpeed) / Double(FanSettings.maxRPM) * 100).rounded()) }

    // MARK: - Diagnostics

    func diagnosticsText() -> String {
        let speeds = fanSpeeds.map(String.init).joined(separator: ", ")
        return """
        Fan App diagnostics
        Generated: \(Date())
        Mode: \(settings.mode.label)
        Smart profile: \(settings.smartProfile.rawValue)
        Override: \(fanController.activeOverride)
        CPU: \(cpuTemperature.map { String(format: "%.1f C", $0) } ?? "Unavailable")
        GPU: \(gpuTemperature.map { String(format: "%.1f C", $0) } ?? "Unavailable")
        Fan speeds: \(speeds.isEmpty ? "Unavailable" : speeds)
        Target RPM: \(fanController.targetSpeed)
        Fans detected: \(numberOfFans)
        SMC access: \(hasAccess)
        Monitoring: \(isMonitoring)
        Helper installed: \(PermissionsManager.shared.isHelperInstalled)
        Launch at login: \(LaunchAtLoginManager.shared.registrationStatus)
        Last write succeeded: \(fanController.lastWriteSuccess)
        Status: \(fanController.statusMessage)
        Error: \(lastError ?? "None")
        """
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "fan-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? diagnosticsText().write(to: url, atomically: true, encoding: .utf8)
    }
}
