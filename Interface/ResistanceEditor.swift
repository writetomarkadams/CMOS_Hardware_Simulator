import SwiftUI

struct ResistanceEditor: View {
    let apply: (Double, ResistanceUnit) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var valueFocused: Bool
    @State private var value: String
    @State private var unit: ResistanceUnit

    init(resistor: Resistor, apply: @escaping (Double, ResistanceUnit) -> Void) {
        self.apply = apply
        _value = State(initialValue: resistor.value.formatted(.number.grouping(.never)))
        _unit = State(initialValue: resistor.unit)
    }

    private var enteredValue: Double? {
        let separator = Locale.current.decimalSeparator ?? "."
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: separator, with: ".")
        guard let amount = Double(input) else { return nil }
        let ohms = amount * unit.multiplier
        return ohms.isFinite && ohms > 0 ? amount : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resistance")
                .font(.headline)

            HStack {
                TextField("Value", text: $value)
                    .focused($valueFocused)
                Picker("Unit", selection: $unit) {
                    ForEach(ResistanceUnit.allCases) { unit in
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
                    guard let enteredValue else { return }
                    apply(enteredValue, unit)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(enteredValue == nil)
            }
        }
        .padding(20)
        .frame(width: 290)
        .defaultFocus($valueFocused, true)
    }
}
