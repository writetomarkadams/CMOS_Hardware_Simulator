import Foundation
import Testing
@testable import CMOS4000Simulator

struct ScopeTimeCursorTests {
    @Test func plotMappingMatchesSampleTimestampsAcrossWidthsAndClampsDrag() {
        let sample = ScopeSample(time: 9.25, value: .logic(.high))
        for width in [320.0, 840.0, 1600.0] {
            let axis = ScopeTimeAxis(window: 9...10, width: width)
            #expect(axis.x(for: sample.time) == axis.x(at: 0.25))
            #expect(axis.time(at: axis.fraction(at: axis.x(for: sample.time))) == sample.time)
            #expect(axis.time(at: axis.fraction(at: -100)) == 9)
            #expect(axis.time(at: axis.fraction(at: width + 100)) == 10)
        }
    }

    @Test func measurementsFollowLiveFrozenAndRescaledWindowsAcrossFourChannels() {
        let scope = Oscilloscope()
        scope.setSpan(1)
        scope.capture(at: 10) { _ in .logic(.high) }
        let cursors = ScopeTimeCursors()
        func measure() -> ScopeTimeCursors.Measurement {
            cursors.measurement(on: ScopeTimeAxis(window: scope.window, width: 840))
        }

        #expect(measure().a == 9.25)
        #expect(measure().b == 9.75)
        #expect(measure().reciprocal == 2)

        scope.setRunning(false)
        scope.capture(at: 20) { _ in .logic(.low) }
        #expect(measure().a == 9.25)
        scope.setSpan(0.25)
        #expect(measure().a == 9.8125)
        #expect(measure().interval == 0.125)
        #expect(measure().reciprocal == 8)

        scope.setRunning(true)
        scope.capture(at: 20) { _ in .logic(.low) }
        #expect(measure().a == 19.8125)
        #expect(measure().reciprocal == 8)
        for channel in 0..<Oscilloscope.channelCount {
            #expect(scope.samples(channel: channel, in: scope.window).map(\.time) == [20])
        }
    }

    @Test func crossedAndCoincidentCursorsHaveAbsoluteOrUndefinedReadouts() {
        let axis = ScopeTimeAxis(window: -0.25...0, width: 840)
        var cursors = ScopeTimeCursors(a: 0.75, b: 0.25)
        #expect(cursors.measurement(on: axis).interval == 0.125)
        #expect(cursors.measurement(on: axis).reciprocal == 8)
        cursors.b = cursors.a
        #expect(cursors.measurement(on: axis).interval == 0)
        #expect(cursors.measurement(on: axis).reciprocal == nil)

        #expect(ScopeTimeCursors.formatTime(6).hasSuffix(" s"))
        #expect(ScopeTimeCursors.formatTime(0.006).hasSuffix(" ms"))
        #expect(ScopeTimeCursors.formatTime(0.000006).hasSuffix(" µs"))
        #expect(ScopeTimeCursors.formatFrequency(500).hasSuffix(" Hz"))
        #expect(ScopeTimeCursors.formatFrequency(2_000).hasSuffix(" kHz"))
    }
}
