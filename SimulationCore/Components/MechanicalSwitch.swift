import Observation

enum SwitchDesignation: String, CaseIterable, Codable, Identifiable {
    case pushButton = "SW_Push"
    case spdt = "SW_SPDT"

    var id: Self { self }
    var label: String {
        switch self {
        case .pushButton: "Normally Open Push Button"
        case .spdt: "SPDT (Maintained)"
        }
    }
}

@Observable
final class MechanicalSwitch: SwitchedConnectivity {
    let designation: SwitchDesignation
    let pins: [Int: Pin]
    private(set) var isPressed = false
    private(set) var selectsThrow3: Bool

    init(_ designation: SwitchDesignation = .pushButton, selectsThrow3: Bool = false) {
        self.designation = designation
        self.selectsThrow3 = designation == .spdt && selectsThrow3
        let names = designation == .pushButton ? ["1", "2"] : ["Throw 1", "Common", "Throw 3"]
        pins = Dictionary(uniqueKeysWithValues: names.enumerated().map { index, name in
            let number = index + 1
            return (number, Pin(number: number, name: name, direction: .bidirectional))
        })
    }

    func evaluate() {}

    func setPressed(_ pressed: Bool) {
        if designation == .pushButton { isPressed = pressed }
    }

    func toggle() {
        if designation == .spdt { selectsThrow3.toggle() }
    }

    var closedConnections: [(Pin, Pin)] {
        switch designation {
        case .pushButton: isPressed ? [(pins[1]!, pins[2]!)] : []
        case .spdt: [(pins[2]!, pins[selectsThrow3 ? 3 : 1]!)]
        }
    }
}
