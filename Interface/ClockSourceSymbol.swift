import SwiftUI

enum ClockFrequencyUnit: String, CaseIterable, Identifiable, Codable {
    case hertz = "Hz"
    case kilohertz = "kHz"
    case megahertz = "MHz"

    var id: Self { self }

    var multiplier: Double {
        switch self {
        case .hertz: 1
        case .kilohertz: 1_000
        case .megahertz: 1_000_000
        }
    }
}

struct ClockFrequency: Equatable, Codable {
    let value: Double
    let unit: ClockFrequencyUnit

    var hertz: Double { value * unit.multiplier }
    var label: String { "\(value.formatted(.number.precision(.significantDigits(1...17)))) \(unit.rawValue)" }

    static func parse(_ text: String, unit: ClockFrequencyUnit, locale: Locale = .current) -> Self? {
        var number = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = locale.groupingSeparator, !separator.isEmpty {
            number = number.replacingOccurrences(of: separator, with: "")
        }
        if let separator = locale.decimalSeparator {
            number = number.replacingOccurrences(of: separator, with: ".")
        }
        guard let value = Double(number) else { return nil }
        let frequency = Self(value: value, unit: unit)
        // Reject values that overflow the frequency or the clock's half-period.
        guard frequency.hertz.isFinite, frequency.hertz > 0,
              0.5 / frequency.hertz < Double(Int64.max) else { return nil }
        return frequency
    }
}

struct ClockSourceSymbol: View {
    let part: WorkbenchPart
    private var partID: Int { part.id }
    let source: WorkbenchClock
    let bench: Workbench
    let isSelected: Bool
    let select: () -> Void
    let rotate: (Int) -> Void

    private var frequency: ClockFrequency {
        bench.clockFrequencies[partID] ?? ClockFrequency(value: 1, unit: .hertz)
    }
    @State private var isRunning = false
    @State private var editingFrequency = false
    @State private var frequencyText = ""
    @State private var frequencyUnit: ClockFrequencyUnit = .hertz
    @FocusState private var frequencyFocused: Bool

    private var enteredFrequency: ClockFrequency? {
        ClockFrequency.parse(frequencyText, unit: frequencyUnit)
    }

    var body: some View {
        VStack(spacing: 4) {
            squareWaveSymbol

            Text(frequency.label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $editingFrequency) {
            frequencyEditor
        }
        .onChange(of: frequency.hertz) {
            if isRunning { bench.runClock(source, hertz: frequency.hertz) }
        }
        .onDisappear {
            isRunning = false
            bench.stopClock(source)
        }
    }

    private func editFrequency() {
        frequencyText = frequency.value.formatted(
            .number.grouping(.never).precision(.significantDigits(1...17))
        )
        frequencyUnit = frequency.unit
        editingFrequency = true
    }

    private var squareWaveSymbol: some View {
        ZStack(alignment: .topLeading) {
            Button(action: toggleClock) {
                Path { path in
                    path.addLines([
                        CGPoint(x: 5, y: 19), CGPoint(x: 14, y: 19),
                        CGPoint(x: 14, y: 7), CGPoint(x: 26, y: 7),
                        CGPoint(x: 26, y: 19), CGPoint(x: 38, y: 19),
                        CGPoint(x: 38, y: 7), CGPoint(x: 50, y: 7),
                        CGPoint(x: 50, y: 19), CGPoint(x: 57, y: 19)
                    ])
                }
                .stroke(isRunning ? Color.green : isSelected ? Color.schematicSelectionInk : Color.primary, lineWidth: 1.5)
                .frame(width: 62, height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clock \(partID)")
            .accessibilityValue("\(frequency.label), \(isRunning ? "running" : "paused")")
            .accessibilityHint(isRunning ? "Pauses the clock" : "Runs the clock")
            .help(isRunning ? "Pause clock" : "Run clock")
            .contextMenu {
                PartRotationCommands(rotate: rotate)
                Button("Set Frequency…", action: editFrequency)
                Button(isRunning ? "Pause" : "Run", action: toggleClock)
                Divider()
                Button("Remove Part", role: .destructive) { bench.removePart(partID) }
            }

            Path { path in
                path.move(to: CGPoint(x: 57, y: 19))
                path.addLine(to: CGPoint(x: 76, y: 19))
            }
            .stroke(isSelected ? Color.schematicSelectionInk : Color.primary, lineWidth: 1.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            outputTerminal(pinNumber: source.output.number).position(x: 76, y: 19)
        }
        .frame(width: 86, height: 29)
    }

    private func toggleClock() {
        select()
        isRunning.toggle()
        if isRunning {
            bench.runClock(source, hertz: frequency.hertz)
        } else {
            bench.stopClock(source)
        }
    }

    private func outputTerminal(pinNumber: Int) -> some View {
        let terminal = WorkbenchTerminal(partID: partID, pinNumber: pinNumber)
        let state = bench.readings[terminal] ?? .highImpedance
        let selected = bench.selectedTerminal == terminal

        return Button {
            bench.select(terminal)
        } label: {
            Image(systemName: selected ? "circle.inset.filled" : "circle")
                .font(.system(size: 8))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
                .anchorPreference(key: CanvasBounds.self, value: .bounds) { [.terminal(terminal): $0] }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bench.label(for: terminal))
        .accessibilityValue(state.description)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(state.description)
    }

    private var frequencyEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clock Frequency")
                .font(.headline)
            HStack {
                TextField("Frequency", text: $frequencyText)
                    .focused($frequencyFocused)
                Picker("Unit", selection: $frequencyUnit) {
                    ForEach(ClockFrequencyUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack {
                Spacer()
                Button("Cancel") { editingFrequency = false }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    guard let enteredFrequency else { return }
                    bench.setClockFrequency(enteredFrequency, for: partID)
                    editingFrequency = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(enteredFrequency == nil)
            }
        }
        .padding(20)
        .frame(width: 330)
        .defaultFocus($frequencyFocused, true)
    }
}
