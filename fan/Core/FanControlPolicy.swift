import Foundation

public enum FanControlPolicy {
    private struct ResponseCurve {
        let response: Double
        let fullSpeedOffset: Double
        let exponent: Double
    }

    // The response slider is continuous, so interpolate between these anchors
    // instead of switching abruptly when the visible label changes.
    private static let responseCurves = [
        ResponseCurve(response: 0.0, fullSpeedOffset: 40.0, exponent: 1.40),
        ResponseCurve(response: 0.5, fullSpeedOffset: 35.0, exponent: 1.20),
        ResponseCurve(response: 1.0, fullSpeedOffset: 30.0, exponent: 1.00),
        ResponseCurve(response: 1.5, fullSpeedOffset: 25.0, exponent: 0.75),
        ResponseCurve(response: 2.0, fullSpeedOffset: 22.5, exponent: 0.50),
        ResponseCurve(response: 3.0, fullSpeedOffset: 20.0, exponent: 0.25)
    ]

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
        guard temperature > threshold else { return minimum }

        let clampedResponse = max(0, min(3, response))
        let curve = interpolatedCurve(for: clampedResponse)
        let naturalFullSpeedTemperature = threshold + curve.fullSpeedOffset
        let fullSpeedTemperature = emergency > threshold
            ? min(naturalFullSpeedTemperature, emergency)
            : naturalFullSpeedTemperature

        guard temperature < fullSpeedTemperature else { return maximum }

        let temperatureRatio = max(
            0,
            min(1, (temperature - threshold) / (fullSpeedTemperature - threshold))
        )
        let responseRatio = pow(temperatureRatio, curve.exponent)

        let target = Double(minimum) + Double(maximum - minimum) * responseRatio
        return Int(max(Double(minimum), min(Double(maximum), target)))
    }

    private static func interpolatedCurve(for response: Double) -> ResponseCurve {
        guard let first = responseCurves.first, let last = responseCurves.last else {
            return ResponseCurve(response: response, fullSpeedOffset: 25, exponent: 0.75)
        }
        if response <= first.response { return first }

        for index in 1..<responseCurves.count {
            let lower = responseCurves[index - 1]
            let upper = responseCurves[index]
            guard response <= upper.response else { continue }

            let progress = (response - lower.response) / (upper.response - lower.response)
            return ResponseCurve(
                response: response,
                fullSpeedOffset: lower.fullSpeedOffset
                    + (upper.fullSpeedOffset - lower.fullSpeedOffset) * progress,
                exponent: lower.exponent + (upper.exponent - lower.exponent) * progress
            )
        }

        return last
    }
}
