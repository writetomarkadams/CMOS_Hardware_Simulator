
import SwiftUI

@main
struct CMOS4000SimulatorApp: App {
    var body: some Scene {
        WindowGroup("Circuit Workbench", id: "workbench") {
            WorkbenchView()
        }
        .defaultSize(width: 900, height: 700)
        .commands { WorkbenchFileCommands() }
    }
}


struct WorkbenchFileActions {
    let open: () -> Void
    let save: () -> Void
    let isEnabled: Bool
}

private struct WorkbenchFileActionsKey: FocusedValueKey {
    typealias Value = WorkbenchFileActions
}

extension FocusedValues {
    var workbenchFiles: WorkbenchFileActions? {
        get { self[WorkbenchFileActionsKey.self] }
        set { self[WorkbenchFileActionsKey.self] = newValue }
    }
}

struct WorkbenchFileCommands: Commands {
    @FocusedValue(\.workbenchFiles) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open…") { actions?.open() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions?.isEnabled != true)
            Button("Save…") { actions?.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(actions?.isEnabled != true)
        }
    }
}
