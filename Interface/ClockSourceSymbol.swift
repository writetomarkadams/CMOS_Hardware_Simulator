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
        bench.clockFrequency(for: partID, source: source)
    }
    @State private var isRunning = false
    @State private var editingFrequency = false
    static let endpoint = CGPoint(x: 80, y: 20)

    var body: some View {
        VStack(spacing: 4) {
            squareWaveSymbol

            Text(frequency.label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 100, height: 60, alignment: .topLeading)
        .sheet(isPresented: $editingFrequency) {
            ClockFrequencyEditor(frequency: frequency, units: ClockFrequencyUnit.allCases) {
                bench.setClockFrequency($0, for: partID)
            }
        }
        .onChange(of: frequency.hertz) {
            if isRunning { bench.runClock(source, hertz: frequency.hertz) }
        }
        .onDisappear {
            isRunning = false
            bench.stopClock(source)
        }
    }

    private var squareWaveSymbol: some View {
        let terminal = WorkbenchTerminal(partID: partID, pinNumber: source.output.number)
        let endpoint = Self.endpoint
        return ZStack(alignment: .topLeading) {
            Button(action: toggleClock) {
                Path { path in
                    path.addLines([
                        CGPoint(x: 5, y: 20), CGPoint(x: 14, y: 20),
                        CGPoint(x: 14, y: 7), CGPoint(x: 26, y: 7),
                        CGPoint(x: 26, y: 20), CGPoint(x: 38, y: 20),
                        CGPoint(x: 38, y: 7), CGPoint(x: 50, y: 7),
                        CGPoint(x: 50, y: 20), CGPoint(x: 57, y: 20)
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
                Button("Set Frequency…") { editingFrequency = true }
                Button(isRunning ? "Pause" : "Run", action: toggleClock)
                Divider()
                Button("Remove Part", role: .destructive) { bench.removePart(partID) }
            }

            Path { path in
                path.move(to: CGPoint(x: 57, y: 20))
                path.addLine(to: CGPoint(x: endpoint.x - (bench.showsOpenPinMarker(terminal) ? 2.5 : 0), y: endpoint.y))
            }
            .stroke(isSelected ? Color.schematicSelectionInk : Color.primary, lineWidth: 1.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            SchematicPinButton(terminal: terminal, bench: bench).position(endpoint)
        }
        .frame(width: 100, height: 30)
    }

    private func toggleClock() {
        select()
        guard !workbenchShiftPressed else { return }
        isRunning.toggle()
        if isRunning {
            bench.runClock(source, hertz: frequency.hertz)
        } else {
            bench.stopClock(source)
        }
    }

}

struct ClockFrequencyEditor: View {
    let units: [ClockFrequencyUnit]
    let apply: (ClockFrequency) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var frequencyText: String
    @State private var frequencyUnit: ClockFrequencyUnit
    @FocusState private var frequencyFocused: Bool

    init(frequency: ClockFrequency, units: [ClockFrequencyUnit], apply: @escaping (ClockFrequency) -> Void) {
        self.units = units
        self.apply = apply
        _frequencyText = State(initialValue: frequency.value.formatted(
            .number.grouping(.never).precision(.significantDigits(1...17))
        ))
        _frequencyUnit = State(initialValue: frequency.unit)
    }

    private var enteredFrequency: ClockFrequency? {
        ClockFrequency.parse(frequencyText, unit: frequencyUnit)
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 16) {
            Text("Clock Frequency")
                .font(.headline)
            HStack {
                TextField("Frequency", text: $frequencyText)
                    .focused($frequencyFocused)
                Picker("Unit", selection: $frequencyUnit) {
                    ForEach(units) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    guard let enteredFrequency else { return }
                    apply(enteredFrequency)
                    dismiss()
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
