//
//  SystemMonitor.swift
//  fan
//
//  Reads temperatures and fan speeds from the SMC on a background queue.
//
//  Kept cheap on purpose: the working sensor keys are found once and remembered, keys this
//  Mac doesn't have are never asked for again, the fans' fixed min/max speeds are read once,
//  values are only published when they change, and the read timer has tolerance so macOS
//  can batch its wake-ups with other work.
//

import Foundation
import Combine
import IOKit

// MARK: - SMC types (layout must match the kernel's SMCParamStruct)

private typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

private struct SMCKeyData_vers_t {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCKeyData_pLimitData_t {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyData_keyInfo_t {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCKeyData_vers_t()
    var pLimitData = SMCKeyData_pLimitData_t()
    var keyInfo = SMCKeyData_keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private let KERNEL_INDEX_SMC: UInt32 = 2
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let SMC_CMD_READ_KEYINFO: UInt8 = 9

private func fourCC(_ s: String) -> UInt32 {
    var r: UInt32 = 0
    for (i, c) in s.utf8.prefix(4).enumerated() { r |= UInt32(c) << (8 * (3 - i)) }
    return r
}

// MARK: - SMC reader (used only from SystemMonitor's queue)

private final class SMCReader: @unchecked Sendable {
    private var connection: io_connect_t = 0
    private var keyInfo: [UInt32: SMCKeyData_keyInfo_t] = [:]
    private var missing: Set<UInt32> = []
    private let lock = NSLock()
    private(set) var lastError: String?

    private static let flt = fourCC("flt ")
    private static let sp78 = fourCC("sp78")
    private static let fpe2 = fourCC("fpe2")
    private static let ui8 = fourCC("ui8 ")
    private static let ui16 = fourCC("ui16")
    private static let ui32 = fourCC("ui32")
    private static let si16 = fourCC("si16")

    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return connection != 0 }

    func open() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if connection != 0 { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { lastError = "AppleSMC service not found"; return false }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        if result == kIOReturnSuccess { lastError = nil; return true }
        connection = 0
        lastError = "Couldn’t open the SMC (error \(result))"
        return false
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        if connection != 0 { IOServiceClose(connection); connection = 0 }
    }

    private func call(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var size = MemoryLayout<SMCParamStruct>.size
        let r = IOConnectCallStructMethod(connection, KERNEL_INDEX_SMC, &input,
                                          MemoryLayout<SMCParamStruct>.size, &output, &size)
        return r == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    /// Reads one key. Keys this Mac doesn't have are remembered and skipped from then on.
    func read(_ key: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        guard connection != 0 else { return nil }
        let code = fourCC(key)
        if missing.contains(code) { return nil }

        let info: SMCKeyData_keyInfo_t
        if let cached = keyInfo[code] {
            info = cached
        } else {
            var input = SMCParamStruct()
            input.key = code
            input.data8 = SMC_CMD_READ_KEYINFO
            guard let out = call(&input), out.keyInfo.dataSize > 0, out.keyInfo.dataSize <= 32 else {
                missing.insert(code)
                return nil
            }
            info = out.keyInfo
            keyInfo[code] = info
        }

        var input = SMCParamStruct()
        input.key = code
        input.keyInfo = info
        input.data8 = SMC_CMD_READ_BYTES
        guard let out = call(&input) else { return nil }
        return Self.parse(out.bytes, type: info.dataType, size: info.dataSize)
    }

    /// The first key in `keys` that gives a believable temperature.
    func firstTemperatureKey(_ keys: [String]) -> String? {
        keys.first { key in read(key).map { $0 > 0 && $0 < 150 } ?? false }
    }

    func temperature(_ key: String) -> Double? {
        guard let t = read(key), t > 0, t < 150 else { return nil }
        return t
    }

    private static func parse(_ bytes: SMCBytes, type: UInt32, size: UInt32) -> Double? {
        withUnsafeBytes(of: bytes) { raw -> Double? in
            let b0 = raw[0], b1 = raw[1]
            switch (type, size) {
            case (flt, 4):
                return Double(raw.loadUnaligned(as: Float32.self))
            case (sp78, 2):
                return Double(Int16(bitPattern: UInt16(b0) << 8 | UInt16(b1))) / 256
            case (fpe2, 2):
                return Double((Int(b0) << 6) + (Int(b1) >> 2))
            case (ui8, 1):
                return Double(b0)
            case (ui16, 2):
                return Double(UInt16(b0) << 8 | UInt16(b1))
            case (ui32, 4):
                return Double(UInt32(b0) << 24 | UInt32(b1) << 16 | UInt32(raw[2]) << 8 | UInt32(raw[3]))
            case (si16, 2):
                return Double(Int16(bitPattern: UInt16(b0) << 8 | UInt16(b1)))
            case (_, 2):
                return Double(UInt16(b0) << 8 | UInt16(b1))
            default:
                return nil
            }
        }
    }
}

// MARK: - System monitor

final class SystemMonitor: ObservableObject {
    @Published var cpuTemperature: Double?
    @Published var gpuTemperature: Double?
    @Published var fanSpeeds: [Int] = []
    @Published var fanMinSpeeds: [Int] = []
    @Published var fanMaxSpeeds: [Int] = []
    @Published var numberOfFans: Int = 0
    @Published var isMonitoring = false
    @Published var hasAccess = false
    @Published var lastError: String?

    private let smc = SMCReader()
    private let queue = DispatchQueue(label: "com.soloteamdev.ffan.smc", qos: .utility)
    private var timer: Timer?
    private var interval: TimeInterval = 5
    private var readInFlight = false
    /// Sensor keys found to work on this Mac; nil until the first read.
    private var sensorKeys: (cpu: String?, gpu: String?)?

    // Intel keys first, then Apple silicon keys.
    private static let cpuKeys = ["TC0P", "TCXC", "TC0E", "TC0F", "TC0D", "TC1C", "TC2C", "TC3C", "TC4C",
                                  "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0b"]
    private static let gpuKeys = ["TGDD", "TG0P", "TG0D", "TG0E", "TG0F"]

    init() {
        hasAccess = smc.open()
        lastError = smc.lastError
    }

    deinit {
        timer?.invalidate()
        smc.close()
    }

    func checkAccess() -> Bool {
        if !hasAccess { hasAccess = smc.open(); lastError = smc.lastError }
        return hasAccess
    }

    // MARK: Control

    func startMonitoring() {
        guard checkAccess() else { return }
        timer?.invalidate()
        timer = nil
        isMonitoring = true
        if numberOfFans == 0 { detectFans() } else { read() }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    func setMonitoringInterval(_ value: TimeInterval) {
        let v = max(2, min(30, value))
        guard v != interval else { return }
        interval = v
        if isMonitoring, !readInFlight { scheduleNext() }
    }

    // MARK: Reading

    private func detectFans() {
        let smc = self.smc
        queue.async { [weak self] in
            var count = 0
            while count < 8, smc.read("F\(count)Ac") != nil { count += 1 }
            // Min and max are fixed for the hardware, so read them once here.
            let mins = (0..<count).map { Int(smc.read("F\($0)Mn") ?? 1000) }
            let maxs = (0..<count).map { Int(smc.read("F\($0)Mx") ?? 6500) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.fanMinSpeeds = mins
                self.fanMaxSpeeds = maxs
                self.numberOfFans = count
                self.read()
            }
        }
    }

    private func read() {
        guard isMonitoring, !readInFlight else { return }
        readInFlight = true
        let smc = self.smc
        let fans = numberOfFans
        let known = sensorKeys

        queue.async { [weak self] in
            var keys = known ?? (smc.firstTemperatureKey(Self.cpuKeys), smc.firstTemperatureKey(Self.gpuKeys))
            var cpu = keys.cpu.flatMap(smc.temperature)
            var gpu = keys.gpu.flatMap(smc.temperature)
            // A remembered key that stops answering gets looked up again.
            if keys.cpu != nil, cpu == nil {
                keys.cpu = smc.firstTemperatureKey(Self.cpuKeys)
                cpu = keys.cpu.flatMap(smc.temperature)
            }
            if keys.gpu != nil, gpu == nil {
                keys.gpu = smc.firstTemperatureKey(Self.gpuKeys)
                gpu = keys.gpu.flatMap(smc.temperature)
            }
            let speeds = (0..<fans).compactMap { smc.read("F\($0)Ac").map { Int($0) } }
            let resolved = keys

            DispatchQueue.main.async {
                guard let self else { return }
                self.readInFlight = false
                self.sensorKeys = resolved
                // Round to 0.1° so sensor noise doesn't redraw anything.
                let c = cpu.map { ($0 * 10).rounded() / 10 }
                let g = gpu.map { ($0 * 10).rounded() / 10 }
                if self.cpuTemperature != c { self.cpuTemperature = c }
                if self.gpuTemperature != g { self.gpuTemperature = g }
                if self.fanSpeeds != speeds { self.fanSpeeds = speeds }
                self.scheduleNext()
            }
        }
    }

    private func scheduleNext() {
        guard isMonitoring else { return }
        timer?.invalidate()
        let hottest = max(cpuTemperature ?? 0, gpuTemperature ?? 0)
        let wait = FanControlPolicy.adaptiveInterval(temperature: hottest, preferred: interval)
        let t = Timer(timeInterval: wait, repeats: false) { [weak self] _ in self?.read() }
        t.tolerance = wait * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
