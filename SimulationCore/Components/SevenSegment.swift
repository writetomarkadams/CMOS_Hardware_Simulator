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
    // A fresh or unpowered latch can contain any four-bit word.
    private static let allCodes = Set(0...15)
    private var latchedCodes = allCodes

    private static let allSegments: UInt8 = 0b1111111

    // TI SCHS072B and SCHS086D, bit order g...a. The CD4511B omits
    // segment a for 6 and segment d for 9.
    private static let cd4511Digits: [UInt8] = [
        0b0111111, 0b0000110, 0b1011011, 0b1001111, 0b1100110,
        0b1101101, 0b1111100, 0b0000111, 0b1111111, 0b1100111
    ]
    private static let cd4543Digits: [UInt8] = [
        0b0111111, 0b0000110, 0b1011011, 0b1001111, 0b1100110,
        0b1101101, 0b1111101, 0b0000111, 0b1111111, 0b1101111
    ]

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

    func powerDidFail() {
        latchedCodes = Self.allCodes
    }

    func evaluate() {
        let is4511 = kind == .cd4511
        let latch = pins[is4511 ? 5 : 1]!.state
        let transparentLevel: LogicState = is4511 ? .low : .high
        if latch == transparentLevel {
            latchedCodes = inputCodes()
        } else if latch != transparentLevel.inverted {
            latchedCodes.formUnion(inputCodes())
        }

        // The latch is upstream of every override. Each control branch sees
        // the codes admitted by the latch and applies the whole output rule.
        let blank = pins[is4511 ? 4 : 7]!.state
        let blankLevels = PresettableCounterState.possibilities(is4511 ? blank.inverted : blank)
        let lampLevels = is4511 ? PresettableCounterState.possibilities(pins[3]!.state.inverted) : [false]
        let phaseLevels = is4511 ? [false] : PresettableCounterState.possibilities(pins[6]!.state)
        let digits = is4511 ? Self.cd4511Digits : Self.cd4543Digits

        var alwaysHigh = Self.allSegments
        var sometimesHigh: UInt8 = 0
        for lamp in lampLevels {
            for blanked in blankLevels {
                for phase in phaseLevels {
                    for code in latchedCodes {
                        let decoded = code < digits.count ? digits[code] : 0
                        let pattern = lamp ? Self.allSegments : (blanked ? 0 : decoded)
                        let output = phase ? pattern ^ Self.allSegments : pattern
                        alwaysHigh &= output
                        sometimesHigh |= output
                    }
                }
            }
        }
        for (bit, number) in kind.outputs.enumerated() {
            let mask: UInt8 = 1 << bit
            pins[number]!.drive(PresettableCounterState.consensus(
                low: alwaysHigh & mask == 0, high: sometimesHigh & mask != 0
            ))
        }
    }

    private func inputCodes() -> Set<Int> {
        var knownMask = 0
        var highBits = 0
        for (bit, number) in kind.inputs.enumerated() {
            switch pins[number]!.state {
            case .high:
                highBits |= 1 << bit
                knownMask |= 1 << bit
            case .low:
                knownMask |= 1 << bit
            case .undefined, .highImpedance:
                break
            }
        }
        return Self.allCodes.filter { $0 & knownMask == highBits }
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
