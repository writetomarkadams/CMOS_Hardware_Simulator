import Foundation

/// Ideal RC solver for supported grounded-capacitor 555 connections.
/// Other networks are deliberately rejected rather than treated as a general analog circuit.
final class NE555TimingSystem {
    struct Network {
        let timer: NE555
        let capacitor: Capacitor
        let ra: Resistor
        let rb: Resistor? // nil = monostable; otherwise astable
        var steering: (charge: Diode1N4148, discharge: Diode1N4148)? = nil

        private var raOhms: Double { ra.value * ra.unit.multiplier }
        private var rbOhms: Double { rb.map { $0.value * $0.unit.multiplier } ?? 0 }

        // Nominal piecewise-linear 1N4148 model.
        private let forwardVoltage = 0.60
        private let diodeOhms = 50.0
        private var chargeParallel: Double { 1 / (1 / rbOhms + 1 / diodeOhms) }
        private var dischargeParallel: Double { 1 / (1 / raOhms + 1 / diodeOhms) }

        var chargingTau: Double {
            (raOhms + (steering == nil ? rbOhms : chargeParallel)) * capacitor.farads
        }
        var dischargeTau: Double {
            (rbOhms + (steering == nil ? 0 : dischargeParallel)) * capacitor.farads
        }
        private var chargingTarget: Double {
            steering == nil ? 5 : 5 - forwardVoltage * chargeParallel / diodeOhms
        }
        private var dischargeTarget: Double {
            steering == nil ? 0 : forwardVoltage + (5 - forwardVoltage) * dischargeParallel / raOhms
        }
        var hasSupportedSteering: Bool {
            guard steering != nil else { return true }
            // Keep the charging diode forward-biased through the upper comparator
            // threshold. Other component ratios can change conduction mid-cycle.
            let currentAtThreshold = (chargingTarget - 10.0 / 3.0) / (raOhms + chargeParallel)
            return currentAtThreshold > forwardVoltage / rbOhms && dischargeTarget < 5.0 / 3.0
        }

        var eventDelay: Double {
            guard timer.pins[4]!.state == .high, timer.pins[5]!.state == .highImpedance else { return .infinity }
            let voltage = capacitor.voltage
            if timer.pins[3]!.driveState == .high {
                // A held-low monostable trigger overrides the threshold comparator.
                if rb == nil && timer.pins[2]!.state != .high { return .infinity }
                return max(0, chargingTau * log((chargingTarget - voltage) / (chargingTarget - 10.0 / 3.0)))
            }
            if rb != nil && timer.pins[3]!.driveState == .low {
                let threshold = 5.0 / 3.0 - dischargeTarget
                return max(0, dischargeTau * log(max(voltage - dischargeTarget, threshold) / threshold))
            }
            return .infinity
        }

        func integrate(_ seconds: Double) {
            if timer.pins[3]!.driveState == .high {
                capacitor.voltage = chargingTarget - (chargingTarget - capacitor.voltage) * exp(-seconds / chargingTau)
            } else if timer.pins[3]!.driveState == .low {
                capacitor.voltage = rb == nil ? 0 : dischargeTarget + (capacitor.voltage - dischargeTarget) * exp(-seconds / dischargeTau)
            }
        }
    }

    private(set) var networks: [Network] = []
    private var previousCapacitors: Set<ObjectIdentifier> = []

    func configure(components: [any LogicComponent], nets: [Net], automaticPower: Bool) {
        let capacitors = components.compactMap { $0 as? Capacitor }
        let resistors = components.compactMap { $0 as? Resistor }
        let diodes = components.compactMap { $0 as? Diode1N4148 }
        for resistor in resistors { resistor.isTimingElement = false }
        for diode in diodes { diode.isTimingElement = false }
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
            if candidate == nil && astable && timingResistors.count == 1,
               let rb = timingResistors.first, let steeringNode = opposite(rb, top) {
                let chargeDiodes = diodes.filter { same($0.pins[2]!, steeringNode) && same($0.pins[1]!, top) }
                let dischargeDiodes = diodes.filter { same($0.pins[2]!, steeringNode) && same($0.pins[1]!, p[7]!) }
                if chargeDiodes.count == 1, dischargeDiodes.count == 1,
                   let charge = chargeDiodes.first, let discharge = dischargeDiodes.first {
                    let supplyResistors = resistors.filter {
                        $0 !== rb && opposite($0, steeringNode).map { rail($0, .fiveVolts) } == true
                    }
                    if supplyResistors.isEmpty {
                        timer.timingIssue = "The diode steering junction has no charging path. Connect a resistor from +5 V to the joined diode anodes."
                    }
                    if supplyResistors.count == 1, let ra = supplyResistors.first,
                       only(net(top), [top, p[2]!, p[6]!, rb.pins[1]!, rb.pins[2]!, charge.pins[1]!]),
                       only(net(p[7]!), [p[7]!, discharge.pins[1]!]),
                       only(net(steeringNode), [charge.pins[2]!, discharge.pins[2]!, rb.pins[1]!, rb.pins[2]!, ra.pins[1]!, ra.pins[2]!]) {
                        let steered = Network(timer: timer, capacitor: cap, ra: ra, rb: rb, steering: (charge, discharge))
                        if steered.hasSupportedSteering {
                            candidate = steered
                        } else {
                            timer.timingIssue = "Unsupported diode steering resistor ratio. Try 10 kΩ from +5 V and 100 kΩ across the charging diode."
                        }
                    }
                }
            }
            guard let candidate, candidate.chargingTau.isFinite, candidate.chargingTau > 0,
                  candidate.rb == nil || (candidate.dischargeTau.isFinite && candidate.dischargeTau > 0) else { continue }
            timer.timingIssue = nil
            // Power validation remains central in SimulationEngine. An unpowered timer has no time events.
            guard automaticPower || timer.powerState == .powered else { cap.voltage = 0; continue }
            if !previousCapacitors.contains(ObjectIdentifier(cap)) { cap.voltage = 0 }
            candidate.ra.isTimingElement = true
            candidate.rb?.isTimingElement = true
            candidate.steering?.charge.isTimingElement = true
            candidate.steering?.discharge.isTimingElement = true
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
