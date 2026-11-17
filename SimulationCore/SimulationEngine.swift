
func testNetResolution() {
    let outputA = Pin(number: 1, name: "A", direction: .output)
    let outputB = Pin(number: 2, name: "B", direction: .output)
    let input = Pin(number: 3, name: "IN", direction: .input)

    let net = Net(name: "TEST_NET")
    net.connect(outputA)
    net.connect(outputB)
    net.connect(input)

    outputA.drive(.high)
    net.resolve()
    print("Test 1: \(net.state)")

    outputA.drive(.low)
    net.resolve()
    print("Test 2: \(net.state)")

    outputA.drive(.high)
    outputB.drive(.low)
    net.resolve()
    print("Test 3: \(net.state)")
}


protocol LogicComponent: AnyObject {
    var pins: [Int: Pin] { get }

    func evaluate()
}


final class SimulationEngine {

    private(set) var components: [any LogicComponent] = []
    private(set) var nets: [Net] = []
    private var drivenPins: [Pin] = []
    private var previousStates: [LogicState] = []

    // Prevent an unstable circuit from running forever.
    let maximumIterations = 100

    func addComponent(_ component: any LogicComponent) {
        components.append(component)
        for pin in component.pins.values where pin.direction != .input {
            drivenPins.append(pin)
            previousStates.append(pin.driveState)
        }
    }

    func addNet(_ net: Net) {
        nets.append(net)
    }

    // Evaluate until all logic states become stable.
    @discardableResult
    func settle() -> Bool {

        for net in nets {
            net.resolve()
        }

        for _ in 0..<maximumIterations {
            for index in drivenPins.indices {
                previousStates[index] = drivenPins[index].driveState
            }
            for component in components {
                component.evaluate()
            }

            var changed = false
            for index in drivenPins.indices where previousStates[index] != drivenPins[index].driveState {
                changed = true
                break
            }
            if !changed { return true }

            for net in nets {
                net.resolve()
            }
        }

        print("WARNING: Simulation did not settle.")
        return false
    }
}


func testCD4081() {
    let chip = CD4081()

    let testCases: [(LogicState, LogicState, LogicState)] = [
        (.low,  .low,  .low),
        (.low,  .high, .low),
        (.high, .low,  .low),
        (.high, .high, .high)
    ]

    print("\nCD4081 AND Gate Test")
    print("--------------------")

    for (a, b, expected) in testCases {
        // Apply input logic levels.
        chip.pins[1]?.receive(a)
        chip.pins[2]?.receive(b)

        // Evaluate all four gates.
        chip.evaluate()

        // Read the output driven by pin 3.
        let actual = chip.pins[3]!.driveState
        let passed = actual == expected

        print(
            "A: \(a), B: \(b) -> Q: \(actual) " +
            (passed ? "PASS" : "FAIL")
        )
    }
}


func testConnectedCD4081() {
    let chip = CD4081()

    // Two virtual signal generators.
    let sourceA = Pin(
        number: 1,
        name: "SOURCE_A",
        direction: .output
    )

    let sourceB = Pin(
        number: 2,
        name: "SOURCE_B",
        direction: .output
    )

    // Our virtual logic probe.
    let probe = Pin(
        number: 1,
        name: "PROBE",
        direction: .input
    )

    // Three virtual wires.
    let netA = Net(name: "INPUT_A")
    let netB = Net(name: "INPUT_B")
    let netQ = Net(name: "OUTPUT_Q")

    // Connect the signal sources to the CD4081.
    netA.connect(sourceA)
    netA.connect(chip.pins[1]!)

    netB.connect(sourceB)
    netB.connect(chip.pins[2]!)

    // Connect the CD4081 output to the probe.
    netQ.connect(chip.pins[3]!)
    netQ.connect(probe)

    let testCases: [(LogicState, LogicState, LogicState)] = [
        (.low,  .low,  .low),
        (.low,  .high, .low),
        (.high, .low,  .low),
        (.high, .high, .high)
    ]

    print("\nCD4081 Connected Circuit Test")
    print("-----------------------------")

    for (a, b, expected) in testCases {

        // Drive our virtual signal sources.
        sourceA.drive(a)
        sourceB.drive(b)

        // Propagate input signals through the nets.
        netA.resolve()
        netB.resolve()

        // Evaluate the CD4081.
        chip.evaluate()

        // Propagate its output to the logic probe.
        netQ.resolve()

        let actual = probe.state
        let passed = actual == expected

        print(
            "A: \(a), B: \(b) -> Probe: \(actual) " +
            (passed ? "PASS" : "FAIL")
        )
    }
}


func testAutomaticPropagation() {
    let engine = SimulationEngine()
    let chip = CD4081()

    engine.addComponent(chip)

    // Three independent signal sources.
    let sourceA = Pin(number: 1, name: "A", direction: .output)
    let sourceB = Pin(number: 2, name: "B", direction: .output)
    let sourceC = Pin(number: 3, name: "C", direction: .output)

    let probe = Pin(number: 1, name: "PROBE", direction: .input)

    // Create the circuit connections.
    let netA = Net(name: "A")
    netA.connect(sourceA)
    netA.connect(chip.pins[1]!)

    let netB = Net(name: "B")
    netB.connect(sourceB)
    netB.connect(chip.pins[2]!)

    // Gate 1 output connects to gate 2 input.
    let netIntermediate = Net(name: "INTERMEDIATE")
    netIntermediate.connect(chip.pins[3]!)
    netIntermediate.connect(chip.pins[5]!)

    let netC = Net(name: "C")
    netC.connect(sourceC)
    netC.connect(chip.pins[6]!)

    let netOutput = Net(name: "OUTPUT")
    netOutput.connect(chip.pins[4]!)
    netOutput.connect(probe)

    for net in [netA, netB, netIntermediate, netC, netOutput] {
        engine.addNet(net)
    }

    print("\nAutomatic Propagation Test")
    print("--------------------------")

    let testCases: [(LogicState, LogicState, LogicState)] = [
        (.low,  .high, .high),
        (.high, .low,  .high),
        (.high, .high, .low),
        (.high, .high, .high)
    ]

    for (a, b, c) in testCases {
        sourceA.drive(a)
        sourceB.drive(b)
        sourceC.drive(c)

        let settled = engine.settle()
        let expected: LogicState =
            (a == .high && b == .high && c == .high) ? .high : .low

        let actual = probe.state
        let passed = settled && actual == expected

        print(
            "A: \(a), B: \(b), C: \(c) " +
            "-> Q: \(actual) " +
            (passed ? "PASS" : "FAIL")
        )
    }
}
