import SwiftUI

struct ComponentLibraryView: View {
    let bench: Workbench
    let placeNewPart: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var search = ""
    @State private var selection: Entry?
    @State private var chipsExpanded = true
    @State private var discreteExpanded = true
    @State private var sourcesExpanded = true

    private enum Entry: Hashable, Identifiable {
        case chip(MultiUnitChip)
        case chipPower(MultiUnitChip, Int, String)
        case displayDriver(SevenSegmentDriverKind)
        case sevenSegmentDisplay, commonAnodeDisplay
        case power(PowerRail)
        case additionalCounter(CounterChip)
        case analogSwitch(AnalogSwitchKind)
        case capacitor(CapacitorKind)
        case pinHeader(PinHeaderKind)
        case cd4070, timer555, counter, rippleCounter, transistor, resistor, diode, logicSwitch, logicInput, clock, oscillatorDIP8, led, led3mm, pullUp

        var id: Self { self }

        var name: String {
            switch self {
            case .chip(.xor): "CD4070 XOR Gate"
            case .chip(let kind): kind.partName
            case .chipPower(let kind, _, let reference): "\(kind.partName) \(reference)"
            case .cd4070: "CD4070"
            case .timer555: "NE555"
            case .counter: "CD4510"
            case .additionalCounter(let kind): kind.rawValue
            case .analogSwitch(let kind): kind.rawValue
            case .displayDriver(let kind): kind.rawValue
            case .sevenSegmentDisplay: "MAN74A"
            case .commonAnodeDisplay: "MAN72A"
            case .rippleCounter: "CD4060"
            case .transistor: "2N3904"
            case .capacitor(let kind): kind.rawValue
            case .pinHeader(let kind): kind.name
            case .resistor: "R_Small"
            case .diode: "1N4148"
            case .pullUp: "Logic Pull-up"
            case .power(let rail): rail.rawValue
            case .logicSwitch: "Logic Switch"
            case .logicInput: "Logic Input"
            case .clock: "Clock Source"
            case .oscillatorDIP8: "CXO_DIP8"
            case .led: "Logic LED"
            case .led3mm: "LED_D3.0mm"
            }
        }

        var detail: String {
            switch self {
            case .chip(.xor): "Individually placed XOR gate"
            case .chip(let kind): kind.unitName
            case .chipPower: "Shared Power Unit · VDD / VSS"
            case .cd4070: "Four XOR gates and power · Switchable DIP-14"
            case .timer555: "Timer · Digital inputs or standard RC astable/monostable"
            case .counter: "BCD Up/Down Counter"
            case .additionalCounter(let kind): kind.detail
            case .analogSwitch(let kind): kind.detail
            case .displayDriver: "BCD to Seven-Segment Latch and Driver"
            case .sevenSegmentDisplay: "Single Digit LED Display · Common Cathode"
            case .commonAnodeDisplay: "Single Digit LED Display · Common Anode"
            case .rippleCounter: "14-stage Binary Counter"
            case .transistor: "NPN Transistor (Digital Switch)"
            case .capacitor(let kind): "Capacitor · \(kind.unit) · NE555 RC timing"
            case .pinHeader(let kind): "Vertical · 2.54 mm · \(kind.footprint)"
            case .resistor: "Resistor"
            case .diode: "Switching Diode"
            case .pullUp: "Weak HIGH for open-collector outputs"
            case .power(.fiveVolts): "Power supply · Logic HIGH"
            case .power(.ground): "Ground · Logic LOW"
            case .logicSwitch: "Manual HIGH or LOW output"
            case .logicInput: "Click to toggle 0 (LOW) or 1 (HIGH)"
            case .clock: "Square wave · Hz, kHz, or MHz"
            case .oscillatorDIP8: "Crystal oscillator · kHz or MHz"
            case .led: "Digital state indicator"
            case .led3mm: "3 mm through-hole LED · \(LED3mm.footprint)"
            }
        }

        var icon: String {
            switch self {
            case .chip, .chipPower, .cd4070, .timer555, .counter, .rippleCounter, .displayDriver, .additionalCounter, .analogSwitch: "cpu"
            case .transistor: "circle.branch"
            case .pinHeader: "circle.grid.2x2"
            case .capacitor, .resistor, .diode: "point.topleft.down.to.point.bottomright.curvepath"
            case .pullUp, .power(.fiveVolts): "arrow.up"
            case .power(.ground): "arrow.down"
            case .logicSwitch: "switch.2"
            case .logicInput: "0.square"
            case .clock, .oscillatorDIP8: "waveform.path"
            case .led, .led3mm: "lightbulb"
            case .sevenSegmentDisplay, .commonAnodeDisplay: "number.square"
            }
        }

        func matches(_ search: String) -> Bool {
            let description = "\(name) \(detail)"
            return search.split(whereSeparator: \.isWhitespace).allSatisfy {
                description.localizedCaseInsensitiveContains(String($0))
            }
        }
    }

    private var chips: [Entry] {
        (MultiUnitChip.allCases.map(Entry.chip) + [.cd4070, .timer555, .counter, .rippleCounter]
            + SevenSegmentDriverKind.allCases.map(Entry.displayDriver)
            + CounterChip.allCases.map(Entry.additionalCounter)
            + AnalogSwitchKind.allCases.map(Entry.analogSwitch)
            + MultiUnitChip.allCases.flatMap { kind in
                bench.packages(for: kind).filter {
                    bench.availableUnits(in: $0, kind: kind).contains(kind.powerUnit)
                }.map { package in
                    let unit = ChipUnitPlacement(kind: kind, packageID: package, unit: kind.powerUnit)
                    return Entry.chipPower(kind, package, bench.reference(for: unit))
                }
            })
            .sorted { $0.name < $1.name }
            .filter { $0.matches(search) }
    }

    private var discreteComponents: [Entry] {
        ([Entry.transistor, .resistor, .diode, .capacitor(.polarized), .capacitor(.small)]
            + PinHeaderKind.allCases.map(Entry.pinHeader)).filter { $0.matches(search) }
    }

    private var sourcesAndIndicators: [Entry] {
        [Entry.power(.fiveVolts), .power(.ground), .logicSwitch, .logicInput, .clock, .oscillatorDIP8, .led, .led3mm, .sevenSegmentDisplay, .commonAnodeDisplay, .pullUp].filter { $0.matches(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Component Library")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            TextField("Search components", text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onChange(of: search) {
                    if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        chipsExpanded = true
                        discreteExpanded = true
                        sourcesExpanded = true
                    }
                    if selection?.matches(search) != true {
                        selection = nil
                    }
                }

            List(selection: $selection) {
                if !chips.isEmpty {
                    Section("Chips", isExpanded: $chipsExpanded) { rows(chips) }
                }
                if !discreteComponents.isEmpty {
                    Section("Discrete Components", isExpanded: $discreteExpanded) { rows(discreteComponents) }
                }
                if !sourcesAndIndicators.isEmpty {
                    Section("Sources and Indicators", isExpanded: $sourcesExpanded) { rows(sourcesAndIndicators) }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if chips.isEmpty && discreteComponents.isEmpty && sourcesAndIndicators.isEmpty {
                    ContentUnavailableView("No Matching Components", systemImage: "magnifyingglass")
                }
            }

            if case .chip(let kind) = selection, let next = bench.nextUnit(for: kind) {
                LabeledContent("Next unit", value: bench.reference(for: next))
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: addSelection)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 520, height: 540)
        .defaultFocus($searchFocused, true)
    }

    private func rows(_ entries: [Entry]) -> some View {
        ForEach(entries) { entry in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: entry.icon)
            }
            .padding(.vertical, 4)
            .tag(entry)
        }
    }

    private func addSelection() {
        guard let selection else { return }

        let previousID = bench.parts.last?.id
        switch selection {
        case .chip(let kind):
            bench.addNextUnit(for: kind)
        case .chipPower(let kind, let package, _):
            bench.addUnit(kind.powerUnit, kind: kind, to: package)
        case .analogSwitch(let kind):
            bench.add(kind.rawValue, component: AnalogSwitch(kind))
        case .additionalCounter(let kind):
            bench.add(kind.rawValue, component: kind.makeComponent())
        case .cd4070:
            bench.add("CD4070", component: CD4070())
        case .timer555:
            bench.add("NE555", component: NE555())
        case .counter:
            bench.add("CD4510", component: CD4510())
        case .rippleCounter:
            bench.add("CD4060", component: CD4060())
        case .displayDriver(let kind):
            bench.add(kind.rawValue, component: SevenSegmentDriver(kind))
        case .sevenSegmentDisplay:
            bench.add("MAN74A", component: MAN74A())
        case .commonAnodeDisplay:
            bench.add("MAN72A", component: MAN72A())
        case .transistor:
            bench.add("2N3904", component: NPN2N3904())
        case .capacitor(let kind):
            bench.add(kind.rawValue, component: Capacitor(kind))
        case .pinHeader(let kind):
            bench.add(kind.name, component: PinHeader(kind))
        case .resistor:
            bench.add("Resistor", component: Resistor())
        case .diode:
            bench.add("1N4148", component: Diode1N4148())
        case .power(let rail):
            bench.add(rail.rawValue, component: WorkbenchPower(rail))
        case .pullUp:
            bench.add("Pull-up", component: WorkbenchPullUp())
        case .logicSwitch:
            bench.add("Switch", component: WorkbenchSwitch())
        case .logicInput:
            bench.add("Logic Input", component: WorkbenchSwitch(showsValue: true))
        case .clock:
            bench.add("Clock", component: WorkbenchClock())
        case .oscillatorDIP8:
            bench.add("CXO_DIP8", component: CXO_DIP8())
        case .led:
            bench.add("LED", component: WorkbenchLED())
        case .led3mm:
            bench.add("LED_D3.0mm", component: LED3mm())
        }
        if let id = bench.parts.last?.id, id != previousID { placeNewPart(id) }
        dismiss()
    }
}
