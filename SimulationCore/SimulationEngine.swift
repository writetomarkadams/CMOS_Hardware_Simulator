
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


// A closed connection joins terminals without driving either terminal.
protocol SwitchedConnectivity: LogicComponent {
    var closedConnections: [(Pin, Pin)] { get }
}

final class SimulationEngine {
    private struct NetLink: Equatable {
        let first: Int
        let second: Int
    }

    private let timing = NE555TimingSystem()
    var hasTimingNetworks: Bool { !timing.networks.isEmpty }

    func timingVoltage(on net: Net) -> Double? {
        timing.networks.first { network in
            net.pins.contains { $0 === network.timer.pins[6] }
        }?.capacitor.voltage
    }

    struct TimeAdvance {
        let elapsed: Double
        let stable: Bool
    }

    /// Advance to each RC comparator crossing and settle downstream logic at every edge.
    /// A bounded batch returns elapsed time so the caller retains unprocessed time.
    func advanceTime(by seconds: Double, maximumEvents: Int = 256,
                     onSettled: ((Double, Bool) -> Void)? = nil) -> TimeAdvance {
        guard seconds.isFinite, seconds >= 0, maximumEvents > 0 else { return TimeAdvance(elapsed: 0, stable: false) }
        var stable = settle()
        onSettled?(0, stable)
        var elapsed = 0.0
        for _ in 0..<maximumEvents {
            let remaining = seconds - elapsed
            if remaining <= 0 { break }
            let step = min(remaining, timing.nextEventDelay)
            timing.integrate(step)
            elapsed += step
            let stepStable = settle()
            stable = stepStable && stable
            onSettled?(elapsed, stepStable)
            if step == remaining { break }
        }
        return TimeAdvance(elapsed: elapsed, stable: stable)
    }

    private var switches: [any SwitchedConnectivity] = []


    private(set) var components: [any LogicComponent] = []
    private(set) var nets: [Net] = []
    var automaticallyPowerChips = false
    var onEvaluationPass: (() -> Void)?
    private var unpoweredChips: Set<ObjectIdentifier> = []
    private var drivenPins: [Pin] = []
    private var previousStates: [LogicState] = []

    // Prevent an unstable circuit from running forever.
    let maximumIterations = 100

    func addComponent(_ component: any LogicComponent) {
        components.append(component)
        if let device = component as? any SwitchedConnectivity {
            switches.append(device)
        }
        for pin in component.pins.values where pin.direction != .input && pin.direction != .noConnect {
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

        // Unwired switch terminals still belong to the electrical island when closed.
        var electricalNets = nets
        var netByPin: [ObjectIdentifier: Int] = [:]
        if !switches.isEmpty {
            for (index, net) in nets.enumerated() {
                for pin in net.pins { netByPin[ObjectIdentifier(pin)] = index }
            }
            for device in switches {
                for pin in device.pins.values where pin.direction == .bidirectional {
                    let id = ObjectIdentifier(pin)
                    guard netByPin[id] == nil else { continue }
                    let net = Net(name: pin.name)
                    net.connect(pin)
                    netByPin[id] = electricalNets.count
                    electricalNets.append(net)
                }
            }
        }

        let mechanicalTerminals = Set(switches.compactMap { $0 as? MechanicalSwitch }
            .flatMap { $0.pins.values.map(ObjectIdentifier.init) })
        let lowerTransistorByUpper = seriesNPNPairs()
        var links: [NetLink] = []
        resolve(electricalNets, links: links)
        timing.configure(components: components, nets: nets, automaticPower: automaticallyPowerChips)
        for _ in 0..<maximumIterations {
            let nextLinks = switches.flatMap { device -> [NetLink] in
                if let chip = device as? any PoweredChip,
                   !automaticallyPowerChips, chip.powerState != .powered { return [] }
                return device.closedConnections.map { first, second in
                    NetLink(first: netByPin[ObjectIdentifier(first)]!, second: netByPin[ObjectIdentifier(second)]!)
                }
            }
            if nextLinks != links {
                links = nextLinks
                resolve(electricalNets, links: links)
                continue
            }

            for index in drivenPins.indices {
                previousStates[index] = drivenPins[index].driveState
            }
            let modeled = switches.contains { $0 is AnalogSwitch } ? [] : DiscreteDC.apply(
                components: components, nets: nets, excludedTerminals: mechanicalTerminals
            )
            timing.prepareInputs()
            onEvaluationPass?()
            for component in components where !modeled.contains(ObjectIdentifier(component)) {
                if let chip = component as? any PoweredChip, !automaticallyPowerChips, chip.powerState != .powered {
                    if unpoweredChips.insert(ObjectIdentifier(chip)).inserted {
                        chip.powerDidFail()
                    }
                    if !(chip is any SwitchedConnectivity) { chip.disableOutputs() }
                } else {
                    let id = ObjectIdentifier(component)
                    unpoweredChips.remove(id)
                    if let upper = component as? Transistor, let lower = lowerTransistorByUpper[id] {
                        let emitter = lower.pin(.emitter)
                        let lowerIsOff = emitter.supplyRail == .ground && emitter.state == .low &&
                            lower.pin(.base).state == .low
                        upper.evaluate(seriesPathOpen: lowerIsOff)
                    } else {
                        component.evaluate()
                    }
                }
            }

            var changed = false
            for index in drivenPins.indices where previousStates[index] != drivenPins[index].driveState {
                changed = true
                break
            }
            if !changed { return true }

            resolve(electricalNets, links: links)
        }

        print("WARNING: Simulation did not settle.")
        return false
    }

    private func seriesNPNPairs() -> [ObjectIdentifier: Transistor] {
        let devices = components.compactMap { $0 as? Transistor }
            .filter { $0.designation == .twoN3904 }
        guard devices.count >= 2 else { return [:] }

        var emitters: [ObjectIdentifier: Transistor] = [:]
        var collectors: [ObjectIdentifier: Transistor] = [:]
        for device in devices {
            emitters[ObjectIdentifier(device.pin(.emitter))] = device
            collectors[ObjectIdentifier(device.pin(.collector))] = device
        }
        var lowerByUpper: [ObjectIdentifier: Transistor] = [:]
        // A third pin can load or switch the midpoint, so only accept a direct pair.
        for net in nets where net.pins.count == 2 {
            let first = ObjectIdentifier(net.pins[0])
            let second = ObjectIdentifier(net.pins[1])
            guard let upper = emitters[first] ?? emitters[second],
                  let lower = collectors[first] ?? collectors[second],
                  upper !== lower else { continue }
            lowerByUpper[ObjectIdentifier(upper)] = lower
        }
        return lowerByUpper
    }

    private func resolve(_ nets: [Net], links: [NetLink]) {
        guard !links.isEmpty else {
            for net in nets { net.resolve() }
            return
        }

        var neighbors: [Int: [Int]] = [:]
        for link in links where link.first != link.second {
            neighbors[link.first, default: []].append(link.second)
            neighbors[link.second, default: []].append(link.first)
        }

        var visited: Set<Int> = []
        for index in nets.indices where visited.insert(index).inserted {
            guard neighbors[index] != nil else {
                nets[index].resolve()
                continue
            }
            var island = [nets[index]]
            var pending = [index]
            while let current = pending.popLast() {
                for neighbor in neighbors[current, default: []] where visited.insert(neighbor).inserted {
                    island.append(nets[neighbor])
                    pending.append(neighbor)
                }
            }
            Net.resolve(together: island)
        }
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
