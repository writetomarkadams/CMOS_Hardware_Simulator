import SwiftUI

struct CircuitImportFile: Identifiable {
    let id = UUID()
    let name: String
    let preview: CircuitImportPreview
}

struct CircuitImportView: View {
    let file: CircuitImportFile
    let hasExistingCircuit: Bool
    let powerMode: PowerMode
    let apply: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Circuit").font(.title2.bold())
            Text(file.name)
            Text("\(file.preview.supportedCount) of \(file.preview.entries.count) components supported · \(file.preview.nets.count) nets")
                .foregroundStyle(.secondary)

            TabView {
                List(Array(file.preview.warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning).textSelection(.enabled)
                }
                .overlay {
                    if file.preview.warnings.isEmpty { Text("No validation warnings.").foregroundStyle(.secondary) }
                }
                .tabItem { Text("Warnings (\(file.preview.warnings.count))") }

                List(file.preview.entries) { entry in
                    VStack(alignment: .leading) {
                        Text("\(entry.part.reference) · \(entry.part.value)")
                        Text("\(entry.part.library):\(entry.part.symbol) → \(entry.model ?? "Omitted")")
                            .foregroundStyle(.secondary)
                    }
                    .textSelection(.enabled)
                }
                .tabItem { Text("Components") }

                List(file.preview.nets, id: \.id) { net in
                    VStack(alignment: .leading) {
                        Text(net.name)
                        Text(net.terminals.map { "\($0.reference).\($0.pin)" }.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                    .textSelection(.enabled)
                }
                .tabItem { Text("Nets") }
            }

            if !file.preview.canImport {
                Text("This file has no importable components.")
            } else if hasExistingCircuit {
                Text("Replace removes the current circuit and uses Explicit Power. Add places an electrically separate circuit below your work and keeps \(powerMode.rawValue). Both actions can be undone.")
                    .foregroundStyle(.secondary)
            } else {
                Text("The imported circuit uses Explicit Power.").foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                if hasExistingCircuit {
                    Button("Replace Workbench", role: .destructive) { apply(true) }
                        .disabled(!file.preview.canImport)
                    Button("Add to Workbench") { apply(false) }
                        .disabled(!file.preview.canImport)
                } else {
                    Button("Import into Workbench") { apply(false) }
                        .disabled(!file.preview.canImport)
                }
            }
        }
        .padding(20)
        .frame(width: 660, height: 510)
    }
}
