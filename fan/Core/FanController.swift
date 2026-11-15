//
//  FanController.swift
//  fan
//
//  Drives the fans from FanSettings. The saved settings are only ever read here.
//  Everything temporary (Boost, emergency cooling, "Smart while hot", sleep) is held in
//  memory, so it ends on its own and can't leave the user's choice changed afterwards.
//
//  Fan writes go through the smc-helper via sudo, which means starting processes. They run
//  on a serial background queue so the menu and popover never wait on them.
//

import Foundation
import Combine

/// A temporary state that is currently overriding the saved mode.
enum ControlOverride: Equatable {
    case none
    case boost
    case emergency
    case hot        // "Switch to Smart while hot"
}

final class FanController: ObservableObject {
    @Published private(set) var activeOverride: ControlOverride = .none
    @Published private(set) var boostEndDate: Date?
    /// The speed the app last asked for. 0 while macOS is in control.
    @Published private(set) var targetSpeed: Int = 0
    @Published private(set) var lastWriteSuccess = false
    @Published private(set) var statusMessage = ""

    let settings: FanSettings
    private weak var systemMonitor: SystemMonitor?
    private var bag = Set<AnyCancellable>()
    private var watchdogProcess: Process?
    private var boostTimer: Timer?
    private var wakeWork: DispatchWorkItem?
    private let helperQueue = DispatchQueue(label: "com.soloteamdev.ffan.helper", qos: .userInitiated)

    /// True once the app has asked for a speed since macOS last had control.
    private var controlling = false
    /// Re-send the current target even if it hasn't changed (after wake).
    private var needsResync = true
    private var suspended = false
    private var hotLatched = false
    private var tickQueued = false

    var minSpeed: Int { FanSettings.minRPM }
    var maxSpeed: Int { FanSettings.maxRPM }

    nonisolated private static let helperPath = "/usr/local/bin/smc-helper"

    init(systemMonitor: SystemMonitor, settings: FanSettings) {
        self.systemMonitor = systemMonitor
        self.settings = settings

        // Any settings change, new reading or fan detection re-evaluates what the fans should do.
        settings.objectWillChange
            .sink { [weak self] _ in self?.scheduleTick() }
            .store(in: &bag)
        systemMonitor.$cpuTemperature
            .combineLatest(systemMonitor.$gpuTemperature, systemMonitor.$numberOfFans)
            .sink { [weak self] _ in self?.scheduleTick() }
            .store(in: &bag)
    }

    deinit {
        boostTimer?.invalidate()
        watchdogProcess?.terminate()
    }

    // MARK: - Public actions

    func choose(_ preset: FanPreset) {
        if boostEndDate != nil { stopBoost() }
        settings.choose(preset)
    }

    func setMode(_ mode: ControlMode) {
        if boostEndDate != nil { stopBoost() }
        settings.mode = mode
    }

    func startBoost(minutes: Int = 10) {
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        boostEndDate = end
        boostTimer?.invalidate()
        // Timers fire against the wall clock, so a boost that ends during sleep is over on wake.
        let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in self?.stopBoost() }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        boostTimer = t
        scheduleTick()
    }

    func stopBoost() {
        boostTimer?.invalidate()
        boostTimer = nil
        boostEndDate = nil
        scheduleTick()
    }

    /// Before quitting: hand every fan back to macOS and wait until it's done.
    func releaseControl() {
        boostTimer?.invalidate()
        boostTimer = nil
        boostEndDate = nil
        restoreSystemControl(wait: true)
        stopWatchdog()
    }

    // MARK: - Sleep and wake

    func systemWillSleep() {
        wakeWork?.cancel()
        // Sleep, display sleep and power-off often arrive together; hand control back once.
        guard !suspended else { return }
        suspended = true
        // Wait, so macOS has the fans before the Mac actually sleeps.
        restoreSystemControl(wait: true)
    }

    func systemDidWake() {
        // Several wake notifications arrive together; act once, after things settle.
        wakeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.suspended = false
            self.needsResync = true
            self.tick()
        }
        wakeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    // MARK: - Control loop

    func scheduleTick() {
        guard !tickQueued else { return }
        tickQueued = true
        // Run after the current change has landed (objectWillChange fires before it does).
        DispatchQueue.main.async { [weak self] in
            self?.tickQueued = false
            self?.tick()
        }
    }

    private var hottest: Double {
        max(systemMonitor?.cpuTemperature ?? 0, systemMonitor?.gpuTemperature ?? 0)
    }

    private func smartTarget(_ temp: Double) -> Int {
        FanControlPolicy.targetSpeed(
            temperature: temp,
            threshold: settings.autoThreshold,
            emergency: settings.emergencyTemperature,
            minimum: minSpeed,
            maximum: settings.autoMaxSpeed,
            response: settings.autoAggressiveness
        )
    }

    private func tick() {
        guard !suspended, let monitor = systemMonitor, monitor.numberOfFans > 0 else { return }

        if let end = boostEndDate, end <= Date() {
            boostTimer?.invalidate(); boostTimer = nil; boostEndDate = nil
        }

        let temp = hottest
        let mode = settings.mode

        // "Smart while hot" latches on at the alert temperature and off 5° below it.
        if settings.autoSwitchWhenHot, mode == .system || mode == .manual, temp > 0 {
            if temp >= settings.highTempAlert { hotLatched = true }
            else if temp < settings.highTempAlert - 5 { hotLatched = false }
        } else {
            hotLatched = false
        }

        let emergency = settings.emergencyEnabled && temp >= settings.emergencyTemperature
            && (mode != .system || hotLatched)

        var desired: Int?          // nil = macOS in control
        var smooth = false         // Smart curve: skip tiny changes
        var newOverride = ControlOverride.none

        if boostEndDate != nil {
            desired = maxSpeed; newOverride = .boost
        } else if emergency {
            desired = maxSpeed; newOverride = .emergency
        } else if hotLatched {
            desired = smartTarget(temp); smooth = true; newOverride = .hot
        } else {
            switch mode {
            case .system:
                desired = nil
            case .maximum:
                desired = maxSpeed
            case .manual:
                desired = settings.manualSpeed
            case .automatic:
                guard temp > 0 else { return }   // wait for the first reading
                desired = smartTarget(temp); smooth = true
            }
        }

        if activeOverride != newOverride { activeOverride = newOverride }

        if let speed = desired {
            let changed = speed != targetSpeed && (!smooth || abs(speed - targetSpeed) >= 150)
            if !controlling || needsResync || changed {
                write(speed, fans: monitor.numberOfFans)
            }
        } else if controlling || needsResync {
            restoreSystemControl(wait: false)
        }
        needsResync = false
    }

    // MARK: - SMC via the helper

    private func write(_ speed: Int, fans: Int) {
        // Record the request now so the next tick doesn't send it again while it's in flight.
        controlling = true
        targetSpeed = speed
        statusMessage = "Holding \(speed) RPM"
        helperQueue.async { [weak self] in
            let ok = (0..<fans).map { Self.runHelper(["set", "\($0)", "\(speed)"]) }.allSatisfy { $0 }
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastWriteSuccess = ok
                if ok { self.startWatchdogIfNeeded(fanCount: fans) }
                else { self.statusMessage = "Couldn’t set fan speed" }
            }
        }
    }

    private func restoreSystemControl(wait: Bool) {
        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else { return }
        // Nothing to undo if we never took control and macOS already has it.
        if !controlling && !needsResync && watchdogProcess == nil { return }
        let fans = monitor.numberOfFans
        controlling = false
        targetSpeed = 0
        statusMessage = "macOS in control"

        let job = { () -> Bool in (0..<fans).map { Self.runHelper(["auto", "\($0)"]) }.allSatisfy { $0 } }
        let finish = { [weak self] (ok: Bool) in
            guard let self else { return }
            if ok { self.stopWatchdog() } else { self.statusMessage = "Couldn’t hand control back to macOS" }
        }
        if wait {
            finish(helperQueue.sync(execute: job))
        } else {
            helperQueue.async { let ok = job(); DispatchQueue.main.async { finish(ok) } }
        }
    }

    /// Runs the helper through passwordless sudo, falling back to an admin prompt.
    /// Safe to call from any thread.
    nonisolated private static func runHelper(_ args: [String]) -> Bool {
        guard FileManager.default.fileExists(atPath: helperPath) else { return false }
        if run("/usr/bin/sudo", ["-n", helperPath] + args) { return true }
        let command = "'\(helperPath)' \(args.joined(separator: " "))"
        return run("/usr/bin/osascript", ["-e", "do shell script \"\(command)\" with administrator privileges"])
    }

    nonisolated private static func run(_ path: String, _ args: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        task.environment = ["LANG": "C"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        // Wait on a semaphore rather than waitUntilExit(), which spins the run loop. On the main
        // thread that let a second sleep notification re-enter helperQueue.sync and crash the app.
        let done = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in done.signal() }
        do {
            try task.run()
        } catch {
            return false
        }
        done.wait()
        return task.terminationStatus == 0
    }

    private func startWatchdogIfNeeded(fanCount: Int) {
        guard watchdogProcess == nil, fanCount > 0,
              let watchdog = Bundle.main.url(forResource: "fan-watchdog", withExtension: nil) else { return }
        let process = Process()
        process.executableURL = watchdog
        process.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "\(fanCount)", Self.helperPath]
        try? process.run()
        watchdogProcess = process
    }

    private func stopWatchdog() {
        watchdogProcess?.terminate()
        watchdogProcess = nil
    }
}
