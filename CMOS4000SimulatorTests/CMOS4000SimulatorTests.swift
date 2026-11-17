
import CoreGraphics
import Foundation
import Testing
@testable import CMOS4000Simulator

struct LogicStateTests {

    @Test("Logic states have the correct descriptions")
    func logicStateDescriptions() {
        #expect(LogicState.low.description == "LOW")
        #expect(LogicState.high.description == "HIGH")
        #expect(LogicState.highImpedance.description == "HIGH-Z")
        #expect(LogicState.undefined.description == "UNDEFINED")
    }

    @Test("Conflicting output drivers produce undefined")
    func conflictingDrivers() {
        let outputA = Pin(number: 1, name: "A", direction: .output)
        let outputB = Pin(number: 2, name: "B", direction: .output)

        let net = Net(name: "TEST")
        net.connect(outputA)
        net.connect(outputB)

        outputA.drive(.high)
        outputB.drive(.low)
        net.resolve()

        #expect(net.state == .undefined)
    }
}


struct CD4081Tests {

    @Test("All four AND gates produce correct outputs")
    func truthTables() {
        let chip = CD4081()

        // Actual CD4081 pin assignments:
        // Gate 1: 1, 2 -> 3
        // Gate 2: 5, 6 -> 4
        // Gate 3: 8, 9 -> 10
        // Gate 4: 12, 13 -> 11

        let gates: [(Int, Int, Int)] = [
            (1, 2, 3),
            (5, 6, 4),
            (8, 9, 10),
            (12, 13, 11)
        ]

        let testCases: [(LogicState, LogicState, LogicState)] = [
            (.low,  .low,  .low),
            (.low,  .high, .low),
            (.high, .low,  .low),
            (.high, .high, .high)
        ]

        for (inputA, inputB, output) in gates {
            for (a, b, expected) in testCases {

                chip.pins[inputA]?.receive(a)
                chip.pins[inputB]?.receive(b)

                chip.evaluate()

                let actual = chip.pins[output]?.driveState

                #expect(
                    actual == expected,
                    "Gate output pin \(output) produced an incorrect result"
                )
            }
        }
    }

    @Test("Undefined inputs propagate correctly")
    func undefinedInputs() {
        let chip = CD4081()

        chip.pins[1]?.receive(.high)
        chip.pins[2]?.receive(.undefined)

        chip.evaluate()

        #expect(chip.pins[3]?.driveState == .undefined)

        // A definite LOW dominates an unknown input.
        chip.pins[1]?.receive(.low)
        chip.evaluate()

        #expect(chip.pins[3]?.driveState == .low)
    }
}


struct SimulationEngineTests {

    @Test("Logic propagates through two connected AND gates")
    func automaticPropagation() {
        let engine = SimulationEngine()
        let chip = CD4081()

        engine.addComponent(chip)

        let sourceA = Pin(number: 1, name: "A", direction: .output)
        let sourceB = Pin(number: 2, name: "B", direction: .output)
        let sourceC = Pin(number: 3, name: "C", direction: .output)
        let probe = Pin(number: 1, name: "PROBE", direction: .input)

        let netA = Net(name: "A")
        netA.connect(sourceA)
        netA.connect(chip.pins[1]!)

        let netB = Net(name: "B")
        netB.connect(sourceB)
        netB.connect(chip.pins[2]!)

        let intermediate = Net(name: "INTERMEDIATE")
        intermediate.connect(chip.pins[3]!)
        intermediate.connect(chip.pins[5]!)

        let netC = Net(name: "C")
        netC.connect(sourceC)
        netC.connect(chip.pins[6]!)

        let output = Net(name: "OUTPUT")
        output.connect(chip.pins[4]!)
        output.connect(probe)

        for net in [netA, netB, intermediate, netC, output] {
            engine.addNet(net)
        }

        let testCases: [(LogicState, LogicState, LogicState, LogicState)] = [
            (.low,  .high, .high, .low),
            (.high, .low,  .high, .low),
            (.high, .high, .low,  .low),
            (.high, .high, .high, .high)
        ]

        for (a, b, c, expected) in testCases {
            sourceA.drive(a)
            sourceB.drive(b)
            sourceC.drive(c)

            let settled = engine.settle()

            #expect(settled)
            #expect(probe.state == expected)
        }
    }
}


struct ClockEdgeDetectorTests {

    @Test("Detect rising and falling clock edges")
    func clockTransitions() {
        let detector = ClockEdgeDetector()

        // Initial state should not create an edge.
        #expect(detector.update(.low) == .none)

        // LOW -> HIGH
        #expect(detector.update(.high) == .rising)

        // Remaining HIGH must not create another edge.
        #expect(detector.update(.high) == .none)

        // HIGH -> LOW
        #expect(detector.update(.low) == .falling)

        // Remaining LOW must not create another edge.
        #expect(detector.update(.low) == .none)

        // Another LOW -> HIGH transition.
        #expect(detector.update(.high) == .rising)
    }

    @Test("Undefined states do not create false edges")
    func undefinedStates() {
        let detector = ClockEdgeDetector()

        #expect(detector.update(.undefined) == .none)
        #expect(detector.update(.high) == .none)
        #expect(detector.update(.undefined) == .none)
        #expect(detector.update(.low) == .none)
    }

    @Test("Reset clears previous clock state")
    func resetDetector() {
        let detector = ClockEdgeDetector()

        #expect(detector.update(.low) == .none)
        #expect(detector.update(.high) == .rising)

        detector.reset()

        // HIGH after reset is not a new rising edge.
        #expect(detector.update(.high) == .none)

        #expect(detector.update(.low) == .falling)
        #expect(detector.update(.high) == .rising)
    }
}

struct BCDCountStateTests {

    @Test("Counter increments and rolls over")
    func countUp() {
        var counter = BCDCountState()

        for expected in 1...9 {
            counter.countUp()
            #expect(counter.value == expected)
        }

        counter.countUp()
        #expect(counter.value == 0)
    }

    @Test("Counter decrements and rolls under")
    func countDown() {
        var counter = BCDCountState()

        counter.countDown()
        #expect(counter.value == 9)

        counter.countDown()
        #expect(counter.value == 8)
    }


    @Test("Counter loads valid BCD values")
    func loadValue() {
        var counter = BCDCountState()

        let validLoad = counter.load(7)
        #expect(validLoad == true)
        #expect(counter.value == 7)

        let invalidLoad = counter.load(12)
        #expect(invalidLoad == false)
        #expect(counter.value == 7)

        let negativeLoad = counter.load(-1)
        #expect(negativeLoad == false)
        #expect(counter.value == 7)
    }


    @Test("Counter resets to zero")
    func resetCounter() {
        var counter = BCDCountState()

        counter.load(8)
        counter.reset()

        #expect(counter.value == 0)
    }

    @Test("Counter produces correct BCD output")
    func bcdOutput() {
        var counter = BCDCountState()

        counter.load(9)

        // Decimal 9 = binary 1001.
        // Bits are returned least significant first.
        #expect(counter.bits == [
            .high,
            .low,
            .low,
            .high
        ])
    }
}

struct CD4510Tests {

    @Test("CD4510 has all 16 physical pins")
    func pinDefinitions() {
        let chip = CD4510()
        chip.pins[1]?.receive(.low)  // Parallel Enable inactive
        #expect(chip.pins.count == 16)

        for number in 1...16 {
            #expect(chip.pins[number] != nil)
        }

        #expect(chip.pins[15]?.name == "CLOCK")
        #expect(chip.pins[10]?.name == "UP_DOWN")
        #expect(chip.pins[9]?.name == "RESET")

        #expect(chip.pins[6]?.name == "Q1")
        #expect(chip.pins[11]?.name == "Q2")
        #expect(chip.pins[14]?.name == "Q3")
        #expect(chip.pins[2]?.name == "Q4")
        #expect(chip.pins[12]?.name == "P2")
        #expect(chip.pins[13]?.name == "P3")
    }
    
    
    @Test("CD4510 counts once per rising clock edge")
    func risingEdgeCounting() {
        let chip = CD4510()
        chip.pins[1]?.receive(.low)  // Parallel Enable inactive
        chip.pins[9]?.receive(.low)    // RESET inactive
        chip.pins[10]?.receive(.high)  // Count UP
        chip.pins[5]?.receive(.low)    // Carry-in enables counting

        // Establish the initial LOW clock state.
        chip.pins[15]?.receive(.low)
        chip.evaluate()

        #expect(chip.count == 0)

        // First rising edge.
        chip.pins[15]?.receive(.high)
        chip.evaluate()

        #expect(chip.count == 1)

        // Repeated evaluation while HIGH must not count.
        chip.evaluate()
        chip.evaluate()
        chip.evaluate()

        #expect(chip.count == 1)

        // Falling edge must not count.
        chip.pins[15]?.receive(.low)
        chip.evaluate()

        #expect(chip.count == 1)

        // Second rising edge.
        chip.pins[15]?.receive(.high)
        chip.evaluate()

        #expect(chip.count == 2)

        // Decimal 2 = BCD 0010.
        #expect(chip.pins[6]?.driveState == .low)   // Q1
        #expect(chip.pins[11]?.driveState == .high) // Q2
        #expect(chip.pins[14]?.driveState == .low)  // Q3
        #expect(chip.pins[2]?.driveState == .low)   // Q4
    }

    @Test("CD4510 counts down and wraps from zero to nine")
    func countDownAndRollover() {
        let chip = CD4510()
        chip.pins[1]?.receive(.low)  // Parallel Enable inactive
        chip.pins[9]?.receive(.low)    // RESET inactive
        chip.pins[10]?.receive(.low)   // Count DOWN
        chip.pins[5]?.receive(.low)    // Counting enabled

        chip.pins[15]?.receive(.low)
        chip.evaluate()

        #expect(chip.pins[7]?.driveState == .low)

        // First rising edge: 0 -> 9
        chip.pins[15]?.receive(.high)
        chip.evaluate()

        #expect(chip.count == 9)
        #expect(chip.pins[7]?.driveState == .high)

        // Falling edge
        chip.pins[15]?.receive(.low)
        chip.evaluate()

        // Second rising edge: 9 -> 8
        chip.pins[15]?.receive(.high)
        chip.evaluate()

        #expect(chip.count == 8)
    }

    @Test("CD4510 counts up and wraps from nine to zero")
    func countUpAndRollover() {
        let chip = CD4510()
        chip.pins[1]?.receive(.low)  // Parallel Enable inactive
        chip.pins[9]?.receive(.low)
        chip.pins[10]?.receive(.high)
        chip.pins[5]?.receive(.low)

        chip.pins[15]?.receive(.low)
        chip.evaluate()

        for _ in 1...9 {
            chip.pins[15]?.receive(.high)
            chip.evaluate()

            chip.pins[15]?.receive(.low)
            chip.evaluate()
        }

        #expect(chip.count == 9)
        #expect(chip.pins[7]?.driveState == .low)

        chip.pins[15]?.receive(.high)
        chip.evaluate()

        #expect(chip.count == 0)
        #expect(chip.pins[7]?.driveState == .high)
    }

    @Test("CD4510 Carry Out responds to Carry In and direction without a clock edge")
    func carryOutControls() {
        let chip = CD4510()
        chip.pins[15]?.receive(.low)
        chip.pins[10]?.receive(.low)
        chip.pins[5]?.receive(.high)
        chip.evaluate()
        #expect(chip.pins[7]?.driveState == .high)

        chip.pins[5]?.receive(.low)
        chip.evaluate()
        #expect(chip.pins[7]?.driveState == .low)

        chip.pins[5]?.receive(.highImpedance)
        chip.evaluate()
        #expect(chip.pins[7]?.driveState == .undefined)

        chip.pins[5]?.receive(.low)
        chip.pins[10]?.receive(.high)
        chip.evaluate()
        #expect(chip.pins[7]?.driveState == .high)
        #expect(chip.count == 0)
    }

    @Test("Cascaded CD4510 counters traverse all 100 counts in both directions", arguments: [true, false])
    func synchronousCascade(onesFirst: Bool) throws {
        let engine = SimulationEngine()
        let ones = CD4510()
        let tens = CD4510()
        let clock = Pin(number: 1, name: "CLOCK_SOURCE", direction: .output)
        let direction = Pin(number: 2, name: "DIRECTION_SOURCE", direction: .output)

        let clockNet = Net(name: "CLOCK")
        clockNet.connect(clock)

        let directionNet = Net(name: "UP_DOWN")
        directionNet.connect(direction)

        for chip in onesFirst ? [ones, tens] : [tens, ones] {
            engine.addComponent(chip)
            chip.pins[1]?.receive(.low) // Preset disabled
            chip.pins[9]?.receive(.low) // Reset inactive
            clockNet.connect(try #require(chip.pins[15]))
            directionNet.connect(try #require(chip.pins[10]))
        }
        ones.pins[5]?.receive(.low)

        let carryNet = Net(name: "ONES_CARRY")
        carryNet.connect(try #require(ones.pins[7]))
        carryNet.connect(try #require(tens.pins[5]))

        for net in [clockNet, directionNet, carryNet] {
            engine.addNet(net)
        }

        clock.drive(.low)
        let sweeps: [(direction: LogicState, counts: [Int], terminalDigit: Int)] = [
            (.high, Array(1...99) + [0], 9),
            (.low, Array((0...99).reversed()), 0)
        ]

        for sweep in sweeps {
            direction.drive(sweep.direction)
            try #require(engine.settle())
            #expect(ones.count == 0)
            #expect(tens.count == 0)
            let initialCarry: LogicState = sweep.terminalDigit == 0 ? .low : .high
            #expect(carryNet.state == initialCarry)

            for expected in sweep.counts {
                let onesDigit = expected % 10
                let tensDigit = expected / 10
                let expectedCarry: LogicState = onesDigit == sweep.terminalDigit ? .low : .high

                // Check the count and carry on both clock levels.
                for clockLevel: LogicState in [.high, .low] {
                    clock.drive(clockLevel)
                    try #require(engine.settle())
                    #expect(ones.count == onesDigit)
                    #expect(tens.count == tensDigit)
                    #expect(carryNet.state == expectedCarry)
                }
            }
        }
    }

    @Test("Two-digit demo steps, wraps, reverses, and resets")
    func twoDigitDemoControls() {
        let counter = TwoDigitCounter()
        #expect(counter.count == 0)

        for expected in 1...10 {
            counter.step()
            #expect(counter.count == expected)
            #expect(counter.carryOut == (expected == 9 ? .low : .high))
        }

        counter.countsUp = false
        #expect(counter.count == 10)
        #expect(counter.carryOut == .low)
        counter.step()
        #expect(counter.count == 9)
        #expect(counter.carryOut == .high)

        counter.reset()
        #expect(counter.count == 0)
        #expect(counter.countsUp == false)
        #expect(counter.carryOut == .low)
        counter.step()
        #expect(counter.count == 99)

        counter.countsUp = true
        counter.step()
        #expect(counter.count == 0)
    }

    @Test("CD4510 resets asynchronously")
    func asynchronousReset() {
        let chip = CD4510()
        chip.pins[1]?.receive(.low)  // Parallel Enable inactive
        chip.pins[9]?.receive(.low)
        chip.pins[10]?.receive(.high)
        chip.pins[5]?.receive(.low)

        chip.pins[15]?.receive(.low)
        chip.evaluate()

        chip.pins[15]?.receive(.high)
        chip.evaluate()

        #expect(chip.count == 1)

        // RESET goes HIGH without a clock transition.
        chip.pins[9]?.receive(.high)
        chip.evaluate()

        #expect(chip.count == 0)

        // The clock is still HIGH.
        chip.pins[9]?.receive(.low)
        chip.evaluate()

        // Releasing RESET must not create another count.
        #expect(chip.count == 0)
    }


    @Test("CD4510 loads a preset value asynchronously")
    func parallelLoading() {
        let chip = CD4510()

        chip.pins[9]?.receive(.low)    // RESET inactive
        chip.pins[10]?.receive(.high)  // Count UP
        chip.pins[5]?.receive(.low)    // Counting enabled
        chip.pins[15]?.receive(.low)   // Clock LOW

        // Preset decimal 3 = BCD 0011
        chip.pins[4]?.receive(.high)   // P1
        chip.pins[12]?.receive(.high)  // P2
        chip.pins[13]?.receive(.low)    // P3
        chip.pins[3]?.receive(.low)    // P4

        chip.pins[1]?.receive(.high)   // Enable parallel loading

        chip.evaluate()

        #expect(chip.count == 3)

        // Disable parallel loading.
        chip.pins[1]?.receive(.low)
        chip.evaluate()

        // One rising clock edge should increment to 4.
        chip.pins[15]?.receive(.high)
        chip.evaluate()

        #expect(chip.count == 4)
        #expect(chip.pins[11]?.driveState == .low)  // Q2
        #expect(chip.pins[14]?.driveState == .high) // Q3
    }

    
}

struct WorkbenchTests {
    @Test("Workbench wires share a net and removing a wire disconnects its pin")
    func wireAndDisconnectGate() throws {
        let bench = Workbench()
        let source = WorkbenchSwitch()
        bench.add("Switch", component: source)
        bench.add("CD4081", component: CD4081())

        let sourcePin = WorkbenchTerminal(partID: 1, pinNumber: 1)
        let inputA = WorkbenchTerminal(partID: 2, pinNumber: 1)
        let inputB = WorkbenchTerminal(partID: 2, pinNumber: 2)
        let output = WorkbenchTerminal(partID: 2, pinNumber: 3)

        let bend = CGPoint(x: 100, y: 50)
        bench.select(sourcePin)
        bench.addBend(at: bend)
        #expect(bench.wires.isEmpty)
        bench.select(inputA)
        #expect(bench.wires.first?.bends == [bend])
        #expect(bench.pendingBends.isEmpty)
        bench.select(inputA)
        bench.select(inputB)
        let secondWire = try #require(bench.wires.last)
        #expect(bench.readings[output] == .low)

        bench.toggle(source)
        #expect(bench.isStable)
        #expect(bench.readings[inputB] == .high)
        #expect(bench.readings[output] == .high)

        bench.selectWire(secondWire.id)
        bench.removeSelectedWire()
        #expect(bench.selectedWireID == nil)
        #expect(bench.readings[inputA] == .high)
        #expect(bench.readings[inputB] == .highImpedance)
        #expect(bench.readings[output] == .undefined)

        bench.select(inputA)
        bench.addBend(at: bend)
        bench.removePart(inputA.partID)
        #expect(bench.parts.map(\.id) == [sourcePin.partID])
        #expect(bench.wires.isEmpty)
        #expect(bench.selectedTerminal == nil)
        #expect(bench.pendingBends.isEmpty)
        #expect(bench.readings[inputA] == nil)
        #expect(bench.readings[sourcePin] == .high)
    }
}

extension WorkbenchTests {
    @Test("A wired logic LED observes the CD4081 output")
    func logicLED() {
        let bench = Workbench()
        let source = WorkbenchSwitch()
        bench.add("Switch", component: source)
        bench.addUnit(MultiUnitChip.and.units[0], kind: .and)
        bench.add("LED", component: WorkbenchLED())

        let switchOutput = WorkbenchTerminal(partID: 1, pinNumber: 1)
        let gateOutput = WorkbenchTerminal(partID: 2, pinNumber: 3)
        let ledInput = WorkbenchTerminal(partID: 3, pinNumber: 1)
        #expect(bench.readings[ledInput] == .highImpedance)

        bench.select(gateOutput)
        bench.select(ledInput)
        #expect(bench.readings[ledInput] == .undefined)

        for number in [1, 2] {
            bench.select(switchOutput)
            bench.select(WorkbenchTerminal(partID: 2, pinNumber: number))
        }
        #expect(bench.readings[ledInput] == .low)

        bench.toggle(source)
        #expect(bench.readings[ledInput] == .high)
    }

    @Test("CD4011 NAND truth table on all four physical gates")
    func nandTruthTable() throws {
        let chip = CD4011()
        let gates = [(1, 2, 3), (5, 6, 4), (8, 9, 10), (12, 13, 11)]
        let cases: [(LogicState, LogicState, LogicState)] = [
            (.low, .low, .high), (.low, .high, .high), (.high, .low, .high),
            (.high, .high, .low), (.low, .highImpedance, .high),
            (.high, .highImpedance, .undefined), (.undefined, .high, .undefined)
        ]

        for (inputA, inputB, output) in gates {
            let a = try #require(chip.pins[inputA])
            let b = try #require(chip.pins[inputB])
            let result = try #require(chip.pins[output])
            for (first, second, expected) in cases {
                a.receive(first)
                b.receive(second)
                chip.evaluate()
                #expect(result.driveState == expected)
            }
        }
    }

    @Test("Quad gate units share a package and expose distinct physical pins", arguments: [MultiUnitChip.and, .nand])
    func individuallyPlacedGates(kind: MultiUnitChip) throws {
        let bench = Workbench()
        bench.addUnit(kind.units[0], kind: kind)
        let first = try #require(bench.parts.first)
        let package = try #require(first.unitPlacement?.packageID)
        bench.addUnit(kind.units[1], kind: kind, to: package)
        bench.addUnit(kind.units[1], kind: kind, to: package)
        bench.addUnit(kind.units[3], kind: kind)
        try #require(bench.parts.count == 3)

        let second = bench.parts[1]
        #expect(first.component === second.component)
        #expect(first.component !== bench.parts[2].component)
        #expect(first.pins.keys.sorted() == [1, 2, 3])
        #expect(second.pins.keys.sorted() == [4, 5, 6])
        #expect(bench.parts[2].pins.keys.sorted() == [11, 12, 13])

        bench.removePart(first.id)
        #expect(bench.availableUnits(in: package, kind: kind).map(\.letter) == ["A", "C", "D"])
        #expect(bench.parts.first?.component === second.component)
    }
}

struct CD4027Tests {
    @Test("CD4027 sets and resets asynchronously and toggles on rising edges")
    func flipFlop() {
        let chip = CD4027()
        for number in [3, 4, 5, 6, 7, 9, 12, 13] {
            chip.pins[number]?.receive(.low)
        }
        chip.pins[7]?.receive(.high)
        chip.pins[12]?.receive(.high)
        chip.evaluate()
        #expect(chip.pins[1]?.driveState == .high)
        #expect(chip.pins[2]?.driveState == .low)
        #expect(chip.pins[15]?.driveState == .low)
        #expect(chip.pins[14]?.driveState == .high)

        chip.pins[7]?.receive(.low)
        chip.pins[5]?.receive(.high)
        chip.pins[6]?.receive(.high)
        chip.pins[3]?.receive(.high)
        chip.evaluate()
        #expect(chip.pins[1]?.driveState == .low)
        chip.evaluate()
        #expect(chip.pins[1]?.driveState == .low)

        chip.pins[3]?.receive(.low)
        chip.evaluate()
        #expect(chip.pins[1]?.driveState == .low)
        chip.pins[3]?.receive(.high)
        chip.evaluate()
        #expect(chip.pins[1]?.driveState == .high)
        #expect(chip.pins[15]?.driveState == .low)
    }
}

struct CD40106Tests {
    @Test("Each CD40106 inverter drives the opposite digital level on its physical output")
    func inversion() {
        for (input, output) in [(1, 2), (3, 4), (5, 6), (9, 8), (11, 10), (13, 12)] {
            let chip = CD40106()
            chip.evaluate()
            #expect(chip.pins[output]?.driveState == .undefined)
            chip.pins[input]?.receive(.low)
            chip.evaluate()
            #expect(chip.pins[output]?.driveState == .high)
            chip.pins[input]?.receive(.high)
            chip.evaluate()
            #expect(chip.pins[output]?.driveState == .low)
        }
    }
}

extension WorkbenchTests {
    @Test("The workbench clock alternates the wired output and pauses at LOW")
    func clockSource() {
        let bench = Workbench()
        let clock = WorkbenchClock()
        bench.add("Clock", component: clock)
        bench.add("LED", component: WorkbenchLED())

        let output = WorkbenchTerminal(partID: 1, pinNumber: 1)
        let input = WorkbenchTerminal(partID: 2, pinNumber: 1)
        bench.select(output)
        bench.select(input)
        #expect(bench.readings[input] == .low)

        bench.advanceClock(clock)
        #expect(bench.readings[input] == .high)
        bench.advanceClock(clock)
        #expect(bench.readings[input] == .low)
        bench.advanceClock(clock)
        #expect(bench.readings[input] == .high)

        bench.stopClock(clock)
        #expect(bench.readings[input] == .low)
        bench.advanceClock(clock)
        #expect(bench.readings[input] == .high)
    }
}

extension WorkbenchTests {
    @Test("Adding chip units fills each package before assigning another designator")
    func automaticPackageAllocation() throws {
        let bench = Workbench()
        bench.add("Switch", component: WorkbenchSwitch())
        for _ in 0..<3 {
            bench.addNextUnit(for: .jk)
        }
        try #require(bench.parts.count == 4)
        #expect(bench.parts.compactMap(\.reference) == ["U1A", "U1B", "U2A"])
        #expect(bench.parts[1].component === bench.parts[2].component)
        #expect(bench.parts[1].component !== bench.parts[3].component)

        bench.add("CD4510", component: CD4510())
        #expect(bench.parts.last?.reference == "U3")
        bench.removePart(bench.parts[2].id)
        #expect(bench.nextUnit(for: .jk)?.reference == "U1B")
        bench.addNextUnit(for: .jk)
        #expect(bench.parts.last?.reference == "U1B")
        #expect(bench.parts.last?.component === bench.parts[1].component)
    }
}

extension WorkbenchTests {
    @Test("A grounded 2N3904 pulls a weakly driven collector LOW and releases it when off")
    func groundedTransistorSwitch() {
        let bench = Workbench()
        let baseSwitch = WorkbenchSwitch()
        let transistor = NPN2N3904()
        bench.add("Ground", component: WorkbenchSwitch())
        bench.add("Base", component: baseSwitch)
        bench.add("2N3904", component: transistor)
        bench.add("Pull-up", component: WorkbenchPullUp())
        bench.add("LED", component: WorkbenchLED())

        let collector = WorkbenchTerminal(partID: 3, pinNumber: 3)
        let indicator = WorkbenchTerminal(partID: 5, pinNumber: 1)
        let connections = [
            (WorkbenchTerminal(partID: 1, pinNumber: 1), WorkbenchTerminal(partID: 3, pinNumber: 1)),
            (WorkbenchTerminal(partID: 2, pinNumber: 1), WorkbenchTerminal(partID: 3, pinNumber: 2)),
            (collector, indicator)
        ]
        for (first, second) in connections {
            bench.select(first)
            bench.select(second)
        }
        #expect(bench.readings[indicator] == .highImpedance)

        bench.select(WorkbenchTerminal(partID: 4, pinNumber: 1))
        bench.select(collector)
        #expect(bench.readings[indicator] == .high)

        bench.toggle(baseSwitch)
        #expect(bench.isStable)
        #expect(bench.readings[indicator] == .low)

        bench.toggle(baseSwitch)
        #expect(bench.readings[indicator] == .high)
    }
}

extension WorkbenchTests {
    @Test("A resistor supplies a weak level and releases it when the source is removed")
    func resistorBias() {
        let bench = Workbench()
        let source = WorkbenchSwitch()
        let resistor = Resistor()
        bench.add("Switch", component: source)
        bench.add("Resistor", component: resistor)
        bench.add("LED", component: WorkbenchLED())

        let sourcePin = WorkbenchTerminal(partID: 1, pinNumber: 1)
        let resistorInput = WorkbenchTerminal(partID: 2, pinNumber: 1)
        let resistorOutput = WorkbenchTerminal(partID: 2, pinNumber: 2)
        let led = WorkbenchTerminal(partID: 3, pinNumber: 1)
        bench.select(sourcePin)
        bench.select(resistorInput)
        bench.select(resistorOutput)
        bench.select(led)
        bench.toggle(source)
        #expect(bench.readings[led] == .high)

        resistor.setResistance(4.7, unit: .kilohms)
        #expect(resistor.value == 4.7)
        #expect(resistor.unit == .kilohms)
        resistor.setResistance(0, unit: .megohms)
        #expect(resistor.value == 4.7)
        #expect(resistor.unit == .kilohms)

        bench.removePart(1)
        #expect(bench.isStable)
        #expect(bench.readings[led] == .highImpedance)
    }

    @Test("A 1N4148 passes a HIGH from anode to cathode and blocks reverse HIGH")
    func diodeDirection() {
        let chip = Diode1N4148()
        chip.pins[2]?.receive(.high)
        chip.evaluate()
        #expect(chip.pins[1]?.driveState == .high)

        chip.pins[2]?.receive(.highImpedance)
        chip.pins[1]?.receive(.high)
        chip.evaluate()
        #expect(chip.pins[1]?.driveState == .highImpedance)
        #expect(chip.pins[2]?.driveState == .highImpedance)

        chip.pins[1]?.receive(.low)
        chip.evaluate()
        #expect(chip.pins[2]?.driveState == .low)
    }
}

struct CD4060Tests {
    @Test("CD4060 divides falling clock edges and clears asynchronously")
    func binaryCounter() {
        let chip = CD4060()
        let clock = chip.pins[11]!
        let reset = chip.pins[12]!
        let q4 = chip.pins[7]!
        let q14 = chip.pins[3]!
        clock.receive(.low)
        reset.receive(.high)
        chip.evaluate()
        #expect(q4.driveState == .low)

        reset.receive(.low)
        chip.evaluate()
        for count in 1...16_384 {
            clock.receive(.high)
            chip.evaluate()
            #expect(q4.driveState == ((count - 1) & 8 == 0 ? .low : .high))
            clock.receive(.low)
            chip.evaluate()
            #expect(q4.driveState == (count & 8 == 0 ? .low : .high))
            #expect(q14.driveState == (count & 8192 == 0 ? .low : .high))
        }

        for _ in 0..<8 {
            clock.receive(.high)
            chip.evaluate()
            clock.receive(.low)
            chip.evaluate()
        }
        #expect(q4.driveState == .high)
        reset.receive(.high)
        chip.evaluate()
        #expect(q4.driveState == .low)
    }
}

extension WorkbenchTests {
    @Test("The clock frequency accepts fractional values and larger units")
    func clockFrequencyEntry() {
        let locale = Locale(identifier: "en_AU")
        let fractional = ClockFrequency.parse("0.5", unit: .hertz, locale: locale)
        let watchCrystal = ClockFrequency.parse("32.768", unit: .kilohertz, locale: locale)
        let megahertz = ClockFrequency.parse("32.768", unit: .megahertz, locale: locale)
        #expect(fractional?.hertz == 0.5)
        #expect(watchCrystal?.hertz == 32_768)
        #expect(megahertz?.hertz == 32_768_000)
        for invalid in ["", "0", "-1", "inf", "1e-300", "1e308"] {
            #expect(ClockFrequency.parse(invalid, unit: .megahertz, locale: locale) == nil)
        }
    }

    @Test("The +5V and GND symbols supply their logic levels to wired inputs")
    func wiredPowerRails() {
        let bench = Workbench()
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        bench.add("LED", component: WorkbenchLED())
        bench.add("LED", component: WorkbenchLED())
        let highProbe = WorkbenchTerminal(partID: 3, pinNumber: 1)
        let lowProbe = WorkbenchTerminal(partID: 4, pinNumber: 1)

        bench.select(WorkbenchTerminal(partID: 1, pinNumber: 1))
        bench.select(highProbe)
        bench.select(WorkbenchTerminal(partID: 2, pinNumber: 1))
        bench.select(lowProbe)

        #expect(bench.readings[highProbe] == .high)
        #expect(bench.readings[lowProbe] == .low)
        bench.removePart(2)
        #expect(bench.readings[lowProbe] == .highImpedance)
    }
}

extension WorkbenchTests {
    @Test("Deleting several parts removes only their attached wires")
    func removeSelectedParts() {
        let bench = Workbench()
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        for _ in 0..<3 {
            bench.add("LED", component: WorkbenchLED())
        }
        for id in 2...4 {
            bench.select(WorkbenchTerminal(partID: 1, pinNumber: 1))
            bench.select(WorkbenchTerminal(partID: id, pinNumber: 1))
        }

        bench.removeParts([2, 3])

        #expect(bench.parts.map(\.id) == [1, 4])
        #expect(bench.wires.map(\.second.partID) == [4])
        #expect(bench.readings[WorkbenchTerminal(partID: 4, pinNumber: 1)] == .high)
    }
}

struct SevenSegmentTests {
    @Test("Both drivers light a wired MAN74A and honor their latch and blanking controls")
    func wiredDisplay() {
        for is4511 in [true, false] {
            let driver = SevenSegmentDriver(is4511 ? .cd4511 : .cd4543)
            let display = MAN74A()
            let engine = SimulationEngine()
            engine.addComponent(driver)
            engine.addComponent(display)

            let outputs = is4511 ? [13, 12, 11, 10, 9, 15, 14] : [9, 10, 11, 12, 13, 15, 14]
            let segments = [14, 13, 8, 7, 6, 1, 2]
            for (output, segment) in zip(outputs, segments) {
                let net = Net(name: "Segment \(segment)")
                net.connect(driver.pins[output]!)
                net.connect(display.pins[segment]!)
                engine.addNet(net)
            }
            func litPins() -> [Int] {
                segments.filter { display.isLit($0) { display.pins[$0]!.state } }
            }
            func setBCD(_ code: Int) {
                let inputs = is4511 ? [7, 1, 2, 6] : [5, 3, 2, 4]
                for (bit, number) in inputs.enumerated() {
                    driver.pins[number]!.receive(code & (1 << bit) == 0 ? .low : .high)
                }
            }

            let latch = driver.pins[is4511 ? 5 : 1]!
            let blank = driver.pins[is4511 ? 4 : 7]!
            let testOrPhase = driver.pins[is4511 ? 3 : 6]!
            latch.receive(is4511 ? .low : .high)
            blank.receive(is4511 ? .high : .low)
            testOrPhase.receive(is4511 ? .high : .low)
            setBCD(6)
            #expect(engine.settle())
            #expect(litPins().isEmpty)
            display.pins[12]!.receive(.low)
            let six = is4511 ? [8, 7, 6, 1, 2] : [14, 8, 7, 6, 1, 2]
            #expect(litPins() == six)

            latch.receive(is4511 ? .high : .low)
            setBCD(9)
            #expect(engine.settle())
            #expect(litPins() == six)

            blank.receive(is4511 ? .low : .high)
            #expect(engine.settle())
            #expect(litPins().isEmpty)

            testOrPhase.receive(is4511 ? .low : .high)
            #expect(engine.settle())
            #expect(litPins() == segments)

            blank.receive(is4511 ? .high : .low)
            testOrPhase.receive(is4511 ? .high : .low)
            latch.receive(is4511 ? .low : .high)
            #expect(engine.settle())
            #expect(litPins() == (is4511 ? [14, 13, 8, 1, 2] : [14, 13, 8, 7, 1, 2]))

            setBCD(10)
            #expect(engine.settle())
            #expect(litPins().isEmpty)
        }
    }
}

extension WorkbenchTests {
    @Test("Undo restores a deleted part, its layout, settings, and working connection")
    func undoPartDeletion() {
        let bench = Workbench()
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("LED", component: WorkbenchLED())
        let position = CGPoint(x: 140, y: 90)
        let input = WorkbenchTerminal(partID: 2, pinNumber: 1)
        bench.placeNewPart(2, at: position)
        bench.rotatePart(2, by: 1)
        bench.setLEDColour(.blue, for: 2)
        bench.select(WorkbenchTerminal(partID: 1, pinNumber: 1))
        bench.addBend(at: position)
        bench.select(input)

        bench.removePart(2)
        #expect(bench.wires.isEmpty)
        bench.undo()
        #expect(bench.parts.map(\.id) == [1, 2])
        #expect(bench.positions[2] == position)
        #expect(bench.rotations[2] == 1)
        #expect(bench.ledColours[2] == .blue)
        #expect(bench.wires.first?.bends == [position])
        #expect(bench.readings[input] == .high)

        bench.redo()
        #expect(bench.parts.map(\.id) == [1])
        #expect(bench.wires.isEmpty)
        bench.undo()
        bench.setLEDColour(.red, for: 2)
        #expect(!bench.canRedo)
        bench.undo()
        #expect(bench.ledColours[2] == .blue)
    }
}

extension WorkbenchTests {
    @Test("A wire junction connects all branches and survives a Workbench file round trip")
    func junctionArchiveRoundTrip() throws {
        let bench = Workbench()
        bench.add("Logic Input", component: WorkbenchSwitch(showsValue: true))
        bench.add("LED", component: WorkbenchLED())
        bench.add("LED", component: WorkbenchLED())
        bench.addNextUnit(for: .and)
        bench.addNextUnit(for: .and)
        bench.toggle(try #require(bench.parts[0].component as? WorkbenchSwitch))
        bench.setLEDColour(.blue, for: 3)
        let source = WorkbenchTerminal(partID: 1, pinNumber: 1)
        let first = WorkbenchTerminal(partID: 2, pinNumber: 1)
        let second = WorkbenchTerminal(partID: 3, pinNumber: 1)
        let point = CGPoint(x: 200, y: 140)
        bench.placeNewPart(3, at: point)
        bench.rotatePart(3, by: 1)
        bench.select(source)
        bench.select(first)
        bench.select(second)
        bench.joinWire(1, at: point, before: [], after: [])
        #expect(bench.readings[second] == .high)
        bench.undo()
        #expect(bench.readings[second] == .highImpedance)
        bench.redo()
        #expect(bench.readings[second] == .high)

        let data = try JSONEncoder().encode(WorkbenchArchive(bench: bench))
        let archive = try JSONDecoder().decode(WorkbenchArchive.self, from: data)
        let reopened = Workbench()
        try reopened.open(archive)
        #expect(reopened.wires.count == 3)
        #expect(reopened.junctions.values.contains(point))
        #expect(reopened.readings[first] == .high)
        #expect(reopened.readings[second] == .high)
        #expect(reopened.parts[3].component === reopened.parts[4].component)
        #expect(reopened.positions[3] == point)
        #expect(reopened.rotations[3] == 1)
        #expect(reopened.ledColours[3] == .blue)
    }
}
