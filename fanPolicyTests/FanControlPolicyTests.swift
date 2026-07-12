import Testing
@testable import FanCore

@Test func belowThresholdUsesMinimum() {
    #expect(FanControlPolicy.targetSpeed(temperature: 50, threshold: 60, emergency: 90,
                                        minimum: 1000, maximum: 6000, response: 1.5) == 1000)
}

@Test func maximumResponseUsesMaximum() {
    #expect(FanControlPolicy.targetSpeed(temperature: 50, threshold: 60, emergency: 90,
                                        minimum: 1000, maximum: 6000, response: 3) == 6000)
}

@Test func adaptivePollingAcceleratesWhenHot() {
    #expect(FanControlPolicy.adaptiveInterval(temperature: 45, preferred: 5) == 12)
    #expect(FanControlPolicy.adaptiveInterval(temperature: 65, preferred: 5) == 5)
    #expect(FanControlPolicy.adaptiveInterval(temperature: 80, preferred: 5) == 2)
}
