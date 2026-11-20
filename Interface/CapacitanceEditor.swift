import SwiftUI

struct CapacitanceEditor: View {
    let capacitor: Capacitor
    let apply: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var valueFocused: Bool
    @State private var value: String

    init(capacitor: Capacitor, apply: @escaping (Double) -> Void) {
        self.capacitor = capacitor
        self.apply = apply
        _value = State(initialValue: capacitor.value.formatted(.number.grouping(.never)))
    }

    private var enteredValue: Double? {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let amount = Double(input), Capacitor.isValid(amount, kind: capacitor.kind) else { return nil }
        return amount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capacitance").font(.headline)
            HStack {
                TextField("Value", text: $value).focused($valueFocused)
                Text(capacitor.kind.unit)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    guard let enteredValue else { return }
                    apply(enteredValue)
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
