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
