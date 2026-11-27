import SwiftUI

struct ComponentLibraryView: View {
    let bench: Workbench
    let placeNewPart: (Int) -> Void
    let showOscilloscope: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var search = ""
    @State private var selection: Entry?
    @State private var collapsed: Set<Family> = []

    private enum Family: String, CaseIterable, Identifiable {
        case cmos4000 = "4000 Series CMOS"
        case hc = "74HC Series CMOS"
        case ls = "74LS Series TTL"
        case discrete = "Discrete Semiconductors"
        case passives = "Passive Components"
        case switches = "Switches"
        case displays = "Displays"
        case sources = "Sources"
        case instruments = "Instruments"
        case timers = "Timers"
        case connectors = "Connectors"

        var id: Self { self }
    }

    private enum Entry: Hashable, Identifiable {
        case hcPackage(HCGatePackage)
        case chip(MultiUnitChip)
        case chipPower(MultiUnitChip, Int, String)
        case displayDriver(SevenSegmentDriverKind)
        case sevenSegmentDisplay, commonAnodeDisplay
        case power(PowerRail)
        case additionalCounter(CounterChip)
        case analogSwitch(AnalogSwitchKind)
        case capacitor(CapacitorKind)
        case pinHeader(PinHeaderKind)
        case cd4011, cd40106, cd4027, cd4070, cd4081, hc08, cd4518, timer555, counter, rippleCounter, transistor, resistor, diode, logicSwitch, logicInput, clock, oscillatorDIP8, led, led3mm, mechanicalSwitch, oscilloscope

        var id: Self { self }

        var name: String {
            switch self {
            case .chip(.xor): "CD4070 XOR Gate"
            case .chip(let kind): kind.partName
            case .chipPower(let kind, _, let reference): "\(kind.partName) \(reference)"
            case .cd4011: "CD4011"
            case .cd40106: "CD40106"
            case .cd4027: "CD4027 Package"
            case .cd4518: "CD4518 Package"
            case .cd4070: "CD4070"
            case .cd4081: "CD4081 Package"
            case .hc08: "74HC08 Package"
            case .hcPackage(let package): "\(package.rawValue) Package"
            case .timer555: "NE555"
            case .counter: "CD4510"
            case .additionalCounter(let kind): kind.rawValue
            case .analogSwitch(let kind): kind.rawValue
            case .displayDriver(let kind): kind.rawValue
            case .sevenSegmentDisplay: "MAN74A"
            case .commonAnodeDisplay: "MAN72A"
            case .rippleCounter: "CD4060"
            case .transistor: "Transistor"
            case .capacitor(let kind): kind.rawValue
            case .pinHeader(let kind): kind.name
            case .resistor: "R_Small"
            case .diode: "1N4148"
            case .mechanicalSwitch: "Switch"
            case .power(let rail): rail.rawValue
            case .logicSwitch: "Logic Switch"
            case .logicInput: "Logic Input"
            case .clock: "Clock Source"
            case .oscillatorDIP8: "CXO_DIP8"
            case .led: "Logic LED"
            case .led3mm: "LED_D3.0mm"
            case .oscilloscope: "Oscilloscope"
            }
        }

        var detail: String {
            switch self {
            case .chip(.xor): "Individually placed XOR gate"
            case .chip(let kind): kind.unitName
            case .chipPower(let kind, _, _) where kind.is74HC: "Shared Power Unit · VCC / GND"
            case .chipPower: "Shared Power Unit · VDD / VSS"
            case .cd4011: "Four NAND gates and power · Switchable DIP-14"
            case .cd40106: "Six Schmitt-trigger inverters and power · Switchable DIP-14"
            case .cd4027: "Two J-K flip-flops and power · Switchable DIP-16"
            case .cd4518: "Two BCD counters and power · Switchable DIP-16"
            case .cd4070: "Four XOR gates and power · Switchable DIP-14"
            case .hcPackage(let package):
                "\(MultiUnitChip(package).unitName) units and power · Switchable DIP-14"
            case .cd4081, .hc08: "Four AND gates and power · Switchable DIP-14"
            case .timer555: "Timer · Digital inputs or standard RC astable/monostable"
            case .counter: "BCD Up/Down Counter"
            case .additionalCounter(let kind): kind.detail
            case .analogSwitch(let kind): kind.detail
            case .displayDriver: "BCD to Seven-Segment Latch and Driver"
            case .sevenSegmentDisplay: "Single Digit LED Display · Common Cathode"
            case .commonAnodeDisplay: "Single Digit LED Display · Common Anode"
            case .rippleCounter: "14-stage Binary Counter"
            case .transistor: "TO-92 · Default \(TransistorDesignation.defaultDevice.rawValue)"
            case .capacitor(let kind): "Capacitor · \(kind.unit) · NE555 RC timing"
            case .pinHeader(let kind): "Vertical · 2.54 mm · \(kind.footprint)"
            case .resistor: "Resistor"
            case .diode: "Switching Diode"
            case .mechanicalSwitch: "Normally Open Push Button · Selectable SPDT"
            case .power(.fiveVolts): "Power supply · Logic HIGH"
            case .power(.ground): "Ground · Logic LOW"
            case .logicSwitch: "Manual HIGH or LOW output"
            case .logicInput: "Click to toggle 0 (LOW) or 1 (HIGH)"
            case .clock: "Square wave · Hz, kHz, or MHz"
            case .oscillatorDIP8: "Crystal oscillator · kHz or MHz"
            case .led: "Digital state indicator"
            case .oscilloscope: "Open the workbench instrument"
            case .led3mm: "3 mm through-hole LED · \(LED3mm.footprint)"
            }
        }

        var icon: String {
            switch self {
            case .hcPackage, .chip, .chipPower, .cd4011, .cd40106, .cd4027, .cd4070, .cd4081, .hc08, .cd4518, .timer555, .counter, .rippleCounter, .displayDriver, .additionalCounter, .analogSwitch: "cpu"
            case .transistor: "circle.branch"
            case .pinHeader: "circle.grid.2x2"
            case .capacitor, .resistor, .diode: "point.topleft.down.to.point.bottomright.curvepath"
            case .power(.fiveVolts): "arrow.up"
            case .power(.ground): "arrow.down"
            case .logicSwitch, .mechanicalSwitch: "switch.2"
            case .logicInput: "0.square"
            case .clock, .oscillatorDIP8, .oscilloscope: "waveform.path"
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

    private func chipEntries(_ kinds: [MultiUnitChip]) -> [Entry] {
        kinds.flatMap { kind in
            [.chip(kind)] + bench.packages(for: kind).compactMap { package in
                guard bench.availableUnits(in: package, kind: kind).contains(kind.powerUnit) else { return nil }
                let unit = ChipUnitPlacement(kind: kind, packageID: package, unit: kind.powerUnit)
                return .chipPower(kind, package, bench.reference(for: unit))
            }
        }
    }

    private func entries(in family: Family) -> [Entry] {
        let entries: [Entry]
        switch family {
        case .cmos4000:
            entries = chipEntries(MultiUnitChip.allCases.filter { !$0.is74HC })
                + [.cd4011, .cd40106, .cd4027, .cd4070, .cd4081, .cd4518, .counter, .rippleCounter]
                + SevenSegmentDriverKind.allCases.map(Entry.displayDriver)
                + CounterChip.allCases.filter { !$0.isTTL }.map(Entry.additionalCounter)
                + AnalogSwitchKind.allCases.map(Entry.analogSwitch)
        case .hc:
            let kinds = MultiUnitChip.allCases.filter(\.is74HC)
            entries = chipEntries(kinds) + [.hc08] + kinds.compactMap { $0.hcPackage.map(Entry.hcPackage) }
        case .ls: entries = CounterChip.allCases.filter(\.isTTL).map(Entry.additionalCounter)
        case .discrete: entries = [.transistor, .diode, .led3mm]
        case .passives: entries = [.resistor, .capacitor(.polarized), .capacitor(.small)]
        case .switches: entries = [.mechanicalSwitch, .logicSwitch]
        case .displays: entries = [.led, .sevenSegmentDisplay, .commonAnodeDisplay]
        case .sources: entries = [.power(.fiveVolts), .power(.ground), .logicInput, .clock, .oscillatorDIP8]
        case .instruments: entries = [.oscilloscope]
        case .timers: entries = [.timer555]
        case .connectors: entries = PinHeaderKind.allCases.map(Entry.pinHeader)
        }
        return entries.filter { $0.matches(search) }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func expanded(_ family: Family) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(family) }, set: { isExpanded in
            if isExpanded { collapsed.remove(family) } else { collapsed.insert(family) }
        })
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
                        collapsed.removeAll()
                    }
                    if selection?.matches(search) != true {
                        selection = nil
                    }
                }

            List(selection: $selection) {
                ForEach(Family.allCases) { family in
                    let matches = entries(in: family)
                    if !matches.isEmpty {
                        Section(family.rawValue, isExpanded: expanded(family)) { rows(matches) }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if Family.allCases.allSatisfy({ entries(in: $0).isEmpty }) {
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
                Button(selection == .oscilloscope ? "Open" : "Add", action: addSelection)
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
        case .oscilloscope:
            dismiss()
            showOscilloscope()
            return
        case .chip(let kind):
            bench.addNextUnit(for: kind)
        case .chipPower(let kind, let package, _):
            bench.addUnit(kind.powerUnit, kind: kind, to: package)
        case .analogSwitch(let kind):
            bench.add(kind.rawValue, component: AnalogSwitch(kind))
        case .additionalCounter(let kind):
            bench.add(kind.rawValue, component: kind.makeComponent())
        case .cd4011:
            bench.add("CD4011", component: CD4011())
        case .cd40106:
            bench.add("CD40106", component: CD40106())
        case .cd4518:
            bench.add("CD4518", component: DualCounter(.bcd))
        case .cd4027:
            bench.add("CD4027", component: CD4027())
        case .cd4070:
            bench.add("CD4070", component: CD4070())
        case .hc08:
            bench.add("74HC08", component: SN74HC08())
        case .hcPackage(let package):
            bench.add(package.rawValue, component: package.makeComponent())
        case .cd4081:
            bench.add("CD4081", component: CD4081())
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
            bench.add("Transistor", component: Transistor())
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
        case .mechanicalSwitch:
            bench.add("Switch", component: MechanicalSwitch())
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
