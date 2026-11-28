
final class Net {
    let name: String

    private(set) var pins: [Pin] = []
    private(set) var dcVoltage: Double?
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
        Self.resolve(pins: pins, nets: [self])
    }

    static func resolve(together nets: [Net]) {
        resolve(pins: nets.flatMap(\.pins), nets: nets)
    }

    func receiveDC(_ voltage: Double) {
        dcVoltage = voltage
        // Fixed thresholds for the discrete model's ideal 5 V logic interface.
        state = voltage <= 0.8 ? .low : voltage >= 2.0 ? .high : .undefined
        for pin in pins {
            pin.receive(state, strongState: pin.strongState, supplyRail: pin.supplyRail, dcVoltage: voltage)
        }
    }

    private static func resolve(pins: [Pin], nets: [Net]) {
        var strongState = LogicState.highImpedance
        var weakState = LogicState.highImpedance
        for pin in pins where pin.driveState != .highImpedance {
            if pin.isWeakDriver {
                weakState = merged(weakState, pin.driveState)
            } else {
                strongState = merged(strongState, pin.driveState)
            }
        }
        let state = strongState == .highImpedance ? weakState : strongState

        let railDrivers = pins.filter { $0.driveState != .highImpedance && $0.drivenSupplyRail != nil }
        let rail = railDrivers.first?.drivenSupplyRail
        let supply = railDrivers.allSatisfy { $0.drivenSupplyRail == rail } && state != .undefined ? rail : nil
        for net in nets {
            net.state = state
            net.dcVoltage = nil
        }
        for pin in pins {
            pin.receive(state, strongState: strongState, supplyRail: supply)
        }

        guard state == .undefined || state == .highImpedance else { return }
        let receivers = pins.filter(\.tracksClockProvenance)
        guard !receivers.isEmpty else { return }
        var drivers: [ObjectIdentifier: ClockDriveObservation] = [:]
        for pin in pins {
            if state == .highImpedance {
                guard pin.direction == .output || pin.direction == .bidirectional ||
                    pin.direction == .power else { continue }
            } else {
                guard pin.driveState != .highImpedance,
                      pin.isWeakDriver == (strongState == .highImpedance) else { continue }
            }
            drivers[ObjectIdentifier(pin)] = ClockDriveObservation(level: pin.driveState,
                                                                   publication: pin.clockPublication)
        }
        for receiver in receivers {
            receiver.clockDriveObservations = drivers
        }
    }

    private static func merged(_ current: LogicState, _ next: LogicState) -> LogicState {
        if current == .highImpedance { return next }
        return current == next ? current : .undefined
    }
}
