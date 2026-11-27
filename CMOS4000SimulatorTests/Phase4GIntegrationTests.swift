import Foundation
import Testing
@testable import CMOS4000Simulator

@MainActor
private final class WiredWorkbench {
    let bench = Workbench(timeSource: { 0 })
    let vdd: Int
    let ground: Int

    init(_ mode: PowerMode) {
        bench.setPowerMode(mode)
        bench.add("+5 V", component: WorkbenchPower(.fiveVolts))
        vdd = bench.parts.last!.id
        bench.add("Ground", component: WorkbenchPower(.ground))
        ground = bench.parts.last!.id
    }

    func add(_ name: String, _ component: any LogicComponent) -> Int {
        bench.add(name, component: component)
        return bench.parts.last!.id
    }

    func terminal(_ part: Int, _ pin: Int) -> WorkbenchTerminal {
        WorkbenchTerminal(partID: part, pinNumber: pin)
    }

    func wire(_ source: Int, _ output: Int, _ receiver: Int, _ input: Int) {
        bench.select(terminal(source, output))
        bench.select(terminal(receiver, input))
    }

    func power(_ part: Int, vdd pin: Int = 16, vss: Int = 8) {
        guard bench.powerMode == .explicit else { return }
        wire(vdd, 1, part, pin)
        wire(ground, 1, part, vss)
    }

    func level(_ part: Int, _ pin: Int) -> LogicState? {
        bench.readings[terminal(part, pin)]
    }

    // Fixed virtual time makes Workbench's event cap the only batching constraint.
    func advance(to target: Double) -> Bool {
        while bench.servicedTime < target {
            let before = bench.servicedTime
            bench.serviceSimulation(until: target)
            guard bench.isStable, bench.servicedTime > before else { return false }
        }
        return bench.servicedTime == target
    }
}

@MainActor
private struct DisplayPath {
    static let glyphs4511 = ["abcdef", "bc", "abdeg", "abcdg", "bcfg",
                             "acdfg", "cdefg", "abc", "abcdefg", "abcfg"]
    static let glyphs4543 = ["abcdef", "bc", "abdeg", "abcdg", "bcfg",
                             "acdfg", "acdefg", "abc", "abcdefg", "abcdfg"]

    let display: SevenSegmentDisplay
    let displayID: Int
    let driverID: Int
    let commonAnode: Bool

    init(_ circuit: WiredWorkbench, label: String, commonAnode: Bool, downstreamFirst: Bool = false) {
        self.commonAnode = commonAnode
        let kind: SevenSegmentDriverKind = commonAnode ? .cd4543 : .cd4511
        let driver = SevenSegmentDriver(kind)
        display = commonAnode ? MAN72A() : MAN74A()
        if downstreamFirst {
            displayID = circuit.add("\(label) display", display)
            driverID = circuit.add("\(label) decoder", driver)
        } else {
            driverID = circuit.add("\(label) decoder", driver)
            displayID = circuit.add("\(label) display", display)
        }
        circuit.power(driverID)
        // Transparent, unblanked, with output polarity matched to the display.
        let controls = commonAnode ? [(1, true), (6, true), (7, false)]
                                  : [(3, true), (4, true), (5, false)]
        for (pin, high) in controls {
            circuit.wire(high ? circuit.vdd : circuit.ground, 1, driverID, pin)
        }
        for (output, input) in zip(kind.outputs, display.segmentNumbers) {
            circuit.wire(driverID, output, displayID, input)
        }
        for pin in display.commonNumbers {
            circuit.wire(commonAnode ? circuit.vdd : circuit.ground, 1, displayID, pin)
        }
    }

    func wireInputs(from source: Int, pins: [Int], in circuit: WiredWorkbench) {
        let kind: SevenSegmentDriverKind = commonAnode ? .cd4543 : .cd4511
        for (output, input) in zip(pins, kind.inputs) {
            circuit.wire(source, output, driverID, input)
        }
    }

    func expect(_ digit: Int, in circuit: WiredWorkbench,
                sourceLocation: SourceLocation = #_sourceLocation) {
        let glyph = (commonAnode ? Self.glyphs4543 : Self.glyphs4511)[digit]
        expectSegments("abcdefg".map { glyph.contains($0) ? "1" : "0" }.joined(),
                       in: circuit, sourceLocation: sourceLocation)
    }

    func expectSegments(_ pattern: String, in circuit: WiredWorkbench,
                        sourceLocation: SourceLocation = #_sourceLocation) {
        for (pin, segment) in zip(display.segmentNumbers, pattern) {
            let expected: LogicState = segment == "X" ? .undefined
                : (segment == "1") != commonAnode ? .high : .low
            #expect(circuit.level(displayID, pin) == expected, sourceLocation: sourceLocation)
            #expect(display.isLit(pin) { circuit.level(displayID, $0) ?? .highImpedance } == (segment == "1"),
                    sourceLocation: sourceLocation)
        }
    }
}

@MainActor
private struct DisplayDigit {
    let counter = CD4510()
    let counterID: Int
    let display: DisplayPath

    init(_ circuit: WiredWorkbench, label: String, downstreamFirst: Bool, commonAnode: Bool) {
        if downstreamFirst {
            display = DisplayPath(circuit, label: label, commonAnode: commonAnode, downstreamFirst: true)
            counterID = circuit.add("\(label) counter", counter)
        } else {
            counterID = circuit.add("\(label) counter", counter)
            display = DisplayPath(circuit, label: label, commonAnode: commonAnode)
        }
        circuit.power(counterID)
        circuit.wire(circuit.ground, 1, counterID, 1)
        display.wireInputs(from: counterID, pins: [6, 11, 14, 2], in: circuit)
    }

    func expect(_ digit: Int, in circuit: WiredWorkbench, sourceLocation: SourceLocation) {
        #expect(counter.count == digit, sourceLocation: sourceLocation)
        display.expect(digit, in: circuit, sourceLocation: sourceLocation)
    }
}

@MainActor
private struct ClockDisplayCircuit {
    static let crystalHz = 32_768.0
    let circuit: WiredWorkbench
    let clock = WorkbenchClock()
    let reset = WorkbenchSwitch()
    let direction = WorkbenchSwitch()
    let clockID: Int
    let resetID: Int
    let ones: DisplayDigit
    let tens: DisplayDigit
    let dividerID: Int?
    let jkID: Int?

    var bench: Workbench { circuit.bench }

    init(_ mode: PowerMode, crystal: Bool, downstreamFirst: Bool = false) {
        let circuit = WiredWorkbench(mode)
        self.circuit = circuit
        clockID = circuit.add("Clock Source", clock)
        resetID = circuit.add("Reset", reset)
        let directionID = circuit.add("Count up", direction)
        if downstreamFirst {
            tens = DisplayDigit(circuit, label: "Tens", downstreamFirst: true, commonAnode: true)
            ones = DisplayDigit(circuit, label: "Ones", downstreamFirst: true, commonAnode: false)
        } else {
            ones = DisplayDigit(circuit, label: "Ones", downstreamFirst: false, commonAnode: false)
            tens = DisplayDigit(circuit, label: "Tens", downstreamFirst: false, commonAnode: true)
        }
        let countClock: Int
        if crystal {
            let divider = circuit.add("CD4060", CD4060())
            let jk = circuit.add("CD4027", CD4027())
            dividerID = divider
            jkID = jk
            circuit.power(divider)
            circuit.power(jk)
            circuit.wire(clockID, 1, divider, 11)
            circuit.wire(resetID, 1, divider, 12)
            circuit.wire(divider, 3, jk, 3)
            circuit.wire(resetID, 1, jk, 4)
            circuit.wire(circuit.vdd, 1, jk, 5)
            circuit.wire(circuit.vdd, 1, jk, 6)
            circuit.wire(circuit.ground, 1, jk, 7)
            countClock = jk
        } else {
            dividerID = nil
            jkID = nil
            countClock = clockID
        }
        for digit in [ones, tens] {
            circuit.wire(countClock, 1, digit.counterID, 15)
            circuit.wire(resetID, 1, digit.counterID, 9)
            circuit.wire(directionID, 1, digit.counterID, 10)
        }
        circuit.wire(circuit.ground, 1, ones.counterID, 5)
        circuit.wire(ones.counterID, 7, tens.counterID, 5)
        bench.toggle(direction)
        bench.toggle(reset)
        bench.toggle(reset)
    }

    func expect(_ value: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(bench.isStable, sourceLocation: sourceLocation)
        ones.expect(value % 10, in: circuit, sourceLocation: sourceLocation)
        tens.expect(value / 10, in: circuit, sourceLocation: sourceLocation)
    }

    func pulse() {
        bench.advanceClock(clock)
        bench.advanceClock(clock)
    }
}

@MainActor
struct Phase4GIntegrationTests {
    @Test(arguments: [PowerMode.explicit, .automatic])
    func crystalThroughDisplayedCount(mode: PowerMode) throws {
        let fixture = ClockDisplayCircuit(mode, crystal: true)
        let divider = try #require(fixture.dividerID)
        let jk = try #require(fixture.jkID)
        let halfPeriod = 0.5 / ClockDisplayCircuit.crystalHz
        fixture.expect(0)
        fixture.bench.runClock(fixture.clock, hertz: ClockDisplayCircuit.crystalHz)

        // Q14 changes every quarter second. The JK toggles only on Q14 rising.
        // The two observed JK rising edges are exactly one simulated second apart.
        let expected: [(Double, LogicState, LogicState, Int)] = [
            (0, .low, .low, 0), (0.25, .high, .high, 1), (0.5, .low, .high, 1),
            (0.75, .high, .low, 1), (1, .low, .low, 1), (1.25, .high, .high, 2)
        ]
        for (previous, next) in zip(expected, expected.dropFirst()) {
            try #require(fixture.circuit.advance(to: next.0 - halfPeriod))
            #expect(fixture.clock.phase == .high)
            #expect(fixture.circuit.level(divider, 3) == previous.1)
            #expect(fixture.circuit.level(jk, 1) == previous.2)
            fixture.expect(previous.3)
            try #require(fixture.circuit.advance(to: next.0))
            #expect(fixture.clock.phase == .low)
            #expect(fixture.circuit.level(divider, 3) == next.1)
            #expect(fixture.circuit.level(jk, 1) == next.2)
            fixture.expect(next.3)
        }
    }

    @Test(arguments: [PowerMode.explicit, .automatic], [false, true])
    func completeDisplayedRollover(mode: PowerMode, downstreamFirst: Bool) {
        let fixture = ClockDisplayCircuit(mode, crystal: false, downstreamFirst: downstreamFirst)
        fixture.expect(0)
        for step in 1...100 {
            fixture.bench.advanceClock(fixture.clock)
            fixture.expect(step % 100)
            fixture.bench.advanceClock(fixture.clock)
            fixture.expect(step % 100)
        }
        fixture.bench.toggle(fixture.direction)
        fixture.expect(0)
        for step in 1...101 {
            fixture.bench.advanceClock(fixture.clock)
            fixture.expect((200 - step) % 100)
            fixture.bench.advanceClock(fixture.clock)
            fixture.expect((200 - step) % 100)
        }
    }

    @Test func poweredResetRestoresBothDisplays() throws {
        let fixture = ClockDisplayCircuit(.explicit, crystal: false)
        let circuit = fixture.circuit
        for _ in 0..<11 { fixture.pulse() }
        fixture.expect(11)
        let supply = circuit.terminal(circuit.vdd, 1)
        let receiver = circuit.terminal(fixture.ones.counterID, 16)
        let wire = try #require(fixture.bench.wires.first {
            $0.first == supply && $0.second == receiver || $0.first == receiver && $0.second == supply
        })
        fixture.bench.removeWire(wire.id)
        #expect(fixture.ones.counter.powerState == .disconnected)
        fixture.ones.display.expectSegments("XXXXXXX", in: circuit)
        circuit.wire(circuit.vdd, 1, fixture.ones.counterID, 16)
        #expect(fixture.ones.counter.count == nil)
        fixture.ones.display.expectSegments("XXXXXXX", in: circuit)
        fixture.bench.toggle(fixture.reset)
        fixture.expect(0)
        fixture.bench.toggle(fixture.reset)
        fixture.pulse()
        fixture.expect(1)
    }

    @Test(arguments: [PowerMode.explicit, .automatic])
    func archiveKeepsConfigurationAndReinitializesClockAndCount(mode: PowerMode) throws {
        let fixture = ClockDisplayCircuit(mode, crystal: false)
        let frequency = ClockFrequency(value: 32.768, unit: .kilohertz)
        fixture.bench.setClockFrequency(frequency, for: fixture.clockID)
        for _ in 0..<11 { fixture.pulse() }
        fixture.expect(11)
        fixture.bench.runClock(fixture.clock, hertz: frequency.hertz)
        try #require(fixture.circuit.advance(to: 0.5 / frequency.hertz))
        fixture.expect(12)
        #expect(fixture.clock.phase == .high)

        let saved = try WorkbenchArchive(bench: fixture.bench).encoded()
        let reopened = Workbench(timeSource: { 0 })
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: saved))
        #expect(try WorkbenchArchive(bench: reopened).encoded() == saved)
        #expect(reopened.powerMode == mode)
        #expect(reopened.clockFrequencies[fixture.clockID] == frequency)
        #expect(!reopened.hasRunningClocks)
        let clock = try #require(reopened.parts.first { $0.id == fixture.clockID }?.component as? WorkbenchClock)
        #expect(clock.phase == .low)
        let counters = reopened.parts.compactMap { $0.component as? CD4510 }
        #expect(counters.count == 2)
        // CD4510 initializes at zero when created by archive restoration.
        #expect(counters.allSatisfy { $0.count == 0 })
        let reset = try #require(reopened.parts.first { $0.id == fixture.resetID }?.component as? WorkbenchSwitch)
        reopened.toggle(reset)
        reopened.toggle(reset)
        #expect(counters.allSatisfy { $0.count == 0 })
        reopened.advanceClock(clock)
        let ones = try #require(reopened.parts.first { $0.id == fixture.ones.counterID }?.component as? CD4510)
        #expect(ones.count == 1)
    }
}

@MainActor
struct Phase4GTTLIntegrationTests {
    private enum Wiring {
        case independent, cascade, biQuinary
    }

    private func verifyDivider(_ kind: CounterChip, mode: PowerMode, wiring: Wiring) {
        let circuit = WiredWorkbench(mode)
        let chip = circuit.add(kind.rawValue, SN74LSCounter(kind))
        let a = WorkbenchClock()
        let b = WorkbenchClock()
        let aID = circuit.add("Clock A", a)
        let bID = circuit.add("Clock B", b)
        let reset = WorkbenchSwitch()
        let resetID = circuit.add("Reset", reset)
        let outputs = kind == .ls92 ? [12, 11, 9, 8] : [12, 9, 8, 11]
        let highBits = kind == .ls90 ? [0, 2, 4, 6, 8]
                       : kind == .ls92 ? [0, 2, 4, 8, 10, 12] : Array(stride(from: 0, to: 16, by: 2))

        circuit.power(chip, vdd: 5, vss: 10)
        for pin in kind == .ls92 ? [6, 7] : [2, 3] { circuit.wire(resetID, 1, chip, pin) }
        if kind == .ls90 {
            for pin in [6, 7] { circuit.wire(circuit.ground, 1, chip, pin) }
        }
        switch wiring {
        case .independent:
            circuit.wire(aID, 1, chip, 14)
            circuit.wire(bID, 1, chip, 1)
        case .cascade:
            circuit.wire(aID, 1, chip, 14)
            circuit.wire(chip, 12, chip, 1)
        case .biQuinary:
            circuit.wire(bID, 1, chip, 1)
            circuit.wire(chip, 11, chip, 14)
        }
        circuit.bench.toggle(reset)
        circuit.bench.toggle(reset)

        func expectWord(_ word: Int, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(circuit.bench.isStable, sourceLocation: sourceLocation)
            let actual = outputs.map { circuit.level(chip, $0) }
            let expected: [LogicState?] = (0..<4).map { word & (1 << $0) == 0 ? .low : .high }
            #expect(actual == expected, sourceLocation: sourceLocation)
        }

        func sweep(_ pattern: [Int], clock: WorkbenchClock) {
            for index in pattern.indices {
                circuit.bench.advanceClock(clock)
                expectWord(pattern[index])
                circuit.bench.advanceClock(clock)
                expectWord(pattern[(index + 1) % pattern.count])
            }
        }

        switch wiring {
        case .independent:
            sweep([0, 1], clock: a)
            circuit.bench.advanceClock(a)
            circuit.bench.advanceClock(a)
            sweep(highBits.map { $0 | 1 }, clock: b)
        case .cascade:
            let pattern = highBits.flatMap { [$0, $0 | 1] }
            sweep(pattern + pattern, clock: a)
        case .biQuinary:
            // QA stays low for five input periods and high for five.
            let pattern = [0, 2, 4, 6, 8, 1, 3, 5, 7, 9]
            sweep(pattern + pattern, clock: b)
        }
    }

    @Test(arguments: [CounterChip.ls90, .ls92, .ls93], [PowerMode.explicit, .automatic])
    func independentAndCascadedDividers(kind: CounterChip, mode: PowerMode) {
        verifyDivider(kind, mode: mode, wiring: .independent)
        verifyDivider(kind, mode: mode, wiring: .cascade)
    }

    @Test(arguments: [PowerMode.explicit, .automatic])
    func biQuinaryDivider(mode: PowerMode) {
        verifyDivider(.ls90, mode: mode, wiring: .biQuinary)
    }

    @Test(arguments: [PowerMode.explicit, .automatic], [false, true])
    func idealCMOSAndTTLInteropWithUncertainPreset(mode: PowerMode, downstreamFirst: Bool) throws {
        let circuit = WiredWorkbench(mode)
        let inverter = CD40106()
        let ttl = SN74LSCounter(.ls90)
        let clock = WorkbenchClock()
        let clockID = circuit.add("Clock source", clock)
        let inverterID: Int
        let ttlID: Int
        let display: DisplayPath
        if downstreamFirst {
            display = DisplayPath(circuit, label: "TTL", commonAnode: false, downstreamFirst: true)
            ttlID = circuit.add("SN74LS90", ttl)
            inverterID = circuit.add("CD40106", inverter)
        } else {
            inverterID = circuit.add("CD40106", inverter)
            ttlID = circuit.add("SN74LS90", ttl)
            display = DisplayPath(circuit, label: "TTL", commonAnode: false)
        }
        circuit.power(inverterID, vdd: 14, vss: 7)
        circuit.power(ttlID, vdd: 5, vss: 10)
        circuit.wire(clockID, 1, inverterID, 1)
        circuit.wire(inverterID, 2, ttlID, 14)
        circuit.wire(ttlID, 12, ttlID, 1)
        display.wireInputs(from: ttlID, pins: [12, 9, 8, 11], in: circuit)

        let reset = WorkbenchSwitch()
        let resetID = circuit.add("Reset to zero", reset)
        let preset = WorkbenchSwitch()
        let presetID = circuit.add("Preset to nine", preset)
        for pin in [2, 3] { circuit.wire(resetID, 1, ttlID, pin) }
        circuit.wire(presetID, 1, ttlID, 6) // Pin 7 is open.
        circuit.bench.toggle(reset)
        circuit.bench.toggle(reset)
        display.expect(0, in: circuit)
        for expected in 1...10 {
            circuit.bench.advanceClock(clock)
            #expect(circuit.level(ttlID, 14) == .low)
            display.expect(expected % 10, in: circuit)
            circuit.bench.advanceClock(clock)
            #expect(circuit.level(ttlID, 14) == .high)
            display.expect(expected % 10, in: circuit)
        }

        // Isolate the ripple link so both clock receivers stay definite
        // while testing uncertainty at the data inputs of the decoder.
        let qa = circuit.terminal(ttlID, 12)
        let ckb = circuit.terminal(ttlID, 1)
        let ripple = try #require(circuit.bench.wires.first { $0.first == qa && $0.second == ckb })
        circuit.bench.removeWire(ripple.id)
        circuit.wire(circuit.ground, 1, ttlID, 1)
        circuit.bench.toggle(reset)
        circuit.bench.toggle(preset)
        let unconnected = WorkbenchSwitch()
        // Reset/preset admit 0 or 9. The receiving decoder sees X00X and
        // preserves b and c across all its resulting candidate BCD words.
        for _ in 0..<3 {
            circuit.bench.toggle(unconnected)
            #expect(circuit.bench.isStable)
            #expect(circuit.level(ttlID, 14) == .high)
            #expect(circuit.level(ttlID, 1) == .low)
            #expect(circuit.level(ttlID, 12) == .undefined)
            #expect(circuit.level(ttlID, 9) == .low)
            #expect(circuit.level(ttlID, 8) == .low)
            #expect(circuit.level(ttlID, 11) == .undefined)
            display.expectSegments("X11XXXX", in: circuit)
        }
        circuit.bench.toggle(preset)
        display.expect(0, in: circuit)
        circuit.bench.toggle(reset)
        circuit.bench.advanceClock(clock)
        display.expect(1, in: circuit)
    }
}

// Invoked by the standalone benchmark runner documented in PROJECT_STATUS.md.
@MainActor
enum Phase4GThroughput {
    static func measure() throws -> [Double] {
        let clock = ContinuousClock()
        let elapsedTarget = 1.0
        var seconds: [Double] = []
        for run in 0...5 {
            let fixture = ClockDisplayCircuit(.explicit, crystal: true)
            fixture.bench.runClock(fixture.clock, hertz: ClockDisplayCircuit.crystalHz)
            let start = clock.now
            let completed = fixture.circuit.advance(to: elapsedTarget)
            let elapsed = start.duration(to: clock.now).components
            guard completed else { throw MeasurementError.incompleteSimulation }
            if run > 0 {
                seconds.append(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
            }
        }
        return seconds
    }

    private enum MeasurementError: Error {
        case incompleteSimulation
    }
}
