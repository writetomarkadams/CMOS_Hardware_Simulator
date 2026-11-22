import Foundation
import Testing
@testable import CMOS4000Simulator

struct OscilloscopeTests {
    @Test func boundedHistoryKeepsChronologyAndWindowBoundarySamples() {
        var history = ScopeHistory(capacity: 4)
        #expect(history.visible(in: 0...1).isEmpty)
        for index in 0..<9 {
            history.append(.init(time: Double(index), value: .logic(index.isMultiple(of: 2) ? .low : .high)))
        }
        history.append(.init(time: 9, value: .logic(.low)))
        history.append(.init(time: 7, value: .logic(.high)))
        #expect(history.visible(in: 0...10).map(\.time) == [5, 6, 7, 8])
        #expect(history.visible(in: 6.5...7.5).map(\.time) == [6, 7, 8])
        #expect(history.visible(in: 7...7).map(\.time) == [6, 7, 8])
        #expect(history.visible(in: 9...10).map(\.time) == [8])
    }

    @Test func rollingWindowContinuesThroughEdgesUntilManuallyFrozen() {
        let scope = Oscilloscope()
        scope.setSpan(4)
        for tick in 0...20 {
            scope.capture(at: Double(tick)) { _ in
                .logic(tick.isMultiple(of: 2) ? .low : .high)
            }
        }
        #expect(scope.running)
        #expect(scope.window == 16...20)
        #expect(scope.samples(channel: 0, in: scope.window).map(\.time) == [15, 16, 17, 18, 19, 20])

        scope.setRunning(false)
        scope.capture(at: 21) { _ in .logic(.high) }
        #expect(scope.window == 16...20)
        scope.setSpan(2)
        #expect(scope.window == 18...20)

        scope.setRunning(true)
        scope.capture(at: 22) { _ in .logic(.low) }
        #expect(scope.running)
        #expect(scope.window == 20...22)
        #expect(scope.samples(channel: 0, in: scope.window).map(\.time) == [22])
    }

    @Test func pinAndWireProbesCaptureEveryScheduledEdgeAndRoundTrip() throws {
        let bench = Workbench(timeSource: { 0 })
        let clock = WorkbenchClock()
        bench.add("Clock", component: clock)
        bench.add("LED", component: WorkbenchLED())
        let output = WorkbenchTerminal(partID: 1, pinNumber: 1)
        bench.select(output)
        bench.select(WorkbenchTerminal(partID: 2, pinNumber: 1))
        let wire = try #require(bench.wires.first)
        bench.assignScopeProbe(.pin(output), to: 0)
        bench.assignScopeProbe(.wire(wire.id), to: 3)
        bench.assignScopeProbe(.wire(999), to: 1)
        bench.assignScopeProbe(.pin(output), to: 4)
        bench.runClock(clock, hertz: 1000)
        bench.serviceSimulation(until: 0.010)
        let times = bench.scope.samples(channel: 0, in: 0...1).map(\.time)
        #expect(times == (0...20).map { Double($0) * 0.0005 })
        #expect(bench.scope.samples(channel: 0, in: 0...1) == bench.scope.samples(channel: 3, in: 0...1))
        #expect(bench.scopeProbes.count == 2)

        bench.scope.setRunning(false)
        bench.serviceSimulation(until: 0.020)
        #expect(bench.scope.time == 0.010)
        #expect(bench.servicedTime == 0.020)

        let saved = try JSONEncoder().encode(WorkbenchArchive(bench: bench))
        let loaded = Workbench(timeSource: { 0 })
        try loaded.open(JSONDecoder().decode(WorkbenchArchive.self, from: saved))
        #expect(loaded.scopeProbes == [0: .pin(output), 3: .wire(wire.id)])
        #expect(!loaded.hasRunningClocks)
        loaded.removeWire(wire.id)
        #expect(loaded.scopeProbes == [0: .pin(output)])
        loaded.undo()
        #expect(loaded.scopeProbes == bench.scopeProbes)
        loaded.clear()
        #expect(loaded.scopeProbes.isEmpty)
    }


    @Test func canvasPlacementUsesLowestFreeChannelAndPreservesConnectivity() throws {
        let bench = Workbench(timeSource: { 0 })
        let clock = WorkbenchClock()
        bench.add("Clock", component: clock)
        bench.add("LED", component: WorkbenchLED())
        let output = WorkbenchTerminal(partID: 1, pinNumber: 1)
        let input = WorkbenchTerminal(partID: 2, pinNumber: 1)
        bench.select(output)
        bench.select(input)
        let wire = try #require(bench.wires.first)
        let originalNet = try #require(bench.circuitNet(at: output))
        let wireProbe = ScopeProbe.wirePoint(id: wire.id, fraction: 0.25)
        let pinProbe = ScopeProbe.netPin(input)
        let placements = [wireProbe, pinProbe, wireProbe, pinProbe]

        for (channel, probe) in placements.enumerated() {
            #expect(bench.nextScopeChannel == channel)
            #expect(bench.placeScopeProbe(probe))
            #expect(bench.scopeProbes[channel] == probe)
            #expect(!bench.scope.samples(channel: channel, in: bench.scope.window).isEmpty)
            #expect(bench.scopeNet(for: probe) === originalNet)
        }
        #expect(bench.nextScopeChannel == nil)
        #expect(!bench.placeScopeProbe(.netPin(output)))
        #expect(bench.scopeProbes[0] == wireProbe)
        #expect(bench.placeScopeProbe(.netPin(output), moving: 2))
        #expect(bench.scopeProbes[2] == .netPin(output))
        bench.assignScopeProbe(nil, to: 1)
        #expect(!bench.placeScopeProbe(pinProbe, moving: 1))
        #expect(bench.nextScopeChannel == 1)
        #expect(bench.placeScopeProbe(pinProbe))

        #expect(bench.wires.map(\.id) == [wire.id])
        #expect(bench.junctions.isEmpty)
        #expect(bench.circuitNet(at: input) === originalNet)
        bench.runClock(clock, hertz: 1000)
        bench.serviceSimulation(until: 0.002)
        let trace = bench.scope.samples(channel: 0, in: 0...1)
        #expect(trace.map(\.value) == [.logic(.low), .logic(.high), .logic(.low), .logic(.high), .logic(.low)])
        for channel in 1...3 {
            #expect(bench.scope.samples(channel: channel, in: 0...1) == trace)
        }
    }

    @Test func canvasProbesFollowWireSplitAndSurvivingNetThroughArchive() throws {
        let bench = Workbench(timeSource: { 0 })
        bench.add("Clock", component: WorkbenchClock())
        bench.add("LED", component: WorkbenchLED())
        bench.add("LED", component: WorkbenchLED())
        let output = WorkbenchTerminal(partID: 1, pinNumber: 1)
        let firstInput = WorkbenchTerminal(partID: 2, pinNumber: 1)
        let secondInput = WorkbenchTerminal(partID: 3, pinNumber: 1)
        bench.select(output)
        bench.select(firstInput)
        let wireID = try #require(bench.wires.first?.id)
        #expect(bench.placeScopeProbe(.wirePoint(id: wireID, fraction: 0.75)))
        #expect(bench.placeScopeProbe(.wirePoint(id: wireID, fraction: 0.5)))
        bench.select(secondInput)
        bench.joinWire(wireID, at: CGPoint(x: 200, y: 100), before: [], after: [], splitFraction: 0.5)
        let junctionID = try #require(bench.junctions.keys.first)
        let junction = WorkbenchTerminal.junction(junctionID)
        let branch = try #require(bench.wires.first { $0.second == firstInput })
        #expect(bench.scopeProbes == [0: .wirePoint(id: branch.id, fraction: 0.5), 1: .netPin(junction)])
        #expect(bench.placeScopeProbe(.netPin(firstInput)))
        bench.placeNewPart(2, at: CGPoint(x: 300, y: 100))
        bench.movePart(2, from: CGPoint(x: 300, y: 100), to: CGPoint(x: 400, y: 160))

        let loaded = Workbench(timeSource: { 0 })
        let encoded = try WorkbenchArchive(bench: bench).encoded()
        try loaded.open(JSONDecoder().decode(WorkbenchArchive.self, from: encoded))
        #expect(loaded.scopeProbes == bench.scopeProbes)
        let net = try #require(loaded.circuitNet(at: output))
        for probe in loaded.scopeProbes.values { #expect(loaded.scopeNet(for: probe) === net) }

        loaded.removeWire(branch.id)
        #expect(loaded.scopeProbes == [0: .netPin(junction), 1: .netPin(junction)])
        for id in loaded.wires.map(\.id) { loaded.removeWire(id) }
        #expect(loaded.scopeProbes.isEmpty)
        #expect(loaded.nextScopeChannel == 0)
        #expect(loaded.scope.samples(channel: 0, in: loaded.scope.window).isEmpty)
    }
    @Test func reopenedCounterCircuitLatchesBriefPresetPulse() throws {
        let original = Workbench(timeSource: { 0 })
        original.add("Clock", component: WorkbenchClock())
        original.add("Ground", component: WorkbenchPower(.ground))
        original.add("+5 V", component: WorkbenchPower(.fiveVolts))
        original.add("CD4510", component: CD4510())
        original.addUnit(MultiUnitChip.and.units[0], kind: .and)

        func wire(_ firstPart: Int, _ firstPin: Int, _ secondPart: Int, _ secondPin: Int) {
            original.select(WorkbenchTerminal(partID: firstPart, pinNumber: firstPin))
            original.select(WorkbenchTerminal(partID: secondPart, pinNumber: secondPin))
        }
        for pin in [3, 4, 5, 9, 12, 13] { wire(2, 1, 4, pin) }
        wire(3, 1, 4, 10)
        wire(1, 1, 4, 15)
        wire(4, 14, 5, 1)
        wire(4, 11, 5, 2)
        wire(5, 3, 4, 1)

        let saved = try JSONEncoder().encode(WorkbenchArchive(bench: original))
        let loaded = Workbench(timeSource: { 0 })
        try loaded.open(JSONDecoder().decode(WorkbenchArchive.self, from: saved))
        #expect(loaded.scopeProbes.isEmpty)
        let clock = try #require(loaded.parts.first?.component as? WorkbenchClock)
        let output = WorkbenchTerminal(partID: 5, pinNumber: 3)
        let feedbackWire = try #require(loaded.wires.first { $0.first == output || $0.second == output })
        loaded.assignScopeProbe(.pin(output), to: 0)
        loaded.assignScopeProbe(.wire(feedbackWire.id), to: 2)

        for _ in 0..<2 {
            for _ in 0..<5 {
                loaded.advanceClock(clock)
                loaded.advanceClock(clock)
                #expect(loaded.scope.pulseSeenChannels.isEmpty)
            }
            loaded.advanceClock(clock)
            #expect(loaded.circuitNet(at: output)?.state == .low)
            #expect(loaded.scope.pulseSeenChannels == [0, 2])
            loaded.advanceClock(clock)
            #expect(loaded.scope.pulseSeenChannels == [0, 2])
            loaded.scope.clear()
            #expect(loaded.scope.pulseSeenChannels.isEmpty)
        }
    }

    @Test func clearingPulseOnHighWaitsForTheNextRisingEdge() {
        let scope = Oscilloscope()
        scope.primePulse(channel: 0, level: .high)
        scope.observePulse(channel: 0, level: .high)
        #expect(scope.pulseSeenChannels.isEmpty)
        scope.observePulse(channel: 0, level: .low)
        scope.observePulse(channel: 0, level: .high)
        #expect(scope.pulseSeenChannels == [0])

        scope.clear()
        scope.observePulse(channel: 0, level: .high)
        #expect(scope.pulseSeenChannels.isEmpty)
        scope.setRunning(false)
        scope.observePulse(channel: 0, level: .low)
        scope.observePulse(channel: 0, level: .high)
        scope.setRunning(true)
        scope.observePulse(channel: 0, level: .high)
        #expect(scope.pulseSeenChannels.isEmpty)
        scope.observePulse(channel: 0, level: .low)
        scope.observePulse(channel: 0, level: .high)
        #expect(scope.pulseSeenChannels == [0])
        scope.reset(channel: 0)
        #expect(scope.pulseSeenChannels.isEmpty)
    }

    @Test func rcSamplesAndOutputEdgesAreAvailableDuringEngineAdvance() throws {
        // With a reversed nonpolar capacitor the timing node is on capacitor pin 2.
        let circuit = CapacitorTimingTests.Circuit(kind: .small, reverse: true)
        let engine = circuit.engine
        let timingNet = try #require(engine.nets.first { net in
            net.pins.contains { $0 === circuit.timer.pins[6] }
        })
        let outputNet = try #require(engine.nets.first { net in
            net.pins.contains { $0 === circuit.timer.pins[3] }
        })
        #expect(engine.timingVoltage(on: outputNet) == nil)
        let scope = Oscilloscope()
        let tau = 30_000 * circuit.cap.farads
        let result = engine.advanceTime(by: tau * 4) { time, stable in
            #expect(stable)
            scope.capture(at: time) { channel in
                switch channel {
                case 0: return engine.timingVoltage(on: timingNet).map(ScopeValue.voltage)
                case 1: return .logic(outputNet.state)
                default: return nil
                }
            }
        }
        let voltages = scope.samples(channel: 0, in: 0...result.elapsed)
        let output = scope.samples(channel: 1, in: 0...result.elapsed)
        #expect(voltages.first?.value == .voltage(0))
        #expect(output.prefix(3).map(\.value) == [.logic(.high), .logic(.low), .logic(.high)])
        let firstEdge = try #require(output.dropFirst().first)
        #expect(abs(firstEdge.time - tau * log(3)) < 1e-10)
        if case .voltage(let volts) = try #require(voltages.dropFirst().first).value {
            #expect(abs(volts - 10.0 / 3.0) < 1e-9)
        } else {
            Issue.record("Expected a timing-node voltage")
        }
    }
}
