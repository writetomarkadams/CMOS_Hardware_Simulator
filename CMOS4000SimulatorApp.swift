
import SwiftUI

@main
struct CMOS4000SimulatorApp: App {
    var body: some Scene {
        WindowGroup("Circuit Workbench", id: "workbench") {
            WorkbenchView()
        }
        .defaultSize(width: 900, height: 700)
    }
}
