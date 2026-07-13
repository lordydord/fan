import Testing
@testable import FanCore

@Test func belowThresholdUsesMinimum() {
    #expect(FanControlPolicy.targetSpeed(temperature: 50, threshold: 60, emergency: 90,
                                        minimum: 1000, maximum: 6000, response: 1.5) == 1000)
}

@Test func maximumResponseReturnsToMinimumBelowTarget() {
    #expect(FanControlPolicy.targetSpeed(temperature: 37, threshold: 55, emergency: 90,
                                        minimum: 1000, maximum: 6500, response: 3) == 1000)
    #expect(FanControlPolicy.targetSpeed(temperature: 55, threshold: 55, emergency: 90,
                                        minimum: 1000, maximum: 6500, response: 3) == 1000)
}

@Test func strongerResponseRampsHarderOnlyAboveTarget() {
    let gentle = FanControlPolicy.targetSpeed(temperature: 60, threshold: 55, emergency: 90,
                                              minimum: 1000, maximum: 6500, response: 0.75)
    let balanced = FanControlPolicy.targetSpeed(temperature: 60, threshold: 55, emergency: 90,
                                                minimum: 1000, maximum: 6500, response: 1.5)
    let maximum = FanControlPolicy.targetSpeed(temperature: 60, threshold: 55, emergency: 90,
                                               minimum: 1000, maximum: 6500, response: 3)

    #expect(gentle < balanced)
    #expect(balanced < maximum)
    #expect(maximum < 6500)
}

@Test func maximumPresetTargetsEveryFanAtConfiguredCeiling() {
    #expect(FanControlPolicy.maximumTargets(fanCount: 2, maximum: 6500) == [6500, 6500])
    #expect(FanControlPolicy.maximumTargets(fanCount: 1, maximum: 6500) == [6500])
    #expect(FanControlPolicy.maximumTargets(fanCount: 0, maximum: 6500).isEmpty)
}

@Test func adaptivePollingAcceleratesWhenHot() {
    #expect(FanControlPolicy.adaptiveInterval(temperature: 45, preferred: 5) == 12)
    #expect(FanControlPolicy.adaptiveInterval(temperature: 65, preferred: 5) == 5)
    #expect(FanControlPolicy.adaptiveInterval(temperature: 80, preferred: 5) == 2)
}

@Test func systemLoadPowerWorksWhenChargedBatteryCurrentIsZero() {
    #expect(PowerReadingPolicy.watts(
        systemLoadMilliwatts: 21_502,
        systemPowerInMilliwatts: 21_502,
        batteryPowerMilliwatts: 0,
        voltageVolts: 12.562,
        amperageMilliamps: 0
    ) == 21.502)
}

@Test func batteryCurrentRemainsAPowerFallback() {
    #expect(PowerReadingPolicy.watts(
        systemLoadMilliwatts: nil,
        systemPowerInMilliwatts: nil,
        batteryPowerMilliwatts: nil,
        voltageVolts: 12.5,
        amperageMilliamps: -1_600
    ) == 20)
}
