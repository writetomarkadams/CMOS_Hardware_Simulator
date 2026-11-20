/// Digital NE555 plus ideal comparator inputs from recognised RC timing networks.
final class NE555: PoweredChip {
    let supplyPins = (vdd: 8, vss: 1)
    let pins: [Int: Pin]
    var timingVoltage: Double?
    var timingIssue: String?
    var timingTriggerIsAnalog = false
    private var latch: LogicState = .undefined

    init() {
        let definitions: [(Int, String, PinDirection)] = [
            (1, "GND", .power), (2, "TRIG", .input), (3, "OUT", .output),
            (4, "RESET", .input), (5, "CONT", .input), (6, "THRES", .input),
            (7, "DISCH", .output), (8, "VCC", .power)
        ]
        pins = Dictionary(uniqueKeysWithValues: definitions.map {
            ($0.0, Pin(number: $0.0, name: $0.1, direction: $0.2))
        })
    }

    func powerDidFail() { latch = .undefined }

    func evaluate() {
        // RESET overrides both comparators. TRIG has priority over THRES (TI function table).
        if pins[4]!.state == .low {
            latch = .low
        } else if pins[4]!.state != .high || pins[5]!.state != .highImpedance || timingIssue != nil {
            // Driven CONT changes analog thresholds, which this digital model cannot calculate.
            latch = .undefined
        } else {
            let trigger: LogicState = timingTriggerIsAnalog && timingVoltage != nil
                ? (timingVoltage! <= 5.0 / 3.0 + 1e-12 ? .low : .high) : pins[2]!.state
            let threshold: LogicState = timingVoltage.map { $0 >= 10.0 / 3.0 - 1e-12 ? .high : .low } ?? pins[6]!.state
            switch (trigger, threshold) {
            case (.low, _): latch = .high
            case (.high, .high): latch = .low
            case (.high, .low): break
            default: latch = .undefined
            }
        }
        pins[3]!.drive(latch)
        // Discharge is an open-collector sink, never a HIGH source or supply rail.
        pins[7]!.drive(latch == .low ? .low : latch == .high ? .highImpedance : .undefined)
    }
}
