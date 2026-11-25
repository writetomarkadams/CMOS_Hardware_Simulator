import Foundation

/// A bounded DC operating-point model for resistor/diode/grounded-emitter
/// transistor networks. The digital engine still handles clocks and gates.
struct DiscreteDC {
    private struct Device {
        enum Kind { case resistor(Double), diode, led, transistor(TransistorDefinition.NPNParameters) }
        let component: any LogicComponent
        let kind: Kind
        let nodes: [Int]
    }

    static func apply(components: [any LogicComponent], nets: [Net]) -> Set<ObjectIdentifier> {
        let hasLED = components.contains { $0 is LED3mm }
        let hasLegacyNetwork = components.contains { $0 is Transistor } && components.contains { $0 is Diode1N4148 }
        guard hasLED || hasLegacyNetwork else { return [] }
        var byPin: [ObjectIdentifier: Int] = [:]
        for (index, net) in nets.enumerated() {
            for pin in net.pins { byPin[ObjectIdentifier(pin)] = index }
        }
        var digitalCollectors: Set<Int> = []
        var regions: [(nodes: Set<Int>, devices: [Device])] = []
        for component in components {
            let kind: Device.Kind
            let pins: [Pin]
            if let transistor = component as? Transistor {
                switch transistor.definition.model {
                case .digitalHighSidePNP:
                    if let collector = byPin[ObjectIdentifier(transistor.pin(.collector))] {
                        digitalCollectors.insert(collector)
                    }
                    continue
                case .groundedNPN(let parameters):
                    kind = .transistor(parameters)
                    pins = [transistor.pin(.emitter), transistor.pin(.base), transistor.pin(.collector)]
                }
            } else {
                switch component {
                case let resistor as Resistor where !resistor.isTimingElement:
                    kind = .resistor(resistor.value * resistor.unit.multiplier)
                case let diode as Diode1N4148 where !diode.isTimingElement: kind = .diode
                case is LED3mm: kind = .led
                default: continue
                }
                pins = component.pins.values.sorted { $0.number < $1.number }
            }
            let nodes = pins.compactMap { byPin[ObjectIdentifier($0)] }
            guard nodes.count == pins.count else { continue }
            let device = Device(component: component, kind: kind, nodes: nodes)
            // A shared ideal supply does not couple otherwise independent regions.
            var joined = Set(nodes.filter { index in
                !nets[index].pins.contains { $0.drivenSupplyRail != nil }
            })
            var devices = [device]
            regions.removeAll { region in
                guard !region.nodes.isDisjoint(with: joined) else { return false }
                joined.formUnion(region.nodes)
                devices += region.devices
                return true
            }
            regions.append((joined, devices))
        }

        var modeled: Set<ObjectIdentifier> = []
        for (nodes, devices) in regions {
            // A digital-only collector cannot serve as a DC voltage source.
            guard nodes.isDisjoint(with: digitalCollectors) else { continue }
            let hasLED = devices.contains { if case .led = $0.kind { true } else { false } }
            let hasLegacyNetwork = devices.contains { if case .diode = $0.kind { true } else { false } } &&
                devices.contains { if case .transistor = $0.kind { true } else { false } }
            guard hasLED || hasLegacyNetwork, let voltages = solve(devices, nets: nets) else { continue }
            for device in devices {
                modeled.insert(ObjectIdentifier(device.component))
                for pin in device.component.pins.values { pin.drive(.highImpedance) }
            }
            for (index, volts) in voltages { nets[index].receiveDC(volts) }
        }
        return modeled
    }

    private static func solve(_ devices: [Device], nets: [Net]) -> [Int: Double]? {
        let ids = Set(devices.flatMap(\.nodes)).sorted()
        guard ids.count <= 32 else { return nil }
        let internalPins = Set(devices.flatMap { $0.component.pins.values.map(ObjectIdentifier.init) })
        var known: [Int: Double] = [:]
        for index in ids {
            for pin in nets[index].pins where !internalPins.contains(ObjectIdentifier(pin)) && pin.driveState != .highImpedance {
                guard !pin.isWeakDriver, pin.driveState == .low || pin.driveState == .high else { return nil }
                let voltage = pin.driveState == .high ? 5.0 : 0.0
                guard known[index].map({ $0 == voltage }) ?? true else { return nil }
                known[index] = voltage
            }
        }
        for device in devices {
            if case .transistor = device.kind, known[device.nodes[0]] != 0 { return nil }
        }
        // Require a resistive path to an ideal driver for each unknown node.
        // This keeps open circuits from acquiring arbitrary voltages.
        var anchored = Set(known.keys)
        for _ in ids {
            let count = anchored.count
            for device in devices {
                if case .resistor = device.kind, !anchored.isDisjoint(with: device.nodes) {
                    anchored.formUnion(device.nodes)
                }
            }
            if anchored.count == count { break }
        }
        guard anchored.isSuperset(of: ids) else { return nil }
        let unknown = ids.filter { known[$0] == nil }
        let row = Dictionary(uniqueKeysWithValues: unknown.enumerated().map { ($1, $0) })

        func residual(_ values: [Double]) -> [Double] {
            func voltage(_ node: Int) -> Double { row[node].map { values[$0] } ?? known[node]! }
            var balance = Array(repeating: 0.0, count: unknown.count)
            func current(_ milliamps: Double, from: Int, to: Int) {
                if let index = row[from] { balance[index] += milliamps }
                if let index = row[to] { balance[index] -= milliamps }
            }
            for device in devices {
                let a = device.nodes[0], b = device.nodes[1]
                switch device.kind {
                case .resistor(let ohms):
                    current((voltage(a) - voltage(b)) * 1000 / ohms, from: a, to: b)
                case .diode:
                    // 1N4148 nominal forward knee and slope in the sub-mA region.
                    let diodeCurrent = max(0, (voltage(b) - voltage(a) - 0.60) / 0.05)
                    current(diodeCurrent, from: b, to: a)
                case .led:
                    let milliamps = max(0, (voltage(b) - voltage(a) - LED3mm.forwardVoltage) / LED3mm.dynamicResistanceKilohms)
                    current(milliamps, from: b, to: a)
                case .transistor(let parameters):
                    let collector = device.nodes[2]
                    let baseCurrent = max(0, (voltage(b) - voltage(a) - parameters.baseKnee) / parameters.baseResistanceKilohms)
                    current(baseCurrent, from: b, to: a)
                    let activeCurrent = parameters.gain * baseCurrent
                    let saturationCurrent = max(0, (voltage(collector) - voltage(a)) / parameters.saturationResistanceKilohms)
                    // Smoothly limit the gain-controlled current by collector voltage.
                    let total = activeCurrent + saturationCurrent
                    let collectorCurrent = total > 0 ? activeCurrent * saturationCurrent / total : 0
                    current(collectorCurrent, from: collector, to: a)
                }
            }
            return balance
        }

        var values = Array(repeating: 2.5, count: unknown.count)
        for _ in 0..<40 {
            let balance = residual(values)
            let error = balance.map(abs).max() ?? 0
            if error < 1e-7 {
                for (index, node) in unknown.enumerated() { known[node] = values[index] }
                return known
            }
            var jacobian = Array(repeating: Array(repeating: 0.0, count: unknown.count), count: unknown.count)
            for column in unknown.indices {
                var perturbed = values
                perturbed[column] += 1e-6
                let samples = residual(perturbed)
                for index in unknown.indices {
                    jacobian[index][column] = (samples[index] - balance[index]) / 1e-6
                }
            }
            guard let step = linearSolve(jacobian, balance.map { -$0 }) else { return nil }
            var gain = 1.0
            var improved = false
            for _ in 0..<20 {
                let trial = zip(values, step).map { min(5, max(0, $0 + $1 * gain)) }
                if (residual(trial).map(abs).max() ?? 0) < error {
                    values = trial
                    improved = true
                    break
                }
                gain *= 0.5
            }
            guard improved else { return nil }
        }
        return nil
    }

    private static func linearSolve(_ matrix: [[Double]], _ target: [Double]) -> [Double]? {
        var rows = zip(matrix, target).map { $0 + [$1] }
        for column in rows.indices {
            guard let pivot = (column..<rows.count).max(by: { abs(rows[$0][column]) < abs(rows[$1][column]) }),
                  abs(rows[pivot][column]) > 1e-12 else { return nil }
            rows.swapAt(column, pivot)
            let scale = rows[column][column]
            for index in column...rows.count { rows[column][index] /= scale }
            for row in rows.indices where row != column {
                let factor = rows[row][column]
                for index in column...rows.count { rows[row][index] -= factor * rows[column][index] }
            }
        }
        return rows.map { $0.last! }
    }
}
