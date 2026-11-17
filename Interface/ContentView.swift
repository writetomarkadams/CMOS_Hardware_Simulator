import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var counter = TwoDigitCounter()
    @State private var isRunning = false

    var body: some View {
        @Bindable var counter = counter

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Two-digit BCD counter", systemImage: "cpu")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Workbench") { openWindow(id: "workbench") }
            }

            Text(counter.count.formatted(.number.precision(.integerLength(2))))
                .font(.system(size: 88, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(red: 0.58, green: 0.96, blue: 0.68))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    Color(red: 0.08, green: 0.13, blue: 0.12),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .accessibilityLabel("Count")
                .accessibilityValue(Text(counter.count.formatted()))

            LabeledContent("Ones Carry Out (pin 7)") {
                Text(counter.carryOut.description)
                    .monospaced()
            }

            Picker("Count direction", selection: $counter.countsUp) {
                Text("Up").tag(true)
                Text("Down").tag(false)
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Reset") {
                    isRunning = false
                    counter.reset()
                }
                Spacer()
                Button("Step", action: counter.step)
                    .disabled(isRunning)
                Button(isRunning ? "Pause" : "Run") {
                    isRunning.toggle()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 380)
        .padding(28)
        .frame(minWidth: 420, minHeight: 300)
        .task(id: isRunning) {
            guard isRunning else { return }

            do {
                while isRunning {
                    try await Task.sleep(for: .seconds(1))
                    guard isRunning, !Task.isCancelled else { return }
                    counter.step()
                }
            } catch {
                // SwiftUI cancels the task on pause or when the view disappears.
            }
        }
    }
}

#Preview {
    ContentView()
}
