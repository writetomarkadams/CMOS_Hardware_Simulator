import Observation

@Observable
final class TwoDigitCounter {
    private(set) var count = 0
    private(set) var carryOut: LogicState = .highImpedance
    var countsUp = true {
        didSet {
            direction.drive(countsUp ? .high : .low)
            settleAndUpdateReadouts()
        }
    }

    private let engine = SimulationEngine()
    private let carry = Net(name: "ONES_CARRY")
    private let ones = CD4510()
    private let tens = CD4510()
    private let clock = Pin(number: 1, name: "CLOCK", direction: .output)
    private let direction = Pin(number: 2, name: "UP_DOWN", direction: .output)
    private let resetSignal = Pin(number: 3, name: "RESET", direction: .output)

    init() {
        for chip in [ones, tens] {
            engine.addComponent(chip)
            chip.pins[1]!.receive(.low) // Preset disabled
        }
        ones.pins[5]!.receive(.low)

        for (source, pinNumber) in [(clock, 15), (direction, 10), (resetSignal, 9)] {
            let net = Net(name: source.name)
            net.connect(source)
            net.connect(ones.pins[pinNumber]!)
            net.connect(tens.pins[pinNumber]!)
            engine.addNet(net)
        }

        carry.connect(ones.pins[7]!)
        carry.connect(tens.pins[5]!)
        engine.addNet(carry)

        clock.drive(.low)
        direction.drive(.high)
        resetSignal.drive(.low)
        settleAndUpdateReadouts()
    }

    func step() {
        clock.drive(.high)
        engine.settle()
        clock.drive(.low)
        settleAndUpdateReadouts()
    }

    func reset() {
        resetSignal.drive(.high)
        engine.settle()
        resetSignal.drive(.low)
        settleAndUpdateReadouts()
    }

    private func settleAndUpdateReadouts() {
        engine.settle()
        count = tens.count * 10 + ones.count
        carryOut = carry.state
    }
}
