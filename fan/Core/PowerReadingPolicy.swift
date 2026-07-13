import Foundation

public enum PowerReadingPolicy {
    /// Returns the best available estimate of the Mac's current power use.
    /// AppleSmartBattery telemetry values are expressed in milliwatts.
    public static func watts(
        systemLoadMilliwatts: Double?,
        systemPowerInMilliwatts: Double?,
        batteryPowerMilliwatts: Double?,
        voltageVolts: Double?,
        amperageMilliamps: Double?
    ) -> Double? {
        for reading in [systemLoadMilliwatts, systemPowerInMilliwatts, batteryPowerMilliwatts] {
            if let reading, reading.isFinite, reading > 0, reading < 1_000_000 {
                return reading / 1_000
            }
        }

        guard let voltageVolts,
              let amperageMilliamps,
              voltageVolts.isFinite,
              amperageMilliamps.isFinite else {
            return nil
        }

        let watts = abs(voltageVolts * amperageMilliamps / 1_000)
        return watts > 0 ? watts : nil
    }
}
