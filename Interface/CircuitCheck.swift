struct CircuitFinding: Identifiable {
    enum Target: Hashable {
        case pin(WorkbenchTerminal)
        case wire(Int)
    }

    struct ID: Hashable {
        let rule: String
        let target: Target
    }

    let id: ID
    let title: String
    let location: String
    let state: LogicState
    let suggestion: String

    var target: Target { id.target }
}

extension Workbench {
    func checkCircuit() -> [CircuitFinding] {
        var findings: [CircuitFinding] = []

        func pin(_ part: WorkbenchPart, _ number: Int) -> WorkbenchTerminal {
            WorkbenchTerminal(partID: part.id, pinNumber: number)
        }

        func report(_ rule: String, _ terminal: WorkbenchTerminal, _ title: String, _ suggestion: String) {
            findings.append(CircuitFinding(id: .init(rule: rule, target: .pin(terminal)),
                                           title: title, location: label(for: terminal),
                                           state: readings[terminal, default: .highImpedance], suggestion: suggestion))
        }

        var checkedNets: Set<ObjectIdentifier> = []
        for wire in wires.sorted(by: { ($0.sourceRoute == .pinAttachment ? 1 : 0, $0.id) < ($1.sourceRoute == .pinAttachment ? 1 : 0, $1.id) })
            where wire.sourceRoute != .alias {
            guard let net = circuitNet(at: wire.first), checkedNets.insert(ObjectIdentifier(net)).inserted,
                  net.state == .undefined else { continue }
            let strongDrivers = net.pins.filter { !$0.isWeakDriver }
            guard strongDrivers.contains(where: { $0.driveState == .high }),
                  strongDrivers.contains(where: { $0.driveState == .low }) else { continue }
            let suggestion = "Separate the HIGH and LOW drivers, or arrange for only one driver to be active at a time."
            if wire.sourceRoute == .pinAttachment,
               let terminal = [wire.first, wire.second].first(where: { !$0.isJunction }) {
                report("contention", terminal, "Opposing outputs share a net", suggestion)
                continue
            }
            findings.append(CircuitFinding(
                id: .init(rule: "contention", target: .wire(wire.id)),
                title: "Opposing outputs share a net",
                location: "\(label(for: wire.first)) ↔ \(label(for: wire.second))", state: net.state,
                suggestion: suggestion
            ))
        }

        let counters = parts.filter { $0.component is CD4026 }
        for part in parts {
            if powerMode == .explicit, let chip = part.component as? any PoweredChip {
                let supplies = [(chip.supplyPins.vdd, LogicState.high, SupplyRail.fiveVolts)] +
                    ([chip.supplyPins.vss] + chip.additionalGroundPins).map { ($0, .low, .ground) }
                for (number, level, rail) in supplies {
                    guard let supply = part.pins[number], supply.state != level || supply.supplyRail != rail else { continue }
                    let source = rail == .fiveVolts ? "+5 V" : "GND"
                    report("supply", pin(part, number), "Supply pin needs \(source)",
                           "Connect this pin to a \(source) rail and remove any conflicting connection.")
                }
            }
            if let issue = timingIssues[part.id] {
                report("timer", pin(part, 7), "NE555 timing network issue", issue)
            }
            if part.component is CD4026 {
                let controls: [(Int, LogicState, String, String)] = [
                    (2, .high, "Clock is inhibited", "Drive Clock Inhibit (pin 2) LOW to allow counting."),
                    (3, .low, "Segment outputs are disabled", "Drive Display Enable (pin 3) HIGH to show the count."),
                    (15, .high, "Counter is held in reset", "Set Reset (pin 15) LOW to let the counter run.")
                ]
                for (number, asserted, title, suggestion) in controls {
                    let terminal = pin(part, number)
                    let state = readings[terminal, default: .highImpedance]
                    if state == .highImpedance || state == .undefined {
                        report("control", terminal, state == .highImpedance ? "Control input is floating" : "Control input is undefined",
                               suggestion)
                    } else if state == asserted {
                        report("control", terminal, title, suggestion)
                    }
                }
                let clock = pin(part, 1)
                let state = readings[clock, default: .highImpedance]
                if state == .highImpedance || state == .undefined {
                    report("clock", clock, "Clock input needs a defined signal",
                           "Connect a Clock Source output to CLK (pin 1) and run the clock.")
                }
            }
            guard let display = part.component as? SevenSegmentDisplay else { continue }
            let commonLevel: LogicState = display.commonAnode ? .high : .low
            for number in display.commonNumbers where readings[pin(part, number)] != commonLevel {
                let source = display.commonAnode ? "+5 V" : "GND"
                report("common", pin(part, number), "Display common needs \(source)",
                       "Connect the display common to \(source).")
            }
            guard !display.commonAnode else { continue }
            let segments = display.segmentNumbers.prefix(7).map { pin(part, $0) }
            let displayNets = segments.map(circuitNet)
            let matches = counters.map { counter in
                let outputs = CD4026.segmentPins.map { pin(counter, $0) }
                let matchingNets = zip(displayNets, outputs).compactMap { net, output -> ObjectIdentifier? in
                    guard let net, net === circuitNet(at: output) else { return nil }
                    return ObjectIdentifier(net)
                }
                return (outputs: outputs, count: Set(matchingNets).count)
            }.sorted { $0.count > $1.count }
            // Require a majority of matching segments before inferring the display's intended driver.
            guard let best = matches.first, best.count >= 4, matches.dropFirst().first?.count != best.count else { continue }
            for (terminal, output) in zip(segments, best.outputs) {
                let expected = circuitNet(at: output)
                if expected == nil || circuitNet(at: terminal) !== expected {
                    report("segment", terminal, "Segment is on a different net",
                           "If this digit should show the counter, remove any other driver from this segment and connect it to \(label(for: output)).")
                }
            }
        }
        return findings
    }

    func currentState(for finding: CircuitFinding) -> LogicState? {
        switch finding.target {
        case .pin(let terminal):
            return readings[terminal]
        case .wire(let id):
            guard let wire = wires.first(where: { $0.id == id }) else { return nil }
            return readings[wire.first] ?? readings[wire.second] ?? circuitNet(at: wire.first)?.state
        }
    }
}
