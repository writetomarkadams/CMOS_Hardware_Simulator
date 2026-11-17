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

    // Sequential models can discard stored state when their supply becomes invalid.
    func powerDidFail()
}

extension PoweredChip {
    func powerDidFail() {}

    var powerState: ChipPowerState {
        let vdd = pins[supplyPins.vdd]!
        let vss = pins[supplyPins.vss]!
        if (vdd.state != .highImpedance && vdd.state != .high) ||
            (vss.state != .highImpedance && vss.state != .low) ||
            (vdd.supplyRail != nil && vdd.supplyRail != .fiveVolts) ||
            (vss.supplyRail != nil && vss.supplyRail != .ground) ||
            (vdd.state != .highImpedance && vdd.supplyRail != .fiveVolts) ||
            (vss.state != .highImpedance && vss.supplyRail != .ground) {
            return .incorrect
        }
        guard vdd.supplyRail == .fiveVolts, vss.supplyRail == .ground,
              vdd.state == .high, vss.state == .low else { return .disconnected }
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
