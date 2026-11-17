
final class Net {
    let name: String

    private(set) var pins: [Pin] = []
    private(set) var state: LogicState = .highImpedance

    init(name: String) {
        self.name = name
    }

    // Connect a pin to this net.
    func connect(_ pin: Pin) {
        guard !pins.contains(where: { $0 === pin }) else {
            return
        }

        pins.append(pin)
        resolve()
    }

    // Determine the net's logic state from its drivers.
    func resolve() {
        var strongState = LogicState.highImpedance
        var weakState = LogicState.highImpedance
        for pin in pins where pin.driveState != .highImpedance {
            if pin.isWeakDriver {
                weakState = merged(weakState, pin.driveState)
            } else {
                strongState = merged(strongState, pin.driveState)
            }
        }
        state = strongState == .highImpedance ? weakState : strongState

        for pin in pins {
            pin.receive(state, strongState: strongState)
        }
    }

    private func merged(_ current: LogicState, _ next: LogicState) -> LogicState {
        if current == .highImpedance { return next }
        return current == next ? current : .undefined
    }
}
