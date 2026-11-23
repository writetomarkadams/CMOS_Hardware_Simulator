import CoreGraphics
import Foundation
import Testing
@testable import CMOS4000Simulator

@MainActor
struct WorkbenchSelectionTests {
    private func terminal(_ part: Int, _ pin: Int = 1) -> WorkbenchTerminal {
        WorkbenchTerminal(partID: part, pinNumber: pin)
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private func location(_ endpoint: WorkbenchTerminal, in bench: Workbench,
                          appearance: ComponentAppearance = .schematic) throws -> CGPoint {
        if endpoint.isJunction { return try #require(bench.junctions[endpoint.pinNumber]) }
        let part = try #require(bench.parts.first { $0.id == endpoint.partID })
        let turns = bench.rotations[part.id, default: 0]
        let position = try #require(bench.positions[part.id])
        let geometry = SchematicPartGeometry(part: part, turns: turns, appearance: appearance)
        return try #require(geometry.location(of: endpoint.pinNumber, at: position, turns: turns,
                                               imported: part.importedSymbol != nil))
    }

    private func connect(_ bench: Workbench, _ first: WorkbenchTerminal, _ second: WorkbenchTerminal,
                         bend: CGPoint? = nil) {
        bench.select(first)
        if let bend { bench.addBend(at: bend) }
        bench.select(second)
    }

    @Test func groupMovesInternalGeometryAndReroutesBoundary() throws {
        let bench = Workbench()
        bench.add("Switch", component: WorkbenchSwitch(showsValue: true))
        bench.add("LED", component: WorkbenchLED())
        bench.add("LED", component: WorkbenchLED())
        bench.add("Ground", component: WorkbenchPower(.ground))
        bench.add("LED", component: WorkbenchLED())
        bench.placeNewPart(1, at: point(20, 40))
        bench.placeNewPart(2, at: point(220, 40))
        bench.placeNewPart(3, at: point(240, 200))
        bench.placeNewPart(4, at: point(140, 10))
        bench.placeNewPart(5, at: point(140, 300))
        bench.rotatePart(2, by: 1)
        connect(bench, terminal(1), terminal(2), bend: point(230, 100))
        let wireID = try #require(bench.wires.first?.id)
        let junction = point(230, 100)
        bench.select(terminal(3))
        bench.joinWire(wireID, at: junction, before: [point(190, 100)], after: [point(260, 100)])
        connect(bench, terminal(4), terminal(5), bend: point(280, 200))

        let originalJunction = try #require(bench.junctions.first)
        let originalPositions = bench.positions
        let originalWires = bench.wires
        let originalRoutes = try originalWires.map {
            try $0.route(from: location($0.first, in: bench), to: location($0.second, in: bench))
        }
        let movement = bench.movement(of: [1, 2], by: CGSize(width: 36, height: 64))
        #expect(movement.delta == point(40, 60))
        #expect(movement.junctions == [originalJunction.key])
        bench.moveParts(movement)
        #expect(bench.positions[1] == point(60, 100))
        #expect(bench.positions[2] == point(260, 100))
        #expect(bench.positions[3] == originalPositions[3])
        #expect(bench.junctions[originalJunction.key] == point(270, 160))
        for (index, wire) in bench.wires.enumerated() {
            #expect(wire.id == originalWires[index].id)
            #expect(wire.first == originalWires[index].first)
            #expect(wire.second == originalWires[index].second)
            let route = try wire.route(from: location(wire.first, in: bench), to: location(wire.second, in: bench))
            if movement.includes(wire.first) && movement.includes(wire.second) {
                #expect(route == originalRoutes[index].map(movement.translate))
            } else {
                #expect(wire.bends == originalWires[index].bends)
            }
            #expect(zip(route, route.dropFirst()).allSatisfy { $0.x == $1.x || $0.y == $1.y })
        }
        let source = try #require(bench.parts[0].component as? WorkbenchSwitch)
        bench.toggle(source)
        #expect(bench.parts[1].pins[1]?.state == .high)
        #expect(bench.parts[2].pins[1]?.state == .high)
        #expect(bench.parts[4].pins[1]?.state == .low)
        bench.undo()
        bench.undo()
        #expect(bench.positions == originalPositions)
        #expect(bench.junctions[originalJunction.key] == junction)
        #expect(bench.wires.map(\.bends) == originalWires.map(\.bends))
        bench.redo()
        #expect(bench.positions[1] == point(60, 100))
        #expect(bench.junctions[originalJunction.key] == point(270, 160))
    }

    @Test func pasteOnlyCopiesInternalNetsAndUndoRedoRestoresTopology() throws {
        let bench = Workbench()
        bench.add("Switch", component: WorkbenchSwitch(showsValue: true))
        bench.add("LED", component: WorkbenchLED())
        bench.add("LED", component: WorkbenchLED())
        bench.placeNewPart(1, at: point(20, 20))
        bench.placeNewPart(2, at: point(180, 20))
        bench.placeNewPart(3, at: point(180, 200))
        bench.setLEDColour(.red, for: 2)
        bench.rotatePart(2, by: 1)
        connect(bench, terminal(1), terminal(2))
        let wireID = try #require(bench.wires.first?.id)
        bench.select(terminal(3))
        bench.joinWire(wireID, at: point(220, 100), before: [], after: [])
        let archive = try bench.copyParts([1, 2])
        let clipboard = try JSONDecoder().decode(WorkbenchArchive.self, from: archive.encoded())
        // Exact geometric overlap still creates electrically independent copies.
        let copies = try bench.pasteParts(clipboard, by: .zero).sorted()
        #expect(copies == [4, 5])
        #expect(bench.ledColours[5] == .red)
        #expect(bench.rotations[5] == 1)
        #expect(bench.positions[5] == bench.positions[2])
        #expect(bench.wires.count == 5)
        #expect(bench.junctions.count == 2)
        let source = try #require(bench.parts[0].component as? WorkbenchSwitch)
        let copiedSource = try #require(bench.parts[3].component as? WorkbenchSwitch)
        #expect(source !== copiedSource)
        bench.toggle(copiedSource)
        #expect(bench.parts[4].pins[1]?.state == .high)
        #expect(bench.parts[1].pins[1]?.state == .low)
        #expect(bench.parts[2].pins[1]?.state == .low)
        bench.undo()
        bench.undo()
        #expect(bench.parts.count == 3)
        #expect(bench.wires.count == 3)
        bench.redo()
        #expect(bench.parts.count == 5)
        #expect(bench.wires.count == 5)
        let single = try bench.copyParts([2])
        #expect(single.wires.isEmpty && single.junctions.isEmpty)
        let reopened = Workbench()
        try reopened.open(WorkbenchArchive(bench: bench))
        #expect(reopened.parts.map(\.reference) == bench.parts.map(\.reference))
        #expect(reopened.wires.count == 5)
        bench.removeParts(Set(copies))
        #expect(bench.parts.count == 3)
        bench.undo()
        #expect(bench.parts.count == 5)
        #expect(bench.wires.count == 5)
        bench.redo()
        #expect(bench.parts.count == 3)
    }

    @Test func danglingJunctionRouteCopiesWithItsSelectedCircuit() throws {
        let bench = Workbench()
        bench.add("Switch", component: WorkbenchSwitch())
        bench.add("LED", component: WorkbenchLED())
        bench.add("LED", component: WorkbenchLED())
        connect(bench, terminal(1), terminal(2))
        let wire = try #require(bench.wires.first)
        bench.select(terminal(3))
        bench.joinWire(wire.id, at: point(100, 100), before: [point(80, 100)], after: [])
        let junction = try #require(bench.junctions.first)
        bench.removeParts([2, 3])
        try #require(bench.wires.count == 1)

        let archive = try bench.copyParts([1])
        let clipboard = try JSONDecoder().decode(WorkbenchArchive.self, from: archive.encoded())
        let copies = try bench.pasteParts(clipboard, by: CGSize(width: 36, height: -64))
        let original = try #require(bench.wires.first)
        let duplicate = try #require(bench.wires.dropFirst().first)
        #expect(duplicate.id != original.id)
        #expect(copies.contains(duplicate.first.partID))
        #expect(duplicate.second.isJunction && duplicate.second != original.second)
        #expect(bench.junctions[junction.key] == point(100, 100))
        #expect(bench.junctions[duplicate.second.pinNumber] == point(140, 40))
        #expect(duplicate.bends == [point(120, 40)])
        let originalNet = try #require(bench.circuitNet(at: original.first))
        let copiedNet = try #require(bench.circuitNet(at: duplicate.first))
        #expect(originalNet !== copiedNet)
    }

    @Test func displayChainCopiesWithIndependentSignalAndPowerNets() throws {
        let bench = Workbench(timeSource: { 0 })
        bench.add("CD4510", component: CD4510())
        bench.add("CD4511", component: SevenSegmentDriver(.cd4511))
        bench.add("MAN74A", component: MAN74A())
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        bench.add("Clock", component: WorkbenchClock())
        bench.setPowerMode(.explicit)
        for id in 1...6 {
            bench.placeNewPart(id, at: point(CGFloat(id) * 220, 100))
        }
        bench.rotatePart(2, by: 1)
        bench.newWireColour = .blue
        for (output, input) in zip([6, 11, 14, 2], [7, 1, 2, 6]) {
            connect(bench, terminal(1, output), terminal(2, input), bend: point(460, 280))
        }
        for (output, segment) in zip([13, 12, 11, 10, 9, 15, 14], [14, 13, 8, 7, 6, 1, 2]) {
            connect(bench, terminal(2, output), terminal(3, segment))
        }
        connect(bench, terminal(4), terminal(1, 16))
        let supplyWire = try #require(bench.wires.last)
        bench.select(terminal(2, 16))
        bench.joinWire(supplyWire.id, at: point(350, 60), before: [point(400, 60)], after: [])
        for pin in [4, 12] {
            connect(bench, terminal(5), terminal(3, pin))
        }
        connect(bench, terminal(5), terminal(1, 8))
        connect(bench, terminal(5), terminal(2, 8))
        connect(bench, terminal(6), terminal(1, 15))
        let originalWires = bench.wires
        let originalJunction = try #require(bench.junctions.first)
        let originalPositions = bench.positions
        let originalData = try WorkbenchArchive(bench: bench).encoded()

        let selection = try bench.copyParts([1, 2, 3, 4, 5])
        let clipboard = try JSONDecoder().decode(WorkbenchArchive.self, from: selection.encoded())
        #expect(try WorkbenchArchive(bench: bench).encoded() == originalData)
        let copies = try bench.pasteParts(clipboard, by: CGSize(width: -473, height: 324)).sorted()
        #expect(copies.count == 5)
        let ids = Dictionary(uniqueKeysWithValues: zip(1...5, copies))
        let copiedWires = Array(bench.wires.dropFirst(originalWires.count))
        let copiedJunctions = bench.junctions.filter { $0.key != originalJunction.key }
        let copiedJunction = try #require(copiedJunctions.first)
        #expect(copiedJunctions.count == 1)
        #expect(copiedJunction.value == point(-120, 380))
        #expect(copiedWires.count == originalWires.count - 1)
        #expect(bench.wires.prefix(originalWires.count).map(\.id) == originalWires.map(\.id))
        #expect(bench.junctions[originalJunction.key] == originalJunction.value)
        let offset = Workbench.Movement(parts: [], junctions: [], delta: point(-470, 320))
        for (oldID, newID) in ids {
            let position = try #require(originalPositions[oldID])
            #expect(bench.positions[oldID] == position)
            #expect(bench.positions[newID] == offset.translate(position))
            #expect(bench.rotations[newID] == bench.rotations[oldID])
        }
        func remap(_ endpoint: WorkbenchTerminal) throws -> WorkbenchTerminal {
            if endpoint.isJunction { return .junction(copiedJunction.key) }
            return terminal(try #require(ids[endpoint.partID]), endpoint.pinNumber)
        }
        for (original, copy) in zip(originalWires.dropLast(), copiedWires) {
            #expect(copy.id != original.id)
            #expect(copy.first == (try remap(original.first)))
            #expect(copy.second == (try remap(original.second)))
            #expect(copy.bends == original.bends.map(offset.translate))
            #expect(copy.colour == original.colour)
            let originalNet = try #require(bench.circuitNet(at: original.first))
            let copyNet = try #require(bench.circuitNet(at: copy.first))
            #expect(copyNet === bench.circuitNet(at: copy.second))
            #expect(copyNet !== originalNet)
            for appearance in [ComponentAppearance.schematic, .physicalDIP] {
                let originalRoute = try original.route(from: location(original.first, in: bench, appearance: appearance),
                                                       to: location(original.second, in: bench, appearance: appearance))
                let copiedRoute = try copy.route(from: location(copy.first, in: bench, appearance: appearance),
                                                 to: location(copy.second, in: bench, appearance: appearance))
                #expect(copiedRoute == originalRoute.map(offset.translate))
            }
        }
        let copiedCounter = try #require(ids[1])
        let copiedDisplay = try #require(ids[3])
        #expect(bench.circuitNet(at: terminal(copiedCounter, 15)) == nil)
        #expect(bench.readings[terminal(copiedCounter, 16)] == .high)
        #expect(bench.readings[terminal(copiedDisplay, 4)] == .low)
        let reopened = Workbench()
        let saved = try WorkbenchArchive(bench: bench).encoded()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: saved))
        #expect(try WorkbenchArchive(bench: reopened).encoded() == saved)
    }

    @Test func repeatedlyDuplicatedDisplayChainsAcceptNewWiresAndReopen() throws {
        let bench = Workbench(timeSource: { 0 })
        bench.add("CD4510", component: CD4510())
        bench.add("CD4511", component: SevenSegmentDriver(.cd4511))
        bench.add("MAN74A", component: MAN74A())
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        bench.add("Clock", component: WorkbenchClock())
        bench.setPowerMode(.explicit)
        for id in 1...6 {
            bench.placeNewPart(id, at: point(600, CGFloat(id) * 300))
        }
        bench.rotatePart(2, by: 1)
        for (output, input) in zip([6, 11, 14, 2], [7, 1, 2, 6]) {
            connect(bench, terminal(1, output), terminal(2, input))
        }
        for (output, segment) in zip([13, 12, 11, 10, 9, 15, 14], [14, 13, 8, 7, 6, 1, 2]) {
            connect(bench, terminal(2, output), terminal(3, segment))
        }
        connect(bench, terminal(4), terminal(1, 16))
        let supply = try #require(bench.wires.last)
        bench.select(terminal(2, 16))
        bench.joinWire(supply.id, at: point(840, 640), before: [], after: [])
        for (part, pin) in [(1, 8), (1, 1), (1, 5), (1, 9), (2, 8), (2, 5), (3, 4), (3, 12)] {
            connect(bench, terminal(5), terminal(part, pin))
        }
        for (part, pin) in [(1, 10), (2, 3), (2, 4)] {
            connect(bench, terminal(4), terminal(part, pin))
        }
        connect(bench, terminal(6), terminal(1, 15))

        var groups = [Array(1...6)]
        let wireCount = bench.wires.count
        let move = Workbench.Movement(parts: [], junctions: [], delta: point(-480, -40))
        for _ in 0..<3 {
            let previous = try #require(groups.last)
            let archive = try bench.copyParts(Set(previous))
            let clipboard = try JSONDecoder().decode(WorkbenchArchive.self, from: archive.encoded())
            #expect(clipboard.wires.count == wireCount)
            #expect(clipboard.junctions.count == 1)
            let copies = try bench.pasteParts(clipboard, by: CGSize(width: -483, height: -42)).sorted()
            try #require(copies.count == previous.count)
            for (old, new) in zip(previous, copies) {
                let oldPart = try #require(bench.parts.first { $0.id == old })
                let newPart = try #require(bench.parts.first { $0.id == new })
                #expect(oldPart.component !== newPart.component)
                #expect(Set(oldPart.pins.keys) == Set(newPart.pins.keys))
                for appearance in [ComponentAppearance.schematic, .physicalDIP] {
                    for pin in newPart.pins.keys {
                        let oldAnchor = try location(terminal(old, pin), in: bench, appearance: appearance)
                        let newAnchor = try location(terminal(new, pin), in: bench, appearance: appearance)
                        #expect(newAnchor == move.translate(oldAnchor))
                    }
                }
            }
            groups.append(copies)
        }
        #expect(bench.wires.count == 4 * wireCount)
        #expect(bench.junctions.count == 4)

        for group in groups {
            let dp = terminal(group[2], 9)
            #expect(bench.showsOpenPinMarker(dp))
            let anchor = try location(dp, in: bench, appearance: .physicalDIP)
            let bend = WorkbenchWire.snap(point(anchor.x - 30, anchor.y))
            connect(bench, dp, terminal(group[3]), bend: bend)
            #expect(!bench.showsOpenPinMarker(dp))
            #expect(bench.wires.last?.bends == [bend])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try bench.save(to: url)
        let reopened = Workbench(timeSource: { 0 })
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: Data(contentsOf: url)), at: url)
        #expect(reopened.wires.count == 4 * (wireCount + 1))
        for group in groups {
            let counterOutput = try #require(reopened.circuitNet(at: terminal(group[0], 6)))
            #expect(counterOutput === reopened.circuitNet(at: terminal(group[1], 7)))
            let segment = try #require(reopened.circuitNet(at: terminal(group[1], 13)))
            #expect(segment === reopened.circuitNet(at: terminal(group[2], 14)))
            let clock = try #require(reopened.circuitNet(at: terminal(group[5])))
            #expect(clock === reopened.circuitNet(at: terminal(group[0], 15)))
            #expect(reopened.readings[terminal(group[0], 16)] == .high)
            #expect(reopened.readings[terminal(group[2], 4)] == .low)
            #expect(reopened.readings[terminal(group[2], 9)] == .high)
            for other in groups where other != group {
                #expect(counterOutput !== reopened.circuitNet(at: terminal(other[0], 6)))
            }
        }
    }

    @Test func freshReferencesRespectImportedPartsAndKeepSharedPackages() throws {
        let bench = Workbench()
        let netlist = """
        (export (components
            (comp (ref "R1") (value "4k7") (libsource (lib "Device") (part "R")))
            (comp (ref "r3") (value "10k") (libsource (lib "Device") (part "R")))
            (comp (ref "U1") (value "CD4011") (libsource (lib "4xxx") (part "4011"))))
          (nets))
        """
        let preview = try CircuitImportPreview.read(netlist, filenameExtension: "net")
        #expect(bench.importCircuit(preview, replacing: true) != nil)
        let resistor = try #require(bench.parts.first { $0.reference == "R1" })
        let a = try #require(bench.parts.first { $0.reference == "U1A" })
        let b = try #require(bench.parts.first { $0.reference == "U1B" })
        let initialReferences = bench.parts.map(\.reference)
        let archive = try bench.copyParts([resistor.id, a.id, b.id])
        let firstCopy = try bench.pasteParts(archive, by: CGSize(width: 80, height: 120))
        let copiedParts = bench.parts.filter { firstCopy.contains($0.id) }
        #expect(Set(copiedParts.compactMap(\.reference)) == ["R2", "U2A", "U2B"])
        #expect(Array(bench.parts.prefix(initialReferences.count)).map(\.reference) == initialReferences)
        let newA = try #require(copiedParts.first { $0.reference == "U2A" })
        let newB = try #require(copiedParts.first { $0.reference == "U2B" })
        #expect(newA.component === newB.component)
        #expect(newA.component !== a.component)
        let copiedResistor = try #require(copiedParts.first { $0.reference == "R2" }?.component as? Resistor)
        #expect(copiedResistor.value == (resistor.component as? Resistor)?.value)
        #expect(copiedResistor.unit == (resistor.component as? Resistor)?.unit)
        bench.addUnit(MultiUnitChip.nand.units[2], kind: .nand, to: newA.unitPlacement?.packageID)
        #expect(bench.parts.last?.reference == "U2C")
        let secondCopy = try bench.pasteParts(archive, by: CGSize(width: 80, height: 240))
        #expect(Set(bench.parts.filter { secondCopy.contains($0.id) }.compactMap(\.reference)) == ["R4", "U3A", "U3B"])
    }
}
