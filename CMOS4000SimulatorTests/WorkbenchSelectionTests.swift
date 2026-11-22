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

    private func location(_ endpoint: WorkbenchTerminal, in bench: Workbench) throws -> CGPoint {
        if endpoint.isJunction { return try #require(bench.junctions[endpoint.pinNumber]) }
        let part = try #require(bench.parts.first { $0.id == endpoint.partID })
        let turns = bench.rotations[part.id, default: 0]
        let position = try #require(bench.positions[part.id])
        let geometry = SchematicPartGeometry(part: part, turns: turns)
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
