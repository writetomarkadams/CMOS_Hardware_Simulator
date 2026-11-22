import AppKit
import SwiftUI

let oscilloscopeChannelColours: [Color] = [.yellow, .cyan, .green, .pink]

struct OscilloscopeView: View {
    let bench: Workbench
    @Binding var voltageRange: Double
    @Binding var cursors: ScopeTimeCursors
    let placementLabel: String
    let changePlacement: () -> Void

    private let spans = [0.001, 0.01, 0.1, 1.0, 10.0, 60.0]
    private var scope: Oscilloscope { bench.scope }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(placementLabel, action: changePlacement)
                Spacer()
                Toggle("Cursors", isOn: $cursors.isVisible)
                    .toggleStyle(.button)
                    .help("Show or hide the two time cursors")
                Button(scope.running ? "Freeze" : "Run") {
                    scope.setRunning(!scope.running)
                    bench.refreshScope()
                }
                Button("Clear") {
                    scope.clear()
                    bench.refreshScope()
                }
                .help("Clear the waveforms and re-arm the pulse indicators")
                Text(scope.running ? "Running" : "Frozen")
                    .font(.caption)
            }
            HStack {
                ForEach(0..<Oscilloscope.channelCount, id: \.self) { channel in
                    VStack(alignment: .leading, spacing: 3) {
                        probeMenu(channel)
                        if bench.scopeProbes[channel] != nil {
                            let seen = scope.pulseSeenChannels.contains(channel)
                            Label(seen ? "Pulse seen" : "No pulse seen",
                                  systemImage: seen ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(seen ? oscilloscopeChannelColours[channel] : .secondary)
                                .help("Latches when the signal rises from LOW to HIGH while the scope is running")
                        }
                    }
                }
            }
            HStack {
                Picker("Time window", selection: Binding(get: { scope.span }, set: scope.setSpan)) {
                    ForEach(spans, id: \.self) { span in
                        Text(span < 1 ? "\(Int(span * 1000)) ms" : "\(Int(span)) s").tag(span)
                    }
                }
                .fixedSize()
                Picker("Voltage range", selection: $voltageRange) {
                    ForEach([2.0, 5.0, 10.0], id: \.self) { Text("0–\(Int($0)) V").tag($0) }
                }
                .fixedSize()
                Text("Digital lanes show LOW, HIGH, X or Z. Analog lanes show voltage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30,
                                    paused: !scope.running || bench.scopeProbes.isEmpty)) { _ in
                let window = scope.window
                let capturedThrough = scope.time
                let traces = (0..<Oscilloscope.channelCount).map { scope.samples(channel: $0, in: window) }
                GeometryReader { geometry in
                    let axis = ScopeTimeAxis(window: window, width: geometry.size.width)
                    VStack(alignment: .leading, spacing: 4) {
                        Canvas { context, size in
                            draw(in: context, size: size, axis: axis,
                                 capturedThrough: capturedThrough, traces: traces)
                        }
                        .id(scope.revision)
                        .accessibilityLabel("Four-channel waveform plot")
                        .overlay {
                            if cursors.isVisible {
                                GeometryReader { plot in
                                    cursor("A", position: $cursors.a, axis: axis, height: plot.size.height,
                                           handleY: 14, dashed: false)
                                    cursor("B", position: $cursors.b, axis: axis, height: plot.size.height,
                                           handleY: plot.size.height - 14, dashed: true)
                                }
                                .coordinateSpace(name: "scopePlot")
                            }
                        }
                        .background(Color(white: 0.08))
                        .clipShape(.rect(cornerRadius: 6))

                        if cursors.isVisible {
                            cursorReadout(cursors.measurement(on: axis))
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: .infinity)
            }
        }
        .padding(12)
    }

    private func cursor(_ name: String, position: Binding<Double>, axis: ScopeTimeAxis,
                        height: CGFloat, handleY: CGFloat, dashed: Bool) -> some View {
        let x = axis.x(at: position.wrappedValue)
        let color: Color = dashed ? .orange : .white
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [5, 3] : []))
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            Text(name)
                .font(.caption.bold())
                .foregroundStyle(.black)
                .frame(width: 30, height: 24)
                .background(color, in: .rect(cornerRadius: 4))
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("scopePlot"))
                    .onChanged { drag in
                        position.wrappedValue = axis.fraction(at: drag.location.x)
                    })
                .accessibilityLabel("Time cursor " + name)
                .accessibilityValue(ScopeTimeCursors.formatTime(axis.time(at: position.wrappedValue)))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: position.wrappedValue = min(1, position.wrappedValue + 0.01)
                    case .decrement: position.wrappedValue = max(0, position.wrappedValue - 0.01)
                    @unknown default: break
                    }
                }
                .help("Drag time cursor " + name)
                .position(x: min(x, axis.x(at: 1) - 7), y: handleY)
        }
    }

    private func cursorReadout(_ measurement: ScopeTimeCursors.Measurement) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Text("A  " + ScopeTimeCursors.formatTime(measurement.a))
                Text("B  " + ScopeTimeCursors.formatTime(measurement.b))
                Text("Δt  " + ScopeTimeCursors.formatTime(measurement.interval))
                Text("1/Δt  " + (measurement.reciprocal.map(ScopeTimeCursors.formatFrequency) ?? "Undefined"))
            }
            .monospacedDigit()
            Text("1/Δt is the waveform frequency only when A and B span exactly one full period.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func probeMenu(_ channel: Int) -> some View {
        let target = bench.scopeProbes[channel]
        return Menu {
            Button("Disconnect") { bench.assignScopeProbe(nil, to: channel) }
                .disabled(target == nil)
            Menu("Wire / Net") {
                ForEach(bench.wires.filter { $0.sourceRoute != .alias }) { wire in
                    Button("Wire \(wire.id) · \(bench.label(for: wire.first)) ↔ \(bench.label(for: wire.second))") {
                        bench.assignScopeProbe(.wire(wire.id), to: channel)
                    }
                }
            }
            .disabled(bench.wires.isEmpty)
            ForEach(bench.parts) { part in
                Menu(part.label) {
                    ForEach(part.pins.keys.sorted(), id: \.self) { number in
                        let terminal = WorkbenchTerminal(partID: part.id, pinNumber: number)
                        Button(bench.label(for: terminal)) { bench.assignScopeProbe(.pin(terminal), to: channel) }
                    }
                }
            }
        } label: {
            Text("CH \(channel + 1) · \(probeLabel(target))")
                .lineLimit(1)
                .foregroundStyle(oscilloscopeChannelColours[channel])
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(white: 0.12), in: .rect(cornerRadius: 4))
        }
        .help(probeLabel(target))
    }

    private func probeLabel(_ probe: ScopeProbe?) -> String {
        switch probe {
        case .pin(let terminal), .netPin(let terminal): bench.label(for: terminal)
        case .wire(let id), .wirePoint(let id, _): "Wire \(id)"
        case nil: "Attach probe"
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize, axis: ScopeTimeAxis,
                      capturedThrough: Double, traces: [[ScopeSample]]) {
        let window = axis.window
        let left = ScopeTimeAxis.left
        let width = axis.plotWidth
        let laneHeight = size.height / CGFloat(Oscilloscope.channelCount)
        var grid = Path()
        for division in 0...10 {
            let x = axis.x(at: Double(division) / 10)
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        for channel in 1..<Oscilloscope.channelCount {
            let y = CGFloat(channel) * laneHeight
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(.white.opacity(0.19)), lineWidth: 0.5)

        for channel in 0..<Oscilloscope.channelCount {
            let samples = traces[channel]
            let colour = oscilloscopeChannelColours[channel]
            let top = CGFloat(channel) * laneHeight
            let last = samples.last(where: { $0.time <= window.upperBound })?.value
            let label: String
            switch last {
            case .voltage(let volts): label = volts.formatted(.number.precision(.fractionLength(1))) + " V"
            case .logic(.high): label = "HIGH"
            case .logic(.low): label = "LOW"
            case .logic(.highImpedance): label = "Z"
            case .logic(.undefined): label = "X"
            case nil: label = "—"
            }
            context.draw(Text("CH \(channel + 1)  \(label)").font(.system(size: 8)).foregroundStyle(colour),
                         at: CGPoint(x: 3, y: top + laneHeight / 2), anchor: .leading)

            var traceContext = context
            traceContext.clip(to: Path(CGRect(x: left, y: top, width: width, height: laneHeight)))
            func point(_ time: Double, _ value: ScopeValue) -> CGPoint {
                let level: Double
                switch value {
                case .voltage(let volts): level = volts / voltageRange
                case .logic(.high): level = 1
                case .logic(.low): level = 0
                case .logic(.highImpedance): level = 0.35
                case .logic(.undefined): level = 0.65
                }
                return CGPoint(x: axis.x(for: time),
                               y: top + laneHeight * (0.85 - 0.7 * level))
            }

            var known = Path()
            var other = Path()
            var lastDigitalEdgeColumn: Int?
            for (index, sample) in samples.enumerated() {
                let next = index + 1 < samples.count ? samples[index + 1] : nil
                let end = next?.time ?? min(capturedThrough, window.upperBound)
                guard end >= window.lowerBound, sample.time <= window.upperBound else { continue }
                let visibleStart = max(sample.time, window.lowerBound)
                let visibleEnd = min(end, window.upperBound)
                if case .voltage(let first) = sample.value, let next, case .voltage(let second) = next.value {
                    func voltage(at time: Double) -> ScopeValue {
                        guard end > sample.time else { return .voltage(first) }
                        let fraction = (time - sample.time) / (end - sample.time)
                        return .voltage(first + (second - first) * fraction)
                    }
                    known.move(to: point(visibleStart, voltage(at: visibleStart)))
                    known.addLine(to: point(visibleEnd, end == sample.time ? next.value : voltage(at: visibleEnd)))
                } else {
                    let startPoint = point(visibleStart, sample.value)
                    let endPoint = point(visibleEnd, sample.value)
                    switch sample.value {
                    case .logic(.undefined), .logic(.highImpedance):
                        other.move(to: startPoint)
                        other.addLine(to: endPoint)
                    default:
                        known.move(to: startPoint)
                        known.addLine(to: endPoint)
                        if end <= window.upperBound, let next, case .logic(let state) = next.value, state == .high || state == .low,
                           case .logic = sample.value {
                            let column = Int(endPoint.x.rounded())
                            if column != lastDigitalEdgeColumn {
                                known.addLine(to: point(end, next.value))
                                lastDigitalEdgeColumn = column
                            }
                        }
                    }
                }
            }
            traceContext.stroke(known, with: .color(colour), lineWidth: 1.2)
            traceContext.stroke(other, with: .color(colour.opacity(0.7)),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }
    }
}

@MainActor
@Observable
final class WorkbenchScopeWindow {
    var voltageRange = 5.0
    var cursors = ScopeTimeCursors()
    private var window: NSWindow?

    func show(bench: Workbench, dock: @escaping () -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 840, height: 370),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Oscilloscope"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 640, height: 220)
        window.contentView = NSHostingView(rootView: OscilloscopeView(
            bench: bench,
            voltageRange: Binding(get: { [weak self] in self?.voltageRange ?? 5 },
                                  set: { [weak self] in self?.voltageRange = $0 }),
            cursors: Binding(get: { [weak self] in self?.cursors ?? ScopeTimeCursors() },
                             set: { [weak self] in self?.cursors = $0 }),
            placementLabel: "Dock in Workbench",
            changePlacement: dock
        ))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }

    func dispose() {
        window?.close()
        window = nil
    }
}
