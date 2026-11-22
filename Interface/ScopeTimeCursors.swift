import Foundation

struct ScopeTimeAxis {
    let window: ClosedRange<Double>
    let plotWidth: CGFloat

    static let left: CGFloat = 44

    init(window: ClosedRange<Double>, width: CGFloat) {
        self.window = window
        plotWidth = max(1, width - Self.left - 8)
    }

    func x(at fraction: Double) -> CGFloat {
        Self.left + plotWidth * fraction
    }

    func x(for time: Double) -> CGFloat {
        x(at: (time - window.lowerBound) / duration)
    }

    func fraction(at x: CGFloat) -> Double {
        min(1, max(0, Double((x - Self.left) / plotWidth)))
    }

    func time(at fraction: Double) -> Double {
        switch fraction {
        case 0: window.lowerBound
        case 1: window.upperBound
        default: window.lowerBound + duration * fraction
        }
    }

    private var duration: Double { window.upperBound - window.lowerBound }
}

struct ScopeTimeCursors {
    var isVisible = false
    var a = 0.25
    var b = 0.75

    struct Measurement {
        let a: Double
        let b: Double
        var interval: Double { abs(b - a) }

        var reciprocal: Double? {
            guard interval > 0 else { return nil }
            let frequency = 1 / interval
            return frequency.isFinite ? frequency : nil
        }
    }

    func measurement(on axis: ScopeTimeAxis) -> Measurement {
        Measurement(a: axis.time(at: a), b: axis.time(at: b))
    }

    static func formatTime(_ seconds: Double) -> String {
        switch abs(seconds) {
        case 0: return "0 s"
        case 1...: return number(seconds) + " s"
        case 0.001...: return number(seconds * 1_000) + " ms"
        default: return number(seconds * 1_000_000) + " µs"
        }
    }

    static func formatFrequency(_ hertz: Double) -> String {
        hertz >= 1_000 ? number(hertz / 1_000) + " kHz" : number(hertz) + " Hz"
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...9)))
    }
}
