import Testing
@testable import CMOS4000Simulator

struct CorrelatedClockHistoryTests {
    private static let levels: [LogicState] = [.low, .high, .undefined, .highImpedance]
    private static let transitions: [[Set<ClockSampleTransition>]] = [
        [[.hold], [.rising], [.hold, .rising], [.hold, .rising]],
        [[.falling], [.hold], [.hold, .falling], [.hold, .falling]],
        [[.hold, .falling], [.hold, .rising], [.hold, .rising, .falling], [.hold, .rising, .falling]],
        [[.hold, .falling], [.hold, .rising], [.hold, .rising, .falling], [.hold, .rising, .falling]]
    ]

    @Test(arguments: 0..<4, 0..<4)
    func resolvedTransitionMatrix(previous: Int, current: Int) {
        var history = CorrelatedClockHistory(initialState: ClockSampleTransition.hold)
        history.consume(sample(0, Self.levels[previous])) { _, event in CollectionOfOne(event) }
        #expect(history.possibleStates == [.firstSample])

        history.consume(sample(1, Self.levels[current])) { _, event in CollectionOfOne(event) }
        #expect(history.possibleStates == Self.transitions[previous][current])
    }

    @Test(arguments: [LogicState.undefined, .highImpedance],
          [ClockSampleTransition.rising, .falling])
    func ambiguousBridgeAndReturn(ambiguous: LogicState, edge: ClockSampleTransition) {
        let origin: LogicState = edge == .rising ? .low : .high
        let destination = origin.inverted
        var history = CorrelatedClockHistory(initialState: 0)
        let count: (Int, ClockSampleTransition) -> CollectionOfOne<Int> = {
            CollectionOfOne($0 + ($1 == edge ? 1 : 0))
        }

        history.consume(sample(0, origin), applying: count)
        history.consume(sample(1, ambiguous), applying: count)
        #expect(history.possibleStates == [0, 1])
        #expect(history.candidateCount == 2)

        var returning = history
        returning.consume(sample(2, origin), applying: count)
        #expect(returning.possibleStates == [0, 1])

        history.consume(sample(2, destination), applying: count)
        #expect(history.possibleStates == [1])
        #expect(history.candidateCount == 1)
    }

    @Test
    func relevantSameSymbolUpdateCanAdvanceHistory() {
        var history = CorrelatedClockHistory(initialState: 0)
        history.consume(sample(1, .low), applying: countRises)
        history.consume(sample(2, .undefined), applying: countRises)

        // Re-solving the receiver, including after unrelated activity, reuses ID 2.
        for _ in 0..<4 {
            let consumedRepeat = history.consume(sample(2, .undefined)) { _, _ in
                Issue.record("A repeated sample inspected its controls")
                return CollectionOfOne(9)
            }
            #expect(!consumedRepeat)
        }
        #expect(history.candidateCount == 2)

        // A relevant drive update still resolves to X but is a new boundary.
        let consumedUpdate = history.consume(sample(3, .undefined), applying: countRises)
        let consumedStale = history.consume(sample(2, .undefined), applying: countRises)
        #expect(consumedUpdate)
        #expect(!consumedStale)
        #expect(history.candidateCount == 3)
        history.consume(sample(4, .highImpedance), applying: countRises)
        history.consume(sample(5, .high), applying: countRises)
        #expect(history.possibleStates == [1, 2])
    }

    @Test
    func controlsAreSampledAtThePossibleEdgeBoundary() {
        var history = CorrelatedClockHistory(initialState: 0)
        history.consume(sample(0, .low), applying: countRises)
        history.consume(sample(1, .undefined)) { count, edge in
            CollectionOfOne(count + (edge == .rising ? 2 : 0))
        }
        history.consume(sample(2, .high)) { count, edge in
            CollectionOfOne(count + (edge == .rising ? 7 : 0))
        }
        #expect(history.possibleStates == [2, 7])

        // An asynchronous override wins at this boundary, but clock history advances.
        history.consume(sample(3, .low), applying: countRises)
        history.consume(sample(4, .high)) { _, _ in CollectionOfOne(0) }
        let consumedRepeat = history.consume(sample(4, .high), applying: countRises)
        #expect(!consumedRepeat)
        history.consume(sample(5, .high), applying: countRises)
        #expect(history.possibleStates == [0])
    }

    @Test(arguments: CorrelatedClockHistoryTests.levels)
    func invalidationRequiresAFreshFirstSample(restored: LogicState) {
        var history = CorrelatedClockHistory(initialState: 0)
        history.consume(sample(0, .low), applying: countRises)
        history.consume(sample(1, .undefined), applying: countRises)
        history.invalidateClock(resetTo: 5)
        #expect(history.candidateCount == 1)
        let consumedRepeat = history.consume(sample(1, .undefined), applying: countRises)
        #expect(!consumedRepeat)
        history.consume(sample(2, restored), applying: countRises)
        #expect(history.possibleStates == [5])

        history.consume(sample(3, .high), applying: countRises)
        switch restored {
        case .low: #expect(history.possibleStates == [6])
        case .high: #expect(history.possibleStates == [5])
        case .undefined, .highImpedance: #expect(history.possibleStates == [5, 6])
        }
    }

    @Test
    func finiteDeviceStatesMergeByStateAndLevel() {
        var history = CorrelatedClockHistory(initialState: 0)
        for id in UInt64(0)..<128 {
            history.consume(sample(id, id.isMultiple(of: 2) ? .undefined : .highImpedance)) { state, edge in
                // An uncertain enable can hold or count on a rise.
                edge == .rising ? [state, (state + 1) % 4] : [state]
            }
            #expect(history.candidateCount <= 8)
        }
        #expect(history.possibleStates == [0, 1, 2, 3])
        #expect(history.candidateCount == 8)
        history.consume(sample(128, .low)) { _, _ in CollectionOfOne(0) }
        #expect(history.candidateCount == 1)
        history.consume(sample(129, .high), applying: countRises)
        #expect(history.possibleStates == [1])
        #expect(history.candidateCount == 1)
    }

    @Test
    func historyUsesResolvedPullAndContentionLevels() {
        let net = Net(name: "Clock")
        let receiver = Pin(number: 1, name: "CLK", direction: .input)
        let pull = Pin(number: 2, name: "Pull", direction: .output, isWeakDriver: true)
        let low = Pin(number: 3, name: "Low driver", direction: .output)
        let high = Pin(number: 4, name: "High driver", direction: .output)
        for pin in [receiver, pull, low, high] { net.connect(pin) }

        var history = CorrelatedClockHistory(initialState: 0)
        pull.drive(.high)
        low.drive(.low)
        net.resolve()
        #expect(receiver.state == .low)
        history.consume(sample(0, receiver.state), applying: countRises)

        high.drive(.high)
        net.resolve()
        #expect(receiver.state == .undefined)
        history.consume(sample(1, receiver.state), applying: countRises)
        #expect(history.possibleStates == [0, 1])

        low.drive(.highImpedance)
        high.drive(.highImpedance)
        net.resolve()
        #expect(receiver.state == .high)
        history.consume(sample(2, receiver.state), applying: countRises)
        #expect(history.possibleStates == [1])

        pull.drive(.highImpedance)
        net.resolve()
        #expect(receiver.state == .highImpedance)
        history.consume(sample(3, receiver.state), applying: countRises)
        #expect(history.candidateCount == 2)
    }

    private func sample(_ ordinal: UInt64, _ level: LogicState) -> ResolvedClockSample {
        ResolvedClockSample(id: ClockSampleID(ordinal: ordinal), level: level)
    }

    private func countRises(_ count: Int, _ edge: ClockSampleTransition) -> CollectionOfOne<Int> {
        CollectionOfOne(count + (edge == .rising ? 1 : 0))
    }
}
