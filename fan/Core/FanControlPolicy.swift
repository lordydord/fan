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
        let ratio = max(0, min(1, (temperature - threshold) / (ceiling - threshold)))
        let temperatureSpeed = Double(minimum) + Double(maximum - minimum) * ratio
        let midpoint = 1.5
        let target: Double
        if response <= midpoint {
            target = Double(minimum) * (1 - response / midpoint) + temperatureSpeed * (response / midpoint)
        } else {
            let blend = (response - midpoint) / midpoint
            target = temperatureSpeed * (1 - blend) + Double(maximum) * blend
        }
        return Int(max(Double(minimum), min(Double(maximum), target)))
    }
}
