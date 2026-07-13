import Foundation

public enum FanControlPolicy {
    public static func maximumTargets(fanCount: Int, maximum: Int) -> [Int] {
        guard fanCount > 0 else { return [] }
        return Array(repeating: maximum, count: fanCount)
    }

    public static func adaptiveInterval(temperature: Double, preferred: Double) -> Double {
        if temperature >= 75 { return 2 }
        if temperature >= 60 { return max(5, preferred) }
        return max(12, preferred)
    }

    public static func targetSpeed(temperature: Double, threshold: Double, emergency: Double,
                                   minimum: Int, maximum: Int, response: Double) -> Int {
        let ceiling = max(threshold + 10, emergency)
        let temperatureRatio = max(0, min(1, (temperature - threshold) / (ceiling - threshold)))
        let clampedResponse = max(0, min(3, response))
        let midpoint = 1.5

        let responseRatio: Double
        if clampedResponse <= midpoint {
            // Gentle responses follow the same temperature curve at reduced strength.
            responseRatio = temperatureRatio * (clampedResponse / midpoint)
        } else {
            // Strong responses rise earlier above the threshold, but never create a
            // minimum fan-speed floor. At or below the threshold this remains zero.
            let boost = (clampedResponse - midpoint) / midpoint
            let exponent = 1 / (1 + 3 * boost)
            responseRatio = pow(temperatureRatio, exponent)
        }

        let target = Double(minimum) + Double(maximum - minimum) * responseRatio
        return Int(max(Double(minimum), min(Double(maximum), target)))
    }
}
