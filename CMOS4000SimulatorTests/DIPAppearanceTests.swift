import CoreGraphics
import Foundation
import Testing
@testable import CMOS4000Simulator

@MainActor
struct DIPAppearanceTests {
    @Test func dualBCDCounterPackagePreservesBothCountersAndWiring() throws {
        let bench = Workbench()
        let chip = DualCounter(.bcd)
        bench.add("CD4518", component: chip)
        bench.add("LED A", component: WorkbenchLED())
        bench.add("LED B", component: WorkbenchLED())
        let part = bench.parts[0]
        let package = try #require(DIPPackage(part: part))
        #expect(package.pins.map(\.name) == [
            "CLK A", "ENABLE A", "Q1", "Q2", "Q3", "Q4", "RESET A", "VSS",
            "CLK B", "ENABLE B", "Q1", "Q2", "Q3", "Q4", "RESET B", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .input }.map(\.number) == [1, 2, 7, 9, 10, 15])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number) == [3, 4, 5, 6, 11, 12, 13, 14])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [8, 16])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 0..<8 {
            let y = CGFloat(50 + 20 * row)
            #expect(package.endpoints[1 + row] == CGPoint(x: 20, y: y))
            #expect(package.endpoints[16 - row] == CGPoint(x: 160, y: y))
        }

        let position = CGPoint(x: 30, y: 50)
        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let layout = try #require(schematic.packageLayout)
            #expect(layout.units.map { $0.symbol.terminals.map(\.id).sorted() }
                    == [Array(1...7), Array(9...15), [8, 16]])
            #expect(physical.pins == package.endpoints)
            #expect(physical.canvasOrigin(at: position, imported: false)
                    == schematic.canvasOrigin(at: position, imported: false))
            for pin in package.pins {
                let endpoint = try #require(physical.location(of: pin.number, at: position, turns: turns, imported: false))
                #expect(endpoint == WorkbenchWire.snap(endpoint))
            }
        }

        let outputs = [3, 11].map { WorkbenchTerminal(partID: part.id, pinNumber: $0) }
        let leds = bench.parts.dropFirst().map { WorkbenchTerminal(partID: $0.id, pinNumber: 1) }
        bench.componentAppearance = .physicalDIP
        for (output, led) in zip(outputs, leds) {
            bench.select(output)
            bench.select(led)
        }
        bench.rotatePart(part.id, by: 1)
        let archive = try WorkbenchArchive(bench: bench).encoded()
        bench.componentAppearance = .schematic
        #expect(try WorkbenchArchive(bench: bench).encoded() == archive)

        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: archive))
        #expect(reopened.rotations[part.id] == 1)
        #expect(DIPPackage(part: try #require(reopened.parts.first))?.endpoints == package.endpoints)
        for workbench in [bench, reopened] {
            for (output, led) in zip(outputs, leds) {
                let net = try #require(workbench.circuitNet(at: output))
                #expect(workbench.circuitNet(at: led) === net)
            }
            #expect(workbench.circuitNet(at: outputs[0]) !== workbench.circuitNet(at: outputs[1]))
        }
    }

    @Test func binaryCounterDIPPreservesPinIdentityAndWireConnections() throws {
        let bench = Workbench()
        let chip = CD4516()
        bench.add("CD4516", component: chip)
        bench.add("LED", component: WorkbenchLED())
        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        #expect(package.pins.map(\.name) == [
            "PE", "Q3", "P3", "P0", "CARRY IN", "Q0", "CARRY OUT", "VSS",
            "RESET", "UP/DOWN", "Q1", "P1", "P2", "Q2", "CLK", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number) == [2, 6, 7, 11, 14])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [8, 16])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 0..<8 {
            let y = CGFloat(50 + 20 * row)
            #expect(package.endpoints[1 + row] == CGPoint(x: 20, y: y))
            #expect(package.endpoints[16 - row] == CGPoint(x: 160, y: y))
        }

        let position = CGPoint(x: 30, y: 50)
        for turns in 0...3 {
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let schematic = SchematicPartGeometry(part: part, turns: turns, appearance: .schematic)
            #expect(physical.pins == package.endpoints)
            #expect(Set(physical.pins.keys) == Set(schematic.pins.keys))
            #expect(physical.canvasOrigin(at: position, imported: false)
                    == schematic.canvasOrigin(at: position, imported: false))
            for pin in package.pins {
                let endpoint = try #require(physical.location(of: pin.number, at: position, turns: turns, imported: false))
                #expect(endpoint == WorkbenchWire.snap(endpoint))
            }
        }

        let output = WorkbenchTerminal(partID: part.id, pinNumber: 6)
        let led = WorkbenchTerminal(partID: bench.parts[1].id, pinNumber: 1)
        bench.componentAppearance = .physicalDIP
        bench.select(output)
        bench.select(led)
        bench.rotatePart(part.id, by: 1)
        let net = try #require(bench.circuitNet(at: output))
        let archive = try WorkbenchArchive(bench: bench).encoded()
        bench.componentAppearance = .schematic
        #expect(bench.circuitNet(at: led) === net)
        #expect(try WorkbenchArchive(bench: bench).encoded() == archive)

        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: archive))
        #expect(reopened.rotations[part.id] == 1)
        #expect(DIPPackage(part: try #require(reopened.parts.first))?.endpoints == package.endpoints)
        let restoredNet = try #require(reopened.circuitNet(at: output))
        #expect(reopened.circuitNet(at: led) === restoredNet)
    }

    @Test func packageUsesPhysicalPinOrderAndGridAtEveryRotation() throws {
        let bench = Workbench()
        bench.add("CD4070", component: CD4070())
        bench.add("NE555", component: NE555())
        bench.addNextUnit(for: .or)
        bench.add("LED", component: WorkbenchLED())
        let part = bench.parts[0]
        let package = try #require(DIPPackage(part: part))
        #expect(package.pins.map(\.name) == ["A1", "B1", "Q1", "Q2", "A2", "B2", "GND",
                                             "A3", "B3", "Q3", "Q4", "A4", "B4", "VDD"])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [7, 14])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number) == [3, 4, 10, 11])
        let timer = try #require(DIPPackage(part: bench.parts[1]))
        #expect(timer.pins.map(\.name) ==
                ["GND", "TRIG", "OUT", "RESET", "CONT", "THRES", "DISCH", "VCC"])
        #expect(timer.pins.map(\.direction) ==
                [.power, .input, .output, .input, .input, .input, .output, .power])
        #expect(timer.endpoints == [
            1: CGPoint(x: 20, y: 50), 8: CGPoint(x: 160, y: 50),
            2: CGPoint(x: 20, y: 70), 7: CGPoint(x: 160, y: 70),
            3: CGPoint(x: 20, y: 90), 6: CGPoint(x: 160, y: 90),
            4: CGPoint(x: 20, y: 110), 5: CGPoint(x: 160, y: 110),
        ])
        #expect(DIPPackage(part: bench.parts[2]) == nil)
        #expect(DIPPackage(part: bench.parts[3]) == nil)

        for row in 1...7 {
            let left = try #require(package.endpoints[row])
            let right = try #require(package.endpoints[15 - row])
            #expect(left.x < package.body.minX && right.x > package.body.maxX)
            #expect(left.y == right.y && left.y == CGFloat(30 + 20 * row))
        }
        let position = CGPoint(x: 23, y: 48)
        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let center = physical.canvasOrigin(at: position, imported: false)
            #expect(center == schematic.canvasOrigin(at: position, imported: false))
            #expect(Set(physical.pins.keys) == Set(schematic.pins.keys))
            for (number, endpoint) in package.endpoints {
                let location = try #require(physical.location(of: number, at: position, turns: turns, imported: false))
                let offset = CGPoint(x: endpoint.x - physical.size.width / 2,
                                     y: endpoint.y - physical.size.height / 2).schematicRotated(turns)
                #expect(location == CGPoint(x: center.x + offset.x, y: center.y + offset.y))
                #expect(location == WorkbenchWire.snap(location))
            }
        }
    }

    @Test func nandPackageUsesTheExistingGateSymbolsAndPinIdentities() throws {
        let bench = Workbench()
        let chip = CD4011()
        bench.add("CD4011", component: chip)
        for _ in 0..<4 { bench.addNextUnit(for: .nand) }

        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        let gatePins = [[1, 2, 3], [4, 5, 6], [8, 9, 10], [11, 12, 13]]
        #expect(package.usesCD4070Artwork)
        #expect(package.pins.map(\.name) == [
            "A1", "B1", "Q1", "Q2", "A2", "B2", "VSS",
            "A3", "B3", "Q3", "Q4", "A4", "B4", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .input }.map(\.number) == [1, 2, 5, 6, 8, 9, 12, 13])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number) == [3, 4, 10, 11])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [7, 14])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 1...7 {
            let left = try #require(package.endpoints[row])
            let right = try #require(package.endpoints[15 - row])
            #expect(left.x < package.body.minX && right.x > package.body.maxX)
            #expect(left.y == right.y && left.y == CGFloat(30 + 20 * row))
        }

        let gateParts = Array(bench.parts.dropFirst())
        #expect(gateParts.map { $0.pins.keys.sorted() } == gatePins)
        #expect(gateParts.allSatisfy { DIPPackage(part: $0) == nil })
        let position = CGPoint(x: 30, y: 50)
        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let layout = try #require(schematic.packageLayout)
            #expect(layout.units.map { $0.symbol.terminals.map(\.id).sorted() } == gatePins + [[7, 14]])
            #expect(physical.packageLayout == nil)
            #expect(physical.pins == package.endpoints)
            #expect(physical.canvasOrigin(at: position, imported: false)
                    == schematic.canvasOrigin(at: position, imported: false))
        }

        let bytes = try WorkbenchArchive(bench: bench).encoded()
        bench.componentAppearance = .physicalDIP
        #expect(try WorkbenchArchive(bench: bench).encoded() == bytes)
        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: bytes))
        #expect(DIPPackage(part: try #require(reopened.parts.first))?.pins.map(\.name) == package.pins.map(\.name))
        #expect(reopened.parts.dropFirst().map { $0.pins.keys.sorted() } == gatePins)
    }

    @Test func andPackageUsesTheExistingGateSymbolsAndPinIdentities() throws {
        let bench = Workbench()
        let chip = CD4081()
        bench.add("CD4081", component: chip)
        for _ in 0..<4 { bench.addNextUnit(for: .and) }

        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        let gatePins = [[1, 2, 3], [4, 5, 6], [8, 9, 10], [11, 12, 13]]
        #expect(package.usesCD4070Artwork)
        #expect(package.pins.map(\.name) == [
            "A1", "B1", "Q1", "Q2", "A2", "B2", "VSS",
            "A3", "B3", "Q3", "Q4", "A4", "B4", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .input }.map(\.number) == [1, 2, 5, 6, 8, 9, 12, 13])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number) == [3, 4, 10, 11])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [7, 14])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 1...7 {
            let left = try #require(package.endpoints[row])
            let right = try #require(package.endpoints[15 - row])
            #expect(left.x < package.body.minX && right.x > package.body.maxX)
            #expect(left.y == right.y && left.y == CGFloat(30 + 20 * row))
        }

        let gateParts = Array(bench.parts.dropFirst())
        #expect(gateParts.map { $0.pins.keys.sorted() } == gatePins)
        #expect(gateParts.allSatisfy { DIPPackage(part: $0) == nil })
        let position = CGPoint(x: 30, y: 50)
        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let layout = try #require(schematic.packageLayout)
            #expect(layout.units.map { $0.symbol.terminals.map(\.id).sorted() } == gatePins + [[7, 14]])
            #expect(physical.packageLayout == nil)
            #expect(physical.pins == package.endpoints)
            #expect(physical.canvasOrigin(at: position, imported: false)
                    == schematic.canvasOrigin(at: position, imported: false))
        }

        let bytes = try WorkbenchArchive(bench: bench).encoded()
        bench.componentAppearance = .physicalDIP
        #expect(try WorkbenchArchive(bench: bench).encoded() == bytes)
        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: bytes))
        #expect(DIPPackage(part: try #require(reopened.parts.first))?.pins.map(\.name) == package.pins.map(\.name))
        #expect(reopened.parts.dropFirst().map { $0.pins.keys.sorted() } == gatePins)
    }

    @Test func decadeCounterUsesDIP16PinoutAndPreservesWiringAcrossViews() throws {
        let bench = Workbench()
        let chip = CD4017()
        bench.add("CD4017", component: chip)
        bench.add("LED", component: WorkbenchLED())
        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        #expect(package.usesCD4070Artwork)
        #expect(package.pins.map(\.name) == [
            "Q5", "Q1", "Q0", "Q2", "Q6", "Q7", "Q3", "VSS",
            "Q8", "Q4", "Q9", "CARRY OUT", "CLOCK INHIBIT", "CLK", "RESET", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .input }.map(\.number) == [13, 14, 15])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number) == [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [8, 16])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 1...8 {
            let left = try #require(package.endpoints[row])
            let right = try #require(package.endpoints[17 - row])
            #expect(left.x < package.body.minX && right.x > package.body.maxX)
            #expect(left.y == right.y && left.y == CGFloat(30 + 20 * row))
        }

        let output = WorkbenchTerminal(partID: part.id, pinNumber: 3)
        let led = WorkbenchTerminal(partID: bench.parts[1].id, pinNumber: 1)
        bench.select(output)
        bench.select(led)
        bench.rotatePart(part.id, by: 1)
        let net = try #require(bench.circuitNet(at: output))
        let archive = try WorkbenchArchive(bench: bench).encoded()
        let position = CGPoint(x: 30, y: 50)
        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let pivot = physical.canvasOrigin(at: position, imported: false)
            #expect(pivot == schematic.canvasOrigin(at: position, imported: false))
            #expect(Set(schematic.pins.keys) == Set(physical.pins.keys))
            #expect(physical.pins == package.endpoints)
            for (number, endpoint) in package.endpoints {
                let offset = CGPoint(x: endpoint.x - package.size.width / 2,
                                     y: endpoint.y - package.size.height / 2).schematicRotated(turns)
                let location = physical.location(of: number, at: position, turns: turns, imported: false)
                #expect(location == CGPoint(x: pivot.x + offset.x, y: pivot.y + offset.y))
            }
        }
        for appearance in [ComponentAppearance.physicalDIP, .schematic] {
            bench.componentAppearance = appearance
            #expect(bench.circuitNet(at: output) === net)
            #expect(bench.circuitNet(at: led) === net)
            #expect(try WorkbenchArchive(bench: bench).encoded() == archive)
        }

        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: archive))
        #expect(reopened.rotations[part.id] == 1)
        #expect(DIPPackage(part: try #require(reopened.parts.first))?.endpoints == package.endpoints)
        #expect(reopened.circuitNet(at: output) != nil)
        #expect(reopened.circuitNet(at: output) === reopened.circuitNet(at: led))
    }

    @Test func sevenSegmentCounterUsesDIP16PinoutAndPreservesWiringAcrossViews() throws {
        let bench = Workbench()
        let chip = CD4026()
        bench.add("CD4026", component: chip)
        bench.add("LED", component: WorkbenchLED())
        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        #expect(package.usesCD4070Artwork)
        #expect(package.pins.map(\.name) == [
            "CLK", "CLOCK INHIBIT", "DISPLAY ENABLE", "DISPLAY ENABLE OUT", "CARRY OUT", "f", "g", "VSS",
            "d", "a", "e", "b", "c", "UNGATED c", "RESET", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .input }.map(\.number) == [1, 2, 3, 15])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number) == [4, 5, 6, 7, 9, 10, 11, 12, 13, 14])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [8, 16])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 1...8 {
            let left = try #require(package.endpoints[row])
            let right = try #require(package.endpoints[17 - row])
            #expect(left.x < package.body.minX && right.x > package.body.maxX)
            #expect(left.y == right.y && left.y == CGFloat(30 + 20 * row))
        }

        let output = WorkbenchTerminal(partID: part.id, pinNumber: 10)
        let led = WorkbenchTerminal(partID: bench.parts[1].id, pinNumber: 1)
        bench.select(output)
        bench.select(led)
        bench.rotatePart(part.id, by: 1)
        let net = try #require(bench.circuitNet(at: output))
        let archive = try WorkbenchArchive(bench: bench).encoded()
        let position = CGPoint(x: 30, y: 50)
        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let pivot = physical.canvasOrigin(at: position, imported: false)
            #expect(pivot == schematic.canvasOrigin(at: position, imported: false))
            #expect(Set(schematic.pins.keys) == Set(physical.pins.keys))
            #expect(physical.pins == package.endpoints)
            for (number, endpoint) in package.endpoints {
                let offset = CGPoint(x: endpoint.x - package.size.width / 2,
                                     y: endpoint.y - package.size.height / 2).schematicRotated(turns)
                let location = physical.location(of: number, at: position, turns: turns, imported: false)
                #expect(location == CGPoint(x: pivot.x + offset.x, y: pivot.y + offset.y))
            }
        }
        for appearance in [ComponentAppearance.physicalDIP, .schematic] {
            bench.componentAppearance = appearance
            #expect(bench.circuitNet(at: output) === net)
            #expect(bench.circuitNet(at: led) === net)
            #expect(try WorkbenchArchive(bench: bench).encoded() == archive)
        }

        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: archive))
        #expect(reopened.rotations[part.id] == 1)
        #expect(DIPPackage(part: try #require(reopened.parts.first))?.endpoints == package.endpoints)
        #expect(reopened.circuitNet(at: output) != nil)
        #expect(reopened.circuitNet(at: output) === reopened.circuitNet(at: led))
    }

    @Test func presettableCounterUsesDIP16PinoutAndPreservesWiringAcrossViews() throws {
        let bench = Workbench()
        let chip = CD4029()
        bench.add("CD4029", component: chip)
        bench.add("LED", component: WorkbenchLED())
        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        #expect(package.pins.map(\.name) == [
            "PE", "Q4", "JAM 4", "JAM 1", "CARRY IN", "Q1", "CARRY OUT", "VSS",
            "BINARY/DECADE", "UP/DOWN", "Q2", "JAM 2", "JAM 3", "Q3", "CLK", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .input }.map(\.number) == [1, 3, 4, 5, 9, 10, 12, 13, 15])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number) == [2, 6, 7, 11, 14])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [8, 16])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 1...8 {
            #expect(package.endpoints[row] == CGPoint(x: 20, y: 30 + 20 * row))
            #expect(package.endpoints[17 - row] == CGPoint(x: 160, y: 30 + 20 * row))
        }

        let carry = WorkbenchTerminal(partID: part.id, pinNumber: 7)
        let led = WorkbenchTerminal(partID: bench.parts[1].id, pinNumber: 1)
        bench.select(carry)
        bench.select(led)
        bench.rotatePart(part.id, by: 1)
        let net = try #require(bench.circuitNet(at: carry))
        let bytes = try WorkbenchArchive(bench: bench).encoded()
        let position = CGPoint(x: 30, y: 50)
        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let pivot = physical.canvasOrigin(at: position, imported: false)
            #expect(pivot == schematic.canvasOrigin(at: position, imported: false))
            #expect(Set(physical.pins.keys) == Set(schematic.pins.keys))
            #expect(physical.pins == package.endpoints)
            for (number, endpoint) in package.endpoints {
                let offset = CGPoint(x: endpoint.x - package.size.width / 2,
                                     y: endpoint.y - package.size.height / 2).schematicRotated(turns)
                #expect(physical.location(of: number, at: position, turns: turns, imported: false)
                        == CGPoint(x: pivot.x + offset.x, y: pivot.y + offset.y))
            }
        }
        for appearance in [ComponentAppearance.physicalDIP, .schematic] {
            bench.componentAppearance = appearance
            #expect(bench.circuitNet(at: carry) === net)
            #expect(bench.circuitNet(at: led) === net)
            #expect(try WorkbenchArchive(bench: bench).encoded() == bytes)
        }

        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: bytes))
        #expect(reopened.rotations[part.id] == 1)
        #expect(DIPPackage(part: try #require(reopened.parts.first))?.endpoints == package.endpoints)
        let reopenedNet = try #require(reopened.circuitNet(at: carry))
        #expect(reopened.circuitNet(at: led) === reopenedNet)
    }

    @Test func cd4051UsesDIP16PinoutAndPreservesWiringAcrossViews() throws {
        let bench = Workbench()
        let chip = AnalogSwitch(.cd4051)
        bench.add("CD4051", component: chip)
        bench.add("CD4052", component: AnalogSwitch(.cd4052))
        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        #expect(package.pins.map(\.name) == [
            "4", "6", "COM", "7", "5", "INH", "VEE", "VSS",
            "C", "B", "A", "3", "0", "1", "2", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .input }.map(\.number) == [6, 9, 10, 11])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [7, 8, 16])
        #expect(package.pins.filter { $0.direction == .bidirectional }.map(\.number)
                == [1, 2, 3, 4, 5, 12, 13, 14, 15])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 1...8 {
            #expect(package.endpoints[row] == CGPoint(x: 20, y: 30 + 20 * row))
            #expect(package.endpoints[17 - row] == CGPoint(x: 160, y: 30 + 20 * row))
        }

        let common = WorkbenchTerminal(partID: part.id, pinNumber: 3)
        let otherCommon = WorkbenchTerminal(partID: bench.parts[1].id, pinNumber: 3)
        bench.select(common)
        bench.select(otherCommon)
        bench.rotatePart(part.id, by: 1)
        let net = try #require(bench.circuitNet(at: common))
        let bytes = try WorkbenchArchive(bench: bench).encoded()
        let schematic = SchematicPartGeometry(part: part, turns: 1)
        let physical = SchematicPartGeometry(part: part, turns: 1, appearance: .physicalDIP)
        #expect(Set(schematic.pins.keys) == Set(physical.pins.keys))
        #expect(physical.pins == package.endpoints)
        let position = CGPoint(x: 30, y: 50)
        let pivot = schematic.canvasOrigin(at: position, imported: false)
        for (number, endpoint) in package.endpoints {
            let offset = CGPoint(x: endpoint.x - package.size.width / 2,
                                 y: endpoint.y - package.size.height / 2).schematicRotated(1)
            #expect(physical.location(of: number, at: position, turns: 1, imported: false)
                    == CGPoint(x: pivot.x + offset.x, y: pivot.y + offset.y))
        }
        for appearance in [ComponentAppearance.physicalDIP, .schematic] {
            bench.componentAppearance = appearance
            #expect(bench.circuitNet(at: common) === net)
            #expect(bench.circuitNet(at: otherCommon) === net)
            #expect(try WorkbenchArchive(bench: bench).encoded() == bytes)
        }

        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: bytes))
        #expect(reopened.rotations[part.id] == 1)
        #expect(DIPPackage(part: try #require(reopened.parts.first))?.endpoints == package.endpoints)
        let reopenedNet = try #require(reopened.circuitNet(at: common))
        #expect(reopened.circuitNet(at: otherCommon) === reopenedNet)
    }

    @Test func cd4052UsesDIP16PinoutAndPreservesWiringAcrossViews() throws {
        let bench = Workbench()
        let chip = AnalogSwitch(.cd4052)
        bench.add("CD4052", component: chip)
        bench.add("CD4052", component: AnalogSwitch(.cd4052))
        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        #expect(package.pins.map(\.name) == [
            "Y0", "Y2", "Y COM", "Y3", "Y1", "INH", "VEE", "VSS",
            "B", "A", "X3", "X0", "X COM", "X1", "X2", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .bidirectional }.map(\.number)
                == [1, 2, 3, 4, 5, 11, 12, 13, 14, 15])
        #expect(package.pins.filter { $0.direction == .input }.map(\.number) == [6, 9, 10])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [7, 8, 16])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 1...8 {
            #expect(package.endpoints[row] == CGPoint(x: 20, y: 30 + 20 * row))
            #expect(package.endpoints[17 - row] == CGPoint(x: 160, y: 30 + 20 * row))
        }

        let xCommon = WorkbenchTerminal(partID: part.id, pinNumber: 13)
        let yCommon = WorkbenchTerminal(partID: bench.parts[1].id, pinNumber: 3)
        bench.select(xCommon)
        bench.select(yCommon)
        bench.rotatePart(part.id, by: 1)
        let net = try #require(bench.circuitNet(at: xCommon))
        let bytes = try WorkbenchArchive(bench: bench).encoded()
        let schematic = SchematicPartGeometry(part: part, turns: 1)
        let physical = SchematicPartGeometry(part: part, turns: 1, appearance: .physicalDIP)
        #expect(Set(schematic.pins.keys) == Set(physical.pins.keys))
        #expect(physical.pins == package.endpoints)
        for appearance in [ComponentAppearance.physicalDIP, .schematic] {
            bench.componentAppearance = appearance
            #expect(bench.circuitNet(at: xCommon) === net)
            #expect(bench.circuitNet(at: yCommon) === net)
            #expect(try WorkbenchArchive(bench: bench).encoded() == bytes)
        }

        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: bytes))
        #expect(reopened.rotations[part.id] == 1)
        #expect(DIPPackage(part: try #require(reopened.parts.first))?.endpoints == package.endpoints)
        let reopenedNet = try #require(reopened.circuitNet(at: xCommon))
        #expect(reopened.circuitNet(at: yCommon) === reopenedNet)
    }

    @Test func cd4060UsesDIP16PinoutAndPreservesWiringAcrossViews() throws {
        let bench = Workbench()
        let chip = CD4060()
        bench.add("CD4060", component: chip)
        bench.add("LED", component: WorkbenchLED())
        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        #expect(package.pins.map(\.name) == [
            "Q12", "Q13", "Q14", "Q6", "Q5", "Q7", "Q4", "VSS",
            "OSC 9", "OSC 10", "CLK", "RESET", "Q9", "Q8", "Q10", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .input }.map(\.number) == [11, 12])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [8, 16])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number)
                == [1, 2, 3, 4, 5, 6, 7, 9, 10, 13, 14, 15])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 1...8 {
            #expect(package.endpoints[row] == CGPoint(x: 20, y: 30 + 20 * row))
            #expect(package.endpoints[17 - row] == CGPoint(x: 160, y: 30 + 20 * row))
        }

        let output = WorkbenchTerminal(partID: part.id, pinNumber: 7)
        let led = WorkbenchTerminal(partID: bench.parts[1].id, pinNumber: 1)
        bench.select(output)
        bench.select(led)
        bench.rotatePart(part.id, by: 1)
        let net = try #require(bench.circuitNet(at: output))
        let bytes = try WorkbenchArchive(bench: bench).encoded()
        let schematic = SchematicPartGeometry(part: part, turns: 1)
        let physical = SchematicPartGeometry(part: part, turns: 1, appearance: .physicalDIP)
        #expect(Set(schematic.pins.keys) == Set(physical.pins.keys))
        #expect(physical.pins == package.endpoints)
        for appearance in [ComponentAppearance.physicalDIP, .schematic] {
            bench.componentAppearance = appearance
            #expect(bench.circuitNet(at: output) === net)
            #expect(bench.circuitNet(at: led) === net)
            #expect(try WorkbenchArchive(bench: bench).encoded() == bytes)
        }

        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: bytes))
        #expect(reopened.rotations[part.id] == 1)
        #expect(DIPPackage(part: try #require(reopened.parts.first))?.endpoints == package.endpoints)
        let reopenedNet = try #require(reopened.circuitNet(at: output))
        #expect(reopened.circuitNet(at: led) === reopenedNet)
    }

    @Test func cd4053UsesDIP16PinoutAndPreservesWiringAcrossViews() throws {
        let bench = Workbench()
        let chip = AnalogSwitch(.cd4053)
        bench.add("CD4053", component: chip)
        bench.add("CD4053", component: AnalogSwitch(.cd4053))
        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        #expect(package.pins.map(\.name) == [
            "BY", "BX", "CY", "C COM", "CX", "INH", "VEE", "VSS",
            "C", "B", "A", "AX", "AY", "A COM", "B COM", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .bidirectional }.map(\.number)
                == [1, 2, 3, 4, 5, 12, 13, 14, 15])
        #expect(package.pins.filter { $0.direction == .input }.map(\.number) == [6, 9, 10, 11])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [7, 8, 16])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 1...8 {
            #expect(package.endpoints[row] == CGPoint(x: 20, y: 30 + 20 * row))
            #expect(package.endpoints[17 - row] == CGPoint(x: 160, y: 30 + 20 * row))
        }

        let aCommon = WorkbenchTerminal(partID: part.id, pinNumber: 14)
        let cCommon = WorkbenchTerminal(partID: bench.parts[1].id, pinNumber: 4)
        bench.select(aCommon)
        bench.select(cCommon)
        bench.rotatePart(part.id, by: 1)
        let net = try #require(bench.circuitNet(at: aCommon))
        let bytes = try WorkbenchArchive(bench: bench).encoded()
        let schematic = SchematicPartGeometry(part: part, turns: 1)
        let physical = SchematicPartGeometry(part: part, turns: 1, appearance: .physicalDIP)
        #expect(Set(schematic.pins.keys) == Set(physical.pins.keys))
        #expect(physical.pins == package.endpoints)
        for appearance in [ComponentAppearance.physicalDIP, .schematic] {
            bench.componentAppearance = appearance
            #expect(bench.circuitNet(at: aCommon) === net)
            #expect(bench.circuitNet(at: cCommon) === net)
            #expect(try WorkbenchArchive(bench: bench).encoded() == bytes)
        }

        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: bytes))
        #expect(reopened.rotations[part.id] == 1)
        #expect(DIPPackage(part: try #require(reopened.parts.first))?.endpoints == package.endpoints)
        let reopenedNet = try #require(reopened.circuitNet(at: aCommon))
        #expect(reopened.circuitNet(at: cCommon) === reopenedNet)
    }

    @Test func jkPackageSwitchesBetweenDIP16AndExistingSchematicUnits() throws {
        let bench = Workbench()
        let chip = CD4027()
        bench.add("CD4027", component: chip)
        bench.add("LED", component: WorkbenchLED())
        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        #expect(package.pins.map(\.name) == [
            "Q", "Q̅", "CLK", "RESET", "K", "J", "SET", "VSS",
            "SET", "J", "K", "RESET", "CLK", "Q̅", "Q", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number) == [1, 2, 14, 15])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [8, 16])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 1...8 {
            let left = try #require(package.endpoints[row])
            let right = try #require(package.endpoints[17 - row])
            #expect(left.x < package.body.minX && right.x > package.body.maxX)
            #expect(left.y == right.y && left.y == CGFloat(30 + 20 * row))
        }

        let position = CGPoint(x: 30, y: 50)
        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let layout = try #require(schematic.packageLayout)
            #expect(layout.units.map { $0.symbol.terminals.map(\.id).sorted() }
                    == [Array(1...7), Array(9...15), [8, 16]])
            #expect(layout.units.allSatisfy { $0.part.id == part.id && $0.part.component === chip })
            #expect(physical.packageLayout == nil)
            #expect(physical.pins == package.endpoints)
            #expect(physical.canvasOrigin(at: position, imported: false)
                    == schematic.canvasOrigin(at: position, imported: false))
            for number in physical.pins.keys {
                let point = try #require(physical.location(of: number, at: position, turns: turns, imported: false))
                #expect(point == WorkbenchWire.snap(point))
            }
        }

        let output = WorkbenchTerminal(partID: part.id, pinNumber: 15)
        let led = WorkbenchTerminal(partID: bench.parts[1].id, pinNumber: 1)
        bench.componentAppearance = .physicalDIP
        bench.select(output)
        bench.select(led)
        bench.rotatePart(part.id, by: 1)
        let net = try #require(bench.circuitNet(at: output))
        let bytes = try WorkbenchArchive(bench: bench).encoded()
        bench.componentAppearance = .schematic
        #expect(bench.circuitNet(at: output) === net)
        #expect(bench.circuitNet(at: led) === net)
        #expect(try WorkbenchArchive(bench: bench).encoded() == bytes)

        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: bytes))
        #expect(reopened.rotations[part.id] == 1)
        #expect(DIPPackage(part: try #require(reopened.parts.first))?.endpoints == package.endpoints)
        #expect(reopened.circuitNet(at: output) != nil)
        #expect(reopened.circuitNet(at: output) === reopened.circuitNet(at: led))
    }

    @Test func schmittPackageSwitchesAppearanceWithTheSameTerminals() throws {
        let bench = Workbench()
        let chip = CD40106()
        bench.add("CD40106", component: chip)
        bench.add("Input", component: WorkbenchSwitch())
        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        #expect(package.usesCD4070Artwork)
        #expect(package.pins.map(\.name) == [
            "A1", "Q1", "A2", "Q2", "A3", "Q3", "VSS",
            "Q4", "A4", "Q5", "A5", "Q6", "A6", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .input }.map(\.number) == [1, 3, 5, 9, 11, 13])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number) == [2, 4, 6, 8, 10, 12])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [7, 14])
        #expect(package.pins.allSatisfy { $0 === chip.pins[$0.number] })
        for row in 1...7 {
            let left = try #require(package.endpoints[row])
            let right = try #require(package.endpoints[15 - row])
            #expect(left.x < package.body.minX && right.x > package.body.maxX)
            #expect(left.y == right.y && left.y == CGFloat(30 + 20 * row))
        }

        let position = CGPoint(x: 30, y: 50)
        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let layout = try #require(schematic.packageLayout)
            #expect(layout.units.map(\.part.reference) == ["U1A", "U1B", "U1C", "U1D", "U1E", "U1F", "U1G"])
            #expect(layout.units.map { $0.symbol.terminals.map(\.id).sorted() }
                    == [[1, 2], [3, 4], [5, 6], [8, 9], [10, 11], [12, 13], [7, 14]])
            #expect(physical.packageLayout == nil)
            #expect(physical.canvasOrigin(at: position, imported: false)
                    == schematic.canvasOrigin(at: position, imported: false))
            #expect(physical.pins == package.endpoints)
            #expect(Set(physical.pins.keys) == Set(schematic.pins.keys))
            for pin in package.pins {
                let point = try #require(physical.location(of: pin.number, at: position, turns: turns, imported: false))
                #expect(point == WorkbenchWire.snap(point))
            }
        }

        let source = WorkbenchTerminal(partID: 2, pinNumber: 1)
        let input = WorkbenchTerminal(partID: part.id, pinNumber: 1)
        let output = WorkbenchTerminal(partID: part.id, pinNumber: 2)
        bench.select(source)
        bench.select(input)
        bench.rotatePart(part.id, by: 1)
        let net = try #require(bench.circuitNet(at: input))
        let bytes = try WorkbenchArchive(bench: bench).encoded()
        for appearance in [ComponentAppearance.physicalDIP, .schematic] {
            bench.componentAppearance = appearance
            #expect(bench.circuitNet(at: input) === net)
            #expect(bench.readings[output] == .high)
            #expect(try WorkbenchArchive(bench: bench).encoded() == bytes)
        }

        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: bytes))
        #expect(DIPPackage(part: try #require(reopened.parts.first)) != nil)
        #expect(reopened.rotations[part.id] == 1)
        #expect(reopened.circuitNet(at: source) === reopened.circuitNet(at: input))
        #expect(reopened.readings[output] == .high)
    }

    @Test func appearancePreservesCircuitScopeAndExplicitColoursThroughReopen() throws {
        let bench = Workbench(timeSource: { 0 })
        bench.add("CD4070", component: CD4070())
        bench.add("Clock", component: WorkbenchClock())
        bench.add("LED", component: WorkbenchLED())
        let input = WorkbenchTerminal(partID: 1, pinNumber: 1)
        let output = WorkbenchTerminal(partID: 1, pinNumber: 3)
        let clock = WorkbenchTerminal(partID: 2, pinNumber: 1)
        let led = WorkbenchTerminal(partID: 3, pinNumber: 1)
        let start = CGPoint(x: 180, y: 100)
        let end = CGPoint(x: 320, y: 200)
        bench.movePart(1, from: .zero, to: start)
        bench.select(clock)
        bench.select(input)
        #expect(bench.wires.map(\.colour) == [.green])
        bench.setWireColour(.violet, for: try #require(bench.wires.first?.id))
        let probe = ScopeProbe.pin(input)
        #expect(bench.placeScopeProbe(probe))
        let net = try #require(bench.circuitNet(at: input))
        let bytes = try WorkbenchArchive(bench: bench).encoded()
        let revision = bench.circuitRevision

        bench.newWireColour = .yellow
        bench.componentAppearance = .physicalDIP
        #expect(bench.newWireColour == .black)
        #expect(try WorkbenchArchive(bench: bench).encoded() == bytes)
        #expect(bench.circuitRevision == revision)
        #expect(bench.circuitNet(at: clock) === net)
        #expect(bench.scopeNet(for: probe) === net)
        bench.select(output)
        bench.select(led)
        #expect(bench.wires.map(\.colour) == [.violet, .black])
        let wiredNet = try #require(bench.circuitNet(at: input))

        bench.rotatePart(1, by: 1)
        bench.movePart(1, from: start, to: end)
        let part = bench.parts[0]
        let geometry = SchematicPartGeometry(part: part, turns: 1, appearance: bench.componentAppearance)
        let pin = try #require(geometry.location(of: 1, at: end, turns: 1, imported: false))
        let firstWire = try #require(bench.wires.first)
        let route = firstWire.route(from: .zero, to: pin)
        #expect(route.last == pin)
        #expect(zip(route, route.dropFirst()).allSatisfy { $0.x == $1.x || $0.y == $1.y })
        #expect(bench.circuitNet(at: input) === wiredNet)
        #expect(bench.scopeNet(for: probe) === wiredNet)
        bench.componentAppearance = .schematic
        #expect(bench.newWireColour == .yellow)

        let reopened = Workbench()
        let archive = try WorkbenchArchive(bench: bench).encoded()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: archive))
        #expect(reopened.parts[0].component is CD4070)
        #expect(reopened.rotations[1] == 1)
        #expect(reopened.positions[1] == end)
        #expect(reopened.wires.map(\.colour) == [.violet, .black])
        #expect(reopened.circuitNet(at: clock) === reopened.circuitNet(at: input))
        #expect(reopened.scopeProbes[0] == probe)
        #expect(reopened.scopeNet(for: probe) != nil)
    }


    @Test func schematicPackageShowsFourXORGatesAndSharedPower() throws {
        let bench = Workbench()
        let chip = CD4070()
        bench.add("CD4070", component: chip)
        let part = try #require(bench.parts.first)
        let pinGroups = [[1, 2, 3], [4, 5, 6], [8, 9, 10], [11, 12, 13], [7, 14]]
        let position = CGPoint(x: 23, y: 48)

        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let layout = try #require(schematic.packageLayout)
            #expect(layout.units.map(\.part.reference) == ["U1A", "U1B", "U1C", "U1D", "U1E"])
            #expect(layout.units.map { $0.symbol.terminals.map(\.id).sorted() } == pinGroups)
            #expect(layout.units.prefix(4).allSatisfy { !$0.symbol.polygon.isEmpty && $0.symbol.markings.count == 1 })
            let gate = layout.units[0].symbol
            #expect(gate.terminals.map(\.position.y) == [-2.54, 2.54, 0])
            #expect(gate.polygon.contains(gate.terminals[2].bodyEnd))
            #expect(gate.polygon[24].y == gate.polygon[25].y)
            #expect(gate.polygon[24].x < gate.polygon[25].x)
            #expect(layout.units.last?.symbol.polygon.isEmpty == true)
            #expect(Set(schematic.pins.values.map { [$0.x, $0.y] }).count == 14)

            let center = schematic.canvasOrigin(at: position, imported: false)
            #expect(center == CGPoint(x: 160, y: 200))
            for unit in layout.units {
                #expect(unit.part.id == part.id && unit.part.component === chip)
                let geometry = SchematicSymbolGeometry(symbol: unit.symbol, part: unit.part)
                for pin in unit.symbol.terminals {
                    let local = geometry.endpoint(pin)
                    let offset = CGPoint(x: local.x + unit.origin.x - layout.size.width / 2,
                                         y: local.y + unit.origin.y - layout.size.height / 2).schematicRotated(turns)
                    let endpoint = try #require(schematic.location(of: pin.id, at: position, turns: turns, imported: false))
                    #expect(endpoint == CGPoint(x: center.x + offset.x, y: center.y + offset.y))
                    #expect(endpoint == WorkbenchWire.snap(endpoint))
                }
            }
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            #expect(physical.packageLayout == nil)
            #expect(physical.canvasOrigin(at: position, imported: false) == center)
        }
    }

    @Test func individuallyPlacedGatesSharePinsAndSimulateThroughPowerUnit() throws {
        let bench = Workbench()
        for _ in 0..<4 { bench.addNextUnit(for: .xor) }
        let first = try #require(bench.parts.first)
        bench.addUnit(MultiUnitChip.xor.powerUnit, kind: .xor, to: 1)
        #expect(bench.parts.map(\.reference) == ["U1A", "U1B", "U1C", "U1D", "U1E"])
        #expect(bench.parts.allSatisfy { $0.component === first.component && DIPPackage(part: $0) == nil })
        bench.setPowerMode(.explicit)
        bench.add("VDD", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))

        func wire(_ source: Int, _ unit: Int, _ pin: Int) {
            bench.select(WorkbenchTerminal(partID: source, pinNumber: 1))
            bench.select(WorkbenchTerminal(partID: unit, pinNumber: pin))
        }
        for gate in QuadGate.allCases {
            wire(6, gate.rawValue, gate.terminals.inputA)
            wire(7, gate.rawValue, gate.terminals.inputB)
            #expect(bench.readings[WorkbenchTerminal(partID: gate.rawValue, pinNumber: gate.terminals.output)] == .undefined)
        }
        wire(6, 5, 14)
        wire(7, 5, 7)

        let reopened = Workbench()
        try reopened.open(WorkbenchArchive(bench: bench))
        for gate in QuadGate.allCases {
            let output = WorkbenchTerminal(partID: gate.rawValue, pinNumber: gate.terminals.output)
            #expect(bench.readings[output] == .high)
            #expect(reopened.readings[output] == .high)
        }
    }

    @Test func existingMultiUnitChipsRetainSchematicGeometryInPhysicalMode() throws {
        let bench = Workbench()
        for kind in MultiUnitChip.allCases where kind != .xor {
            bench.addNextUnit(for: kind)
            let part = try #require(bench.parts.last)
            let schematic = SchematicPartGeometry(part: part, turns: 0)
            let physical = SchematicPartGeometry(part: part, turns: 0, appearance: .physicalDIP)
            #expect(part.reference?.hasSuffix("A") == true)
            #expect(schematic.packageLayout == nil && physical.packageLayout == nil)
            #expect(DIPPackage(part: part) == nil)
            #expect(schematic.pins == physical.pins)
        }
    }

    @Test func xorUsesEachPhysicalGatePair() {
        let chip = CD4070()
        let cases: [(LogicState, LogicState, LogicState)] = [
            (.low, .low, .low), (.low, .high, .high), (.high, .low, .high),
            (.high, .high, .low), (.high, .highImpedance, .undefined),
            (.low, .undefined, .undefined)
        ]
        for gate in QuadGate.allCases {
            let (a, b, q) = gate.terminals
            for (first, second, expected) in cases {
                chip.pins[a]?.receive(first)
                chip.pins[b]?.receive(second)
                chip.evaluate()
                #expect(chip.pins[q]?.driveState == expected)
            }
        }
    }
}
