import Foundation
import Testing
@testable import CMOS4000Simulator

@MainActor
struct WorkbenchDocumentTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
    }

    @Test func editsAndUndoTrackTheSavedRevision() throws {
        let bench = Workbench()
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(!bench.isDirty)

        let clock = WorkbenchClock()
        bench.add("Clock", component: clock)
        bench.placeNewPart(1, at: CGPoint(x: 20, y: 20))
        let resistor = Resistor()
        bench.add("Resistor", component: resistor)
        #expect(bench.isDirty)
        try bench.save(to: file)
        #expect(!bench.isDirty)
        #expect(bench.documentURL == file)

        let output = WorkbenchTerminal(partID: 1, pinNumber: 1)
        bench.select(output)
        bench.addBend(at: CGPoint(x: 50, y: 50))
        bench.cancelWire()
        bench.advanceClock(clock)
        bench.refreshScope()
        bench.rotatePart(1, by: 4)
        bench.movePart(1, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 20, y: 20))
        #expect(!bench.isDirty)

        bench.select(output)
        bench.select(WorkbenchTerminal(partID: 2, pinNumber: 1))
        #expect(bench.isDirty)
        bench.undo()
        #expect(!bench.isDirty)
        bench.redo()
        #expect(bench.isDirty)
        bench.undo()

        bench.movePart(1, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 40, y: 40))
        #expect(bench.isDirty)
        bench.undo()
        #expect(!bench.isDirty)
        bench.setResistance(resistor.value + 1, unit: resistor.unit, for: resistor)
        #expect(bench.isDirty)
        bench.undo()
        #expect(!bench.isDirty)
        bench.removePart(2)
        #expect(bench.isDirty)
    }

    @Test func wirePaletteAndLegacyArchivesPreserveAppearance() throws {
        #expect(WireColour.allCases.map(\.title) == [
            "Black", "Grey", "Brown", "Red", "Orange", "Yellow", "Green", "Blue", "Violet"
        ])

        let bench = Workbench()
        bench.add("Clock", component: WorkbenchClock())
        bench.add("LED", component: WorkbenchLED())
        bench.select(WorkbenchTerminal(partID: 1, pinNumber: 1))
        bench.select(WorkbenchTerminal(partID: 2, pinNumber: 1))
        let wire = try #require(bench.wires.first)
        #expect(wire.colour == .green)

        let encoded = try WorkbenchArchive(bench: bench).encoded()
        var archive = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var wires = try #require(archive["wires"] as? [[String: Any]])
        wires[0].removeValue(forKey: "colour")
        archive["wires"] = wires

        for version in [1, 2] {
            archive["version"] = version
            let legacy = try JSONSerialization.data(withJSONObject: archive)
            let reopened = Workbench()
            try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: legacy))
            #expect(reopened.wires.map(\.colour) == [.green])
            #expect(reopened.newWireColour == .green)
        }
    }

    @Test func wireRecolourAndItsHistoryPreserveLiveNetsAndScope() throws {
        let bench = Workbench(timeSource: { 0 })
        let clock = WorkbenchClock()
        bench.add("Clock", component: clock)
        bench.add("LED", component: WorkbenchLED())
        let output = WorkbenchTerminal(partID: 1, pinNumber: 1)
        let input = WorkbenchTerminal(partID: 2, pinNumber: 1)
        bench.select(output)
        bench.select(input)
        let wire = try #require(bench.wires.first)
        let net = try #require(bench.circuitNet(at: input))
        let probe = ScopeProbe.wirePoint(id: wire.id, fraction: 0.5)
        #expect(bench.placeScopeProbe(probe))
        bench.runClock(clock, hertz: 1000)
        bench.serviceSimulation(until: 0.003)
        let trace = bench.scope.samples(channel: 0, in: 0...1)
        let reading = bench.readings[input]
        #expect(!trace.isEmpty)
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try bench.save(to: file)
        bench.selectWire(wire.id)

        func checkLiveState() {
            #expect(bench.circuitNet(at: output) === net)
            #expect(bench.circuitNet(at: input) === net)
            #expect(bench.scopeNet(for: probe) === net)
            #expect(bench.scopeProbes[0] == probe)
            #expect(bench.scope.samples(channel: 0, in: 0...1) == trace)
            #expect(bench.readings[input] == reading)
            #expect(bench.hasRunningClocks)
        }

        bench.setWireColour(.violet, for: wire.id)
        #expect(bench.isDirty)
        #expect(bench.selectedWireID == wire.id)
        #expect(bench.newWireColour == .green)
        checkLiveState()
        let recolouredRevision = bench.circuitRevision
        bench.setWireColour(.violet, for: wire.id)
        #expect(bench.circuitRevision == recolouredRevision)

        bench.undo()
        #expect(bench.wires.map(\.colour) == [.green])
        #expect(!bench.isDirty)
        checkLiveState()
        bench.redo()
        #expect(bench.wires.map(\.colour) == [.violet])
        checkLiveState()
        bench.serviceSimulation(until: 0.004)
        #expect(bench.scope.samples(channel: 0, in: 0...1).count > trace.count)
    }

    @Test func colouredWiresSurviveSplitMoveAndReopen() throws {
        let bench = Workbench()
        bench.add("Clock", component: WorkbenchClock())
        bench.add("LED", component: WorkbenchLED())
        bench.add("LED", component: WorkbenchLED())
        let output = WorkbenchTerminal(partID: 1, pinNumber: 1)
        let input = WorkbenchTerminal(partID: 2, pinNumber: 1)
        let branch = WorkbenchTerminal(partID: 3, pinNumber: 1)
        bench.newWireColour = .yellow
        bench.select(output)
        bench.select(input)
        let wire = try #require(bench.wires.first)
        bench.newWireColour = .blue
        bench.select(branch)
        bench.joinWire(wire.id, at: CGPoint(x: 50, y: 50), before: [CGPoint(x: 40, y: 50)], after: [])
        #expect(bench.wires.map(\.colour) == [.yellow, .yellow, .blue])
        bench.undo()
        #expect(bench.wires.map(\.colour) == [.yellow])
        bench.redo()
        #expect(bench.wires.map(\.colour) == [.yellow, .yellow, .blue])

        bench.moveParts(bench.movement(of: [1, 2, 3], by: CGSize(width: 20, height: 30)))
        #expect(bench.wires.first?.bends == [CGPoint(x: 60, y: 80)])
        #expect(bench.wires.map(\.colour) == [.yellow, .yellow, .blue])

        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try bench.save(to: file)
        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: Data(contentsOf: file)))
        #expect(reopened.wires.map(\.colour) == [.yellow, .yellow, .blue])
        let net = try #require(reopened.circuitNet(at: output))
        #expect(reopened.circuitNet(at: input) === net)
        #expect(reopened.circuitNet(at: branch) === net)
    }

    @Test func saveCancellationAndFailureBlockClear() throws {
        let workflow = WorkbenchFileWorkflow()
        let bench = Workbench()
        bench.add("LED", component: WorkbenchLED())
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }

        func clear(decision: WorkbenchFileWorkflow.Decision, save: () -> Bool) -> Bool {
            workflow.perform {
                guard workflow.permitsLeaving(bench, decide: { decision }, save: save) else { return false }
                bench.clear()
                return true
            }
        }

        #expect(!clear(decision: .cancel, save: { Issue.record("Cancel must not save"); return false }))
        #expect(!clear(decision: .save, save: { false }))
        #expect(!clear(decision: .save, save: {
            do {
                try bench.save(to: file.appendingPathComponent("missing.json"))
                Issue.record("Saving through a missing directory succeeded")
                return true
            } catch {
                return false
            }
        }))
        #expect(bench.parts.count == 1)
        #expect(bench.isDirty)
        #expect(bench.documentURL == nil)

        #expect(clear(decision: .save, save: {
            do {
                try bench.save(to: file)
                return true
            } catch {
                Issue.record(error)
                return false
            }
        }))
        #expect(bench.parts.isEmpty)
        #expect(!bench.isDirty)
        #expect(bench.documentURL == nil)
        bench.undo()
        #expect(bench.parts.count == 1)
        #expect(bench.documentURL == file)
        #expect(!bench.isDirty)
    }

    @Test func openingAndReplacingKeepDocumentDestinationsSeparate() throws {
        let bench = Workbench()
        bench.add("LED", component: WorkbenchLED())
        let workflow = WorkbenchFileWorkflow()
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try bench.save(to: file)

        let switchInput = WorkbenchSwitch()
        bench.add("Switch", component: switchInput)
        bench.toggle(switchInput)
        let archive = try JSONDecoder().decode(WorkbenchArchive.self, from: Data(contentsOf: file))
        try bench.open(archive, at: file)
        #expect(!bench.isDirty)
        #expect(bench.parts.count == 1)

        let preview = try CircuitImportPreview.read("""
        (export (version D)
          (components (comp (ref R1) (value 4k7) (libsource (lib Device) (part R))))
          (nets))
        """, filenameExtension: "net")
        bench.add("LED", component: WorkbenchLED())
        #expect(!workflow.permitsLeaving(bench, decide: { .cancel }, save: { false }))
        #expect(bench.parts.count == 2)
        #expect(workflow.permitsLeaving(bench, decide: { .discard }, save: { false }))
        _ = try #require(bench.importCircuit(preview, replacing: true))
        #expect(bench.isDirty)
        #expect(bench.documentURL == nil)
        #expect(bench.parts.count == 1)
        bench.undo()
        #expect(bench.documentURL == file)
        #expect(bench.isDirty)
        bench.undo()
        #expect(!bench.isDirty)
    }

    @Test func quitStopsAtCancelAndRejectsReentrantClose() {
        let workflow = WorkbenchFileWorkflow()
        let dirty = Workbench()
        dirty.add("LED", component: WorkbenchLED())
        var prompts = 0
        let cancelledQuit = workflow.requestQuit(checks: [
            {
                workflow.permitsLeaving(dirty, decide: {
                    prompts += 1
                    #expect(!workflow.perform { Issue.record("Reentrant close ran"); return true })
                    return .cancel
                }, save: { false })
            },
            { Issue.record("Quit continued after cancellation"); return true }
        ])
        #expect(!cancelledQuit)
        #expect(prompts == 1)
        #expect(!workflow.isQuitting)
        #expect(dirty.isDirty)
        #expect(workflow.requestQuit(checks: [
            { workflow.permitsLeaving(dirty, decide: { .discard }, save: { false }) }
        ]))
        #expect(workflow.isQuitting)
        #expect(dirty.isDirty)
    }
}
