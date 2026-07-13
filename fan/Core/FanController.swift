//
//  FanController.swift
//  ffan
//
//  Created by mohamad on 11/1/2026.
//  Fixed for proper SMC fan control with sudoers
//

import Foundation
import Combine
import IOKit

enum ControlMode: String, CaseIterable {
    case manual
    case automatic
}

enum FanPreset: String, CaseIterable, Identifiable {
    case system = "System"
    case quiet = "Quiet"
    case balanced = "Balanced"
    case performance = "Performance"
    case maximum = "Max"
    case custom = "Custom"

    static let selectableCases: [FanPreset] = [.system, .quiet, .balanced, .performance, .maximum]
    var id: String { rawValue }
}

class FanController: ObservableObject {
    @Published var mode: ControlMode = .manual
    @Published var manualSpeed: Int = 2000
    @Published var autoThreshold: Double = 60.0
    @Published var autoMaxSpeed: Int = 6500
    @Published var autoAggressiveness: Double = 1.5  // 0.0 = minimal response, 1.5 = linear, 3.0 = strongest response above target
    @Published var isControlEnabled = false
    @Published var lastWriteSuccess = false
    @Published var statusMessage: String = ""
    @Published var lastAppliedSpeed: Int = 0  // Track what we last applied
    @Published var activePreset: FanPreset = .balanced
    @Published var emergencyProtectionEnabled = true
    @Published var emergencyTemperature: Double = 90
    @Published var boostEndDate: Date?
    
    private weak var systemMonitor: SystemMonitor?
    private var autoControlTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastUpdateTime: Date = .distantPast
    private var watchdogProcess: Process?
    private var boostRestore: (ControlMode, Int, FanPreset)?
    
    let minSpeed = 1000
    let maxSpeed = 6500
    
    // Path to the installed smc-helper
    private var smcHelperPath: String {
        return "/usr/local/bin/smc-helper"
    }
    
    init(systemMonitor: SystemMonitor) {
        self.systemMonitor = systemMonitor
        loadSettings()
        
        // Observe fan detection and apply settings when ready
        systemMonitor.$numberOfFans
            .receive(on: DispatchQueue.main)
            .filter { $0 > 0 }
            .first()
            .sink { [weak self] _ in
                print("FanController: Fans detected, applying initial settings")
                self?.applyInitialSettings()
            }
            .store(in: &cancellables)
    }
    
    deinit {
        stopWatchdog()
        stopAutoControl()
        restoreAutomaticControl()
    }
    
    private func applyInitialSettings() {
        print("FanController: Applying initial settings - mode: \(mode)")

        if activePreset == .system {
            restoreAutomaticControl()
            return
        }
        
        switch mode {
        case .manual:
            enableManualMode()
            applyFanSpeed(manualSpeed)
        case .automatic:
            startAutoControl()
        }
    }
    
    func reapplySettings() {
        print("FanController: Reapplying settings after wake - mode: \(mode)")
        
        // Check if fans are detected, retry if not
        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else {
            print("FanController: No fans detected yet, retrying in 2 seconds...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.reapplySettings()
            }
            return
        }

        if activePreset == .system {
            restoreAutomaticControl()
            return
        }
        
        switch mode {
        case .manual:
            enableManualMode()
            applyFanSpeed(manualSpeed)
            print("FanController: Manual mode reapplied at \(manualSpeed) RPM")
        case .automatic:
            enableManualMode() // Enable control first
            startAutoControl()
            // Force immediate speed application based on last known speed or a safe default
            let safeSpeed = lastAppliedSpeed > 0 ? lastAppliedSpeed : 3000
            applyFanSpeed(safeSpeed)
            print("FanController: Auto mode reapplied, initial speed: \(safeSpeed) RPM")
        }
    }
    
    func setManualSpeed(_ speed: Int) {
        guard mode == .manual else { return }
        
        let clampedSpeed = max(minSpeed, min(maxSpeed, speed))
        manualSpeed = clampedSpeed
        activePreset = clampedSpeed == maxSpeed ? .maximum : .custom
        
        if isControlEnabled {
            applyFanSpeed(clampedSpeed)
        }
        
        saveSettings() // Save immediately for UI responsiveness
    }
    
    func setMode(_ newMode: ControlMode, preservePreset: Bool = false) {
        mode = newMode
        if !preservePreset {
            activePreset = newMode == .manual && manualSpeed == maxSpeed ? .maximum : .custom
        }
        
        if newMode == .automatic {
            restoreAutomaticControl()
            startAutoControl()
        } else {
            stopAutoControl()
            enableManualMode()
            applyFanSpeed(manualSpeed)
        }
        
        saveSettings()
    }
    
    private func enableManualMode() {
        guard systemMonitor != nil else {
            statusMessage = "No system monitor available"
            return
        }
        isControlEnabled = true
        statusMessage = "Manual control enabled"
        print("Fan Control: Manual control enabled")
    }
    
    func restoreAutomaticControl() {
        guard let monitor = systemMonitor else { return }
        guard monitor.numberOfFans > 0 else { return }
        
        // Execute 'auto' command for all fans
        var allSuccess = true
        for i in 0..<monitor.numberOfFans {
             if !runSmcHelper(args: ["auto", "\(i)"]) {
                 allSuccess = false
             }
        }
        
        if allSuccess {
            stopWatchdog()
            isControlEnabled = false
            statusMessage = "Automatic mode restored"
            print("Fan Control: Automatic mode restored")
        } else {
            statusMessage = "Failed to restore auto mode"
            print("Fan Control: Failed to restore auto mode")
        }
    }
    
    private func applyFanSpeed(_ speed: Int) {
        guard let monitor = systemMonitor else {
            statusMessage = "No system monitor"
            lastWriteSuccess = false
            return
        }
        
        guard monitor.numberOfFans > 0 else {
            statusMessage = "No fans detected"
            lastWriteSuccess = false
            return
        }
        
        // Apply speed to all fans
        var allSuccess = true
        for i in 0..<monitor.numberOfFans {
            if !runSmcHelper(args: ["set", "\(i)", "\(speed)"]) {
                allSuccess = false
            }
        }
        
        if allSuccess {
            startWatchdogIfNeeded(fanCount: monitor.numberOfFans)
            if !lastWriteSuccess { lastWriteSuccess = true }
        } else {
            if lastWriteSuccess { lastWriteSuccess = false }
        }
    }
    
    /// Executes the smc-helper tool via sudo.
    /// Tries non-interactive (passwordless) sudo first.
    /// Falls back to AppleScript (prompt) if that fails.
    private func runSmcHelper(args: [String]) -> Bool {
        // 1. Try sudo -n (Non-interactive)
        // This relies on the sudoers file being set up correctly by install.sh
        let helperPath = smcHelperPath
        
        if !FileManager.default.fileExists(atPath: helperPath) {
            statusMessage = "Error: smc-helper not installed"
            print("Error: \(helperPath) not found")
            return false
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", helperPath] + args
        task.environment = ["LANG": "C"] // Prevent locale issues
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                return true
            }
        } catch {
            print("Fan Control: sudo -n execution error: \(error)")
        }
        
        // 2. Fallback: AppleScript (Prompts user for password)
        // This handles cases where install.sh wasn't run or sudoers is broken.
        print("Fan Control: sudo -n failed. Falling back to AppleScript.")
        
        // Construct the full shell command string for AppleScript
        // e.g. '/usr/local/bin/smc-helper' set 0 4000
        let argsString = args.joined(separator: " ")
        let fullCommand = "'\(helperPath)' \(argsString)"
        
        let scriptSource = "do shell script \"\(fullCommand)\" with administrator privileges"
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: scriptSource) {
            _ = scriptObject.executeAndReturnError(&error)
            if let error = error {
                let errorMsg = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
                print("Fan Control: AppleScript failed: \(errorMsg)")
                // Don't show confusing AppleScript errors to user in status, keep it simple
                return false
            }
            return true
        }
        
        return false
    }
    
    func startAutoControl() {
        stopAutoControl()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Run immediately
            self.updateAutoControl()
            
            // A slower control loop plus hysteresis avoids tiny, constant SMC writes.
            self.autoControlTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
                self?.updateAutoControl()
            }
            RunLoop.current.add(self.autoControlTimer!, forMode: .common)
        }
    }
    
    func stopAutoControl() {
        autoControlTimer?.invalidate()
        autoControlTimer = nil
    }
    
    private func updateAutoControl() {
        guard mode == .automatic, let monitor = systemMonitor else { return }
        
        let currentTemp = max(
            monitor.cpuTemperature ?? 0,
            monitor.gpuTemperature ?? 0
        )
        
        guard currentTemp > 0 else { return }
        
        if !isControlEnabled {
            enableManualMode()
        }
        
        let emergency = emergencyProtectionEnabled && currentTemp >= emergencyTemperature
        if emergency {
            applyMaximumSpeed()
            statusMessage = "Emergency: fans at 100%"
            return
        }
        let finalSpeed = FanControlPolicy.targetSpeed(
            temperature: currentTemp, threshold: autoThreshold, emergency: emergencyTemperature,
            minimum: minSpeed, maximum: autoMaxSpeed, response: autoAggressiveness
        )
        
        // Only apply if speed changed significantly (avoid unnecessary SMC calls)
        if abs(finalSpeed - lastAppliedSpeed) >= 150 || lastAppliedSpeed == 0 {
            applyFanSpeed(finalSpeed)
            lastAppliedSpeed = finalSpeed
            
            // Update status with debug info
            let newStatus = "Auto: \(finalSpeed) RPM"
            if statusMessage != newStatus {
                DispatchQueue.main.async { [weak self] in
                    self?.statusMessage = newStatus
                }
            }
        }
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        
        if let savedMode = defaults.string(forKey: "fanControlMode") {
            mode = ControlMode(rawValue: savedMode) ?? .manual
        }
        
        let savedManualSpeed = defaults.integer(forKey: "manualFanSpeed")
        if savedManualSpeed >= minSpeed && savedManualSpeed <= maxSpeed {
            manualSpeed = savedManualSpeed
        }
        
        let savedThreshold = defaults.double(forKey: "autoThreshold")
        if savedThreshold >= 40 && savedThreshold <= 90 {
            autoThreshold = savedThreshold
        }
        
        let savedMaxSpeed = defaults.integer(forKey: "autoMaxSpeed")
        if savedMaxSpeed >= minSpeed && savedMaxSpeed <= maxSpeed {
            autoMaxSpeed = savedMaxSpeed
        }
        
        let savedAggressiveness = defaults.double(forKey: "autoAggressiveness")
        if savedAggressiveness >= 0.0 && savedAggressiveness <= 3.0 {
            autoAggressiveness = savedAggressiveness
        }
        emergencyProtectionEnabled = defaults.object(forKey: "emergencyProtectionEnabled") as? Bool ?? true
        let savedEmergency = defaults.double(forKey: "emergencyTemperature")
        if savedEmergency >= 75 && savedEmergency <= 105 { emergencyTemperature = savedEmergency }

        if let savedPreset = defaults.string(forKey: "activePreset"),
           let preset = FanPreset(rawValue: savedPreset) {
            activePreset = preset
        } else {
            activePreset = inferredPreset()
        }
    }

    private func inferredPreset() -> FanPreset {
        if mode == .manual {
            return manualSpeed == maxSpeed ? .maximum : .custom
        }
        if autoThreshold == 65, autoMaxSpeed == 3600, autoAggressiveness == 0.75 { return .quiet }
        if autoThreshold == 60, autoMaxSpeed == 5000, autoAggressiveness == 1.5 { return .balanced }
        if autoThreshold == 50, autoMaxSpeed == maxSpeed, autoAggressiveness == 2.25 { return .performance }
        return .custom
    }
    
    // Explicitly return control to system (SMC auto behavior) without app interference
    func resetToSystemControl() {
        print("Fan Control: Resetting to system default...")
        stopAutoControl()
        restoreAutomaticControl()
    }
    
    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: "fanControlMode")
        defaults.set(manualSpeed, forKey: "manualFanSpeed")
        defaults.set(autoThreshold, forKey: "autoThreshold")
        defaults.set(autoMaxSpeed, forKey: "autoMaxSpeed")
        defaults.set(autoAggressiveness, forKey: "autoAggressiveness")
        defaults.set(activePreset.rawValue, forKey: "activePreset")
        defaults.set(emergencyProtectionEnabled, forKey: "emergencyProtectionEnabled")
        defaults.set(emergencyTemperature, forKey: "emergencyTemperature")
    }
    
    func setAutoThreshold(_ threshold: Double) {
        autoThreshold = max(40, min(90, threshold))
        activePreset = .custom
        saveSettings()
        // Force immediate update in auto mode
        if mode == .automatic {
            lastAppliedSpeed = 0  // Reset to force update
            updateAutoControl()
        }
    }
    
    func setAutoMaxSpeed(_ speed: Int) {
        autoMaxSpeed = max(minSpeed, min(maxSpeed, speed))
        activePreset = .custom
        saveSettings()
        // Force immediate update in auto mode
        if mode == .automatic {
            lastAppliedSpeed = 0  // Reset to force update
            updateAutoControl()
        }
    }
    
    func setAutoAggressiveness(_ value: Double) {
        autoAggressiveness = max(0.0, min(3.0, value))
        activePreset = .custom
        saveSettings()
        // Force immediate update in auto mode
        if mode == .automatic {
            lastAppliedSpeed = 0  // Reset to force update
            updateAutoControl()
        }
    }

    func applyPreset(_ preset: FanPreset) {
        activePreset = preset
        switch preset {
        case .system:
            resetToSystemControl()
        case .quiet:
            setMode(.automatic, preservePreset: true); autoThreshold = 65; autoMaxSpeed = 3600; autoAggressiveness = 0.75
        case .balanced:
            setMode(.automatic, preservePreset: true); autoThreshold = 60; autoMaxSpeed = 5000; autoAggressiveness = 1.5
        case .performance:
            setMode(.automatic, preservePreset: true); autoThreshold = 50; autoMaxSpeed = maxSpeed; autoAggressiveness = 2.25
        case .maximum:
            stopAutoControl(); mode = .manual; manualSpeed = maxSpeed; enableManualMode(); applyMaximumSpeed()
        case .custom:
            return
        }
        saveSettings()
        if mode == .automatic { lastAppliedSpeed = 0; updateAutoControl() }
    }

    func setFanSpeed(_ speed: Int, fanIndex: Int) {
        guard let monitor = systemMonitor, fanIndex >= 0, fanIndex < monitor.numberOfFans else { return }
        let value = max(minSpeed, min(maxSpeed, speed))
        if runSmcHelper(args: ["set", "\(fanIndex)", "\(value)"]) {
            lastAppliedSpeed = value
            activePreset = .custom
            saveSettings()
            startWatchdogIfNeeded(fanCount: monitor.numberOfFans)
        }
    }

    private func applyMaximumSpeed() {
        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else { return }
        var success = true
        let targets = FanControlPolicy.maximumTargets(fanCount: monitor.numberOfFans, maximum: maxSpeed)
        for (index, target) in targets.enumerated() {
            // Use the same explicit ceiling as the manual and Performance
            // controls. Some Macs report lower F{n}Mx values even though the
            // accepted target and observed maximum are 6500 RPM.
            if !runSmcHelper(args: ["set", "\(index)", "\(target)"]) { success = false }
        }
        if success { lastAppliedSpeed = maxSpeed }
        lastWriteSuccess = success
        if success { startWatchdogIfNeeded(fanCount: monitor.numberOfFans) }
    }

    func startBoost(minutes: Int = 10) {
        if boostRestore == nil { boostRestore = (mode, manualSpeed, activePreset) }
        boostEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        applyPreset(.maximum)
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(minutes * 60)) { [weak self] in
            guard let self, let end = self.boostEndDate, end <= Date() else { return }
            self.stopBoost()
        }
    }

    func stopBoost() {
        boostEndDate = nil
        guard let restore = boostRestore else { return }
        boostRestore = nil
        if restore.0 == .automatic { applyPreset(restore.2) }
        else { setMode(.manual); setManualSpeed(restore.1) }
    }

    func setEmergencyProtection(enabled: Bool, temperature: Double) {
        emergencyProtectionEnabled = enabled
        emergencyTemperature = max(75, min(105, temperature))
        saveSettings()
    }

    private func startWatchdogIfNeeded(fanCount: Int) {
        guard watchdogProcess == nil, fanCount > 0 else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let watchdog = Bundle.main.url(forResource: "fan-watchdog", withExtension: nil) else { return }
        let process = Process()
        process.executableURL = watchdog
        process.arguments = ["\(pid)", "\(fanCount)", smcHelperPath]
        try? process.run()
        watchdogProcess = process
    }

    private func stopWatchdog() {
        watchdogProcess?.terminate()
        watchdogProcess = nil
    }
}
