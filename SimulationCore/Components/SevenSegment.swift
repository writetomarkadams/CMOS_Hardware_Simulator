enum SevenSegmentDriverKind: String, CaseIterable, Codable {
    case cd4511 = "CD4511"
    case cd4543 = "CD4543"

    // Physical pin numbers in BCD weight order and segment a–g order.
    var inputs: [Int] { self == .cd4511 ? [7, 1, 2, 6] : [5, 3, 2, 4] }
    var outputs: [Int] { self == .cd4511 ? [13, 12, 11, 10, 9, 15, 14] : [9, 10, 11, 12, 13, 15, 14] }
}

final class SevenSegmentDriver: LogicComponent {
    let kind: SevenSegmentDriverKind
    let pins: [Int: Pin]
    private var latchedCode: Int?

    private static let digits = ["abcdef", "bc", "abdeg", "abcdg", "bcfg",
                                 "acdfg", "acdefg", "abc", "abcdefg", "abcdfg"]

    init(_ kind: SevenSegmentDriverKind) {
        self.kind = kind
        var pins = [
            8: Pin(number: 8, name: "VSS", direction: .power),
            16: Pin(number: 16, name: "VDD", direction: .power)
        ]
        for (number, name) in zip(kind.inputs, ["A", "B", "C", "D"]) {
            pins[number] = Pin(number: number, name: name, direction: .input)
        }
        for (number, name) in zip(kind.outputs, "abcdefg") {
            pins[number] = Pin(number: number, name: String(name), direction: .output)
        }
        let controls = kind == .cd4511 ? [3: "LT (active low)", 4: "BI (active low)", 5: "LE"]
                                      : [1: "LD", 6: "PH", 7: "BI"]
        for (number, name) in controls {
            pins[number] = Pin(number: number, name: name, direction: .input)
        }
        self.pins = pins
    }

    func evaluate() {
        let is4511 = kind == .cd4511
        let latch = pins[is4511 ? 5 : 1]!.state
        if latch == (is4511 ? .low : .high) {
            latchedCode = inputCode()
        } else if latch != (is4511 ? .high : .low) {
            latchedCode = nil
        }

        let segments: String?
        let phase: LogicState
        if is4511 {
            phase = .low
            let test = pins[3]!.state
            let blank = pins[4]!.state
            switch (test, blank) {
            case (.low, _): segments = "abcdefg"
            case (.high, .low): segments = ""
            case (.high, .high): segments = decodedSegments()
            default: segments = nil
            }
        } else {
            phase = pins[6]!.state
            switch pins[7]!.state {
            case .high: segments = ""
            case .low: segments = decodedSegments()
            case .undefined, .highImpedance: segments = nil
            }
        }
        for (number, name) in zip(kind.outputs, "abcdefg") {
            let output: LogicState
            if let segments, phase == .low || phase == .high {
                output = segments.contains(name) != (phase == .high) ? .high : .low
            } else {
                output = .undefined
            }
            pins[number]!.drive(output)
        }
    }

    private func inputCode() -> Int? {
        var code = 0
        for (bit, number) in kind.inputs.enumerated() {
            switch pins[number]!.state {
            case .high: code |= 1 << bit
            case .low: break
            case .undefined, .highImpedance: return nil
            }
        }
        return code
    }

    private func decodedSegments() -> String? {
        guard let code = latchedCode else { return nil }
        guard code < Self.digits.count else { return "" }
        if kind == .cd4511 && code == 6 { return "cdefg" }
        if kind == .cd4511 && code == 9 { return "abcfg" }
        return Self.digits[code]
    }
}

class SevenSegmentDisplay: LogicComponent {
    let pins: [Int: Pin]
    let segmentNumbers: [Int]
    let commonNumbers: [Int]
    let commonAnode: Bool

    init(segments: [Int], commons: [Int], commonAnode: Bool) {
        self.segmentNumbers = segments
        self.commonNumbers = commons
        self.commonAnode = commonAnode
        var pins = Dictionary(uniqueKeysWithValues: zip(segments, ["A", "B", "C", "D", "E", "F", "G", "DP"]).map {
            ($0, Pin(number: $0, name: $1, direction: .input))
        })
        for number in commons {
            pins[number] = Pin(number: number, name: commonAnode ? "CA" : "CC", direction: .input)
        }
        self.pins = pins
    }

    func evaluate() {}

    func isLit(_ number: Int, reading: (Int) -> LogicState) -> Bool {
        guard reading(number) == (commonAnode ? .low : .high) else { return false }
        let commonLevel: LogicState = commonAnode ? .high : .low
        let commons = commonNumbers.map(reading)
        return commons.contains(commonLevel) && commons.allSatisfy { $0 == commonLevel || $0 == .highImpedance }
    }
}

final class MAN74A: SevenSegmentDisplay {
    static let segmentPins = [14, 13, 8, 7, 6, 1, 2, 9]
    static let commonPins = [4, 12]

    init() {
        super.init(segments: Self.segmentPins, commons: Self.commonPins, commonAnode: false)
    }
}

final class MAN72A: SevenSegmentDisplay {
    static let segmentPins = [1, 13, 10, 8, 7, 2, 11, 6]
    static let commonPins = [3, 14]

    init() {
        super.init(segments: Self.segmentPins, commons: Self.commonPins, commonAnode: true)
    }
}
