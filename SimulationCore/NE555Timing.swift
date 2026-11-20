import Foundation

/// Narrow ideal-RC solver for TI's standard grounded-capacitor 555 connections.
/// Other networks are deliberately rejected rather than treated as a general analog circuit.
final class NE555TimingSystem {
    struct Network {
        let timer: NE555
        let capacitor: Capacitor
        let ra: Resistor
        let rb: Resistor? // nil = monostable; otherwise astable
        var chargingTau: Double { (ra.value * ra.unit.multiplier + (rb.map { $0.value * $0.unit.multiplier } ?? 0)) * capacitor.farads }
        var dischargeTau: Double { (rb.map { $0.value * $0.unit.multiplier } ?? 0) * capacitor.farads }

        var eventDelay: Double {
            guard timer.pins[4]!.state == .high, timer.pins[5]!.state == .highImpedance else { return .infinity }
            let voltage = capacitor.voltage
            if timer.pins[3]!.driveState == .high {
                // A held-low monostable trigger overrides the threshold comparator.
                if rb == nil && timer.pins[2]!.state != .high { return .infinity }
                return max(0, chargingTau * log((5 - voltage) / (5.0 / 3.0)))
            }
            if rb != nil && timer.pins[3]!.driveState == .low {
                return max(0, dischargeTau * log(max(voltage, 5.0 / 3.0) / (5.0 / 3.0)))
            }
            return .infinity
        }

        func integrate(_ seconds: Double) {
            if timer.pins[3]!.driveState == .high {
                capacitor.voltage = 5 - (5 - capacitor.voltage) * exp(-seconds / chargingTau)
            } else if timer.pins[3]!.driveState == .low {
                capacitor.voltage = rb == nil ? 0 : capacitor.voltage * exp(-seconds / dischargeTau)
            }
        }
    }

    private(set) var networks: [Network] = []
    private var previousCapacitors: Set<ObjectIdentifier> = []

    func configure(components: [any LogicComponent], nets: [Net], automaticPower: Bool) {
        let capacitors = components.compactMap { $0 as? Capacitor }
        let resistors = components.compactMap { $0 as? Resistor }
        for resistor in resistors { resistor.isTimingElement = false }
        var byPin: [ObjectIdentifier: Net] = [:]
        for net in nets { for pin in net.pins { byPin[ObjectIdentifier(pin)] = net } }
        func net(_ pin: Pin) -> Net? { byPin[ObjectIdentifier(pin)] }
        func same(_ a: Pin, _ b: Pin) -> Bool {
            guard let first = net(a), let second = net(b) else { return false }
            return first === second
        }
        func rail(_ pin: Pin, _ rail: SupplyRail) -> Bool {
            guard let node = net(pin) else { return false }
            let desired: LogicState = rail == .fiveVolts ? .high : .low
            return node.state == desired && node.pins.contains { $0.drivenSupplyRail == rail && $0.driveState == desired }
        }
        func opposite(_ resistor: Resistor, _ pin: Pin) -> Pin? {
            if same(resistor.pins[1]!, pin) { return resistor.pins[2]! }
            if same(resistor.pins[2]!, pin) { return resistor.pins[1]! }
            return nil
        }
        func only(_ node: Net?, _ allowed: [Pin]) -> Bool {
            guard let node else { return false }
            return node.pins.allSatisfy { pin in allowed.contains { $0 === pin } }
        }
        var found: [Network] = []
        for timer in components.compactMap({ $0 as? NE555 }) {
            timer.timingVoltage = nil
            timer.timingTriggerIsAnalog = false
            timer.timingIssue = nil
            let p = timer.pins
            let attached = capacitors.filter { cap in
                cap.pins.values.contains { cp in [2, 6, 7].contains { same(cp, p[$0]!) } }
            }
            guard !attached.isEmpty else { continue }
            timer.timingIssue = "Unsupported NE555 RC wiring. Use one grounded timing capacitor and the standard astable (two resistors) or monostable (one resistor) circuit. Check capacitor polarity and supply rails."
            guard attached.count == 1, let cap = attached.first else { continue }
            let top: Pin
            let bottom: Pin
            if same(cap.pins[1]!, p[6]!) { top = cap.pins[1]!; bottom = cap.pins[2]! }
            else if cap.kind == .small && same(cap.pins[2]!, p[6]!) { top = cap.pins[2]!; bottom = cap.pins[1]! }
            else { continue }
            guard rail(bottom, .ground) else { continue }
            let astable = same(p[2]!, p[6]!)
            let timingResistors = resistors.filter { opposite($0, top) != nil }
            var candidate: Network?
            if astable && timingResistors.count == 1, let rb = timingResistors.first,
               let dischargeEnd = opposite(rb, top), same(dischargeEnd, p[7]!) {
                let supplyResistors = resistors.filter { $0 !== rb && opposite($0, p[7]!).map { rail($0, .fiveVolts) } == true }
                if supplyResistors.count == 1, let ra = supplyResistors.first,
                   only(net(top), [top, p[2]!, p[6]!, rb.pins[1]!, rb.pins[2]!]),
                   only(net(p[7]!), [p[7]!, rb.pins[1]!, rb.pins[2]!, ra.pins[1]!, ra.pins[2]!]) {
                    candidate = Network(timer: timer, capacitor: cap, ra: ra, rb: rb)
                }
            } else if !astable && same(p[6]!, p[7]!), timingResistors.count == 1,
                      let ra = timingResistors.first, let supplyEnd = opposite(ra, top), rail(supplyEnd, .fiveVolts),
                      only(net(top), [top, p[6]!, p[7]!, ra.pins[1]!, ra.pins[2]!]) {
                candidate = Network(timer: timer, capacitor: cap, ra: ra, rb: nil)
            }
            guard let candidate, candidate.chargingTau.isFinite, candidate.chargingTau > 0,
                  candidate.rb == nil || (candidate.dischargeTau.isFinite && candidate.dischargeTau > 0) else { continue }
            timer.timingIssue = nil
            // Power validation remains central in SimulationEngine. An unpowered timer has no time events.
            guard automaticPower || timer.powerState == .powered else { cap.voltage = 0; continue }
            if !previousCapacitors.contains(ObjectIdentifier(cap)) { cap.voltage = 0 }
            candidate.ra.isTimingElement = true
            candidate.rb?.isTimingElement = true
            found.append(candidate)
        }
        networks = found
        previousCapacitors = Set(found.map { ObjectIdentifier($0.capacitor) })
        prepareInputs()
    }

    func prepareInputs() {
        for network in networks {
            if network.rb == nil && network.timer.pins[3]!.driveState == .low { network.capacitor.voltage = 0 }
            network.timer.timingVoltage = network.capacitor.voltage
            network.timer.timingTriggerIsAnalog = network.rb != nil
        }
    }

    var nextEventDelay: Double { networks.map(\.eventDelay).min() ?? .infinity }
    func integrate(_ seconds: Double) { for network in networks { network.integrate(seconds) } }
}
