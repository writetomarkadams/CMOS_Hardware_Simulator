enum PowerMode: String, Codable, CaseIterable {
    case automatic = "Automatic Power"
    case explicit = "Explicit Power"
}

enum SupplyRail: Equatable {
    case fiveVolts, ground
}

enum ChipPowerState: Equatable {
    case powered, disconnected, incorrect

    var warning: String? {
        switch self {
        case .powered: nil
        case .disconnected: "Supply disconnected"
        case .incorrect: "Incorrect supply connection"
        }
    }
}

protocol PoweredChip: LogicComponent {
    var supplyPins: (vdd: Int, vss: Int) { get }

    var additionalGroundPins: [Int] { get }

    // Sequential models can discard stored state when their supply becomes invalid.
    func powerDidFail()
}

extension PoweredChip {
    func powerDidFail() {}
    var additionalGroundPins: [Int] { [] }

    var powerState: ChipPowerState {
        let supplies = [(supplyPins.vdd, LogicState.high, SupplyRail.fiveVolts)] +
            ([supplyPins.vss] + additionalGroundPins).map { ($0, .low, .ground) }
        var disconnected = false
        for (number, level, rail) in supplies {
            let pin = pins[number]!
            if pin.state == .highImpedance && pin.supplyRail == nil {
                disconnected = true
            } else if pin.state != level || pin.supplyRail != rail {
                return .incorrect
            }
        }
        if disconnected { return .disconnected }
        return .powered
    }

    func disableOutputs() {
        for pin in pins.values where pin.direction == .output || pin.direction == .bidirectional {
            pin.drive(.undefined)
        }
    }
}

extension QuadLogicChip: PoweredChip {
    var supplyPins: (vdd: Int, vss: Int) { (14, 7) }
}
extension CD40106: PoweredChip {
    var supplyPins: (vdd: Int, vss: Int) { (14, 7) }
}
extension CD4027: PoweredChip {
    var supplyPins: (vdd: Int, vss: Int) { (16, 8) }
}
extension CD4060: PoweredChip {
    var supplyPins: (vdd: Int, vss: Int) { (16, 8) }
}
extension CD4510: PoweredChip {
    var supplyPins: (vdd: Int, vss: Int) { (16, 8) }
}
extension SevenSegmentDriver: PoweredChip {
    var supplyPins: (vdd: Int, vss: Int) { (16, 8) }
}
